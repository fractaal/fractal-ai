import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";

const SESSION_FORMAT =
	"#{session_name}\t#{?session_attached,●,○}\t#{W:#{?#{==:#{window_panes},1},#{pane_title},#{P:[#{pane_title}] }} | }";

interface TmuxSession {
	name: string;
	attached: string;
	titles: string;
	current: boolean;
}

type NoticeLevel = "info" | "warning" | "error";

function cleanTitles(titles: string | undefined): string {
	return (titles ?? "").replace(/ \| $/, "");
}

function notice(ctx: ExtensionContext, message: string, level: NoticeLevel = "info") {
	if (ctx.hasUI) {
		ctx.ui.notify(message, level);
		return;
	}

	const stream = level === "error" ? console.error : console.log;
	stream(message);
}

async function tmux(pi: ExtensionAPI, args: string[], timeout = 5000) {
	const result = await pi.exec("tmux", args, { timeout });
	if (result.code !== 0) {
		const details = (result.stderr || result.stdout || `exit code ${result.code}`).trim();
		throw new Error(details || `tmux ${args.join(" ")} failed`);
	}
	return result.stdout;
}

async function currentSession(pi: ExtensionAPI): Promise<string> {
	if (!process.env.TMUX) return "";
	try {
		return (await tmux(pi, ["display-message", "-p", "#{client_session}"], 2000)).trim();
	} catch {
		return "";
	}
}

async function listSessions(pi: ExtensionAPI): Promise<TmuxSession[]> {
	const current = await currentSession(pi);
	const output = await tmux(pi, ["list-sessions", "-F", SESSION_FORMAT]);

	return output
		.split(/\r?\n/)
		.filter(Boolean)
		.map((line) => {
			const [name = "", attached = "○", ...titleParts] = line.split("\t");
			const titles = cleanTitles(titleParts.join("\t"));
			return { name, attached, titles, current: name === current };
		});
}

function resolveMatches(sessions: TmuxSession[], query: string): TmuxSession[] {
	const needle = query.toLowerCase();
	const sessionMatches = sessions.filter((session) => session.name.toLowerCase().includes(needle));
	if (sessionMatches.length > 0) return sessionMatches;

	// Match pane titles only after session names, and never let the current pane's
	// just-run command make the current session look like a match.
	return sessions.filter((session) => !session.current && session.titles.toLowerCase().includes(needle));
}

function describeSession(session: TmuxSession): string {
	return `${session.name}  ${session.attached}  ${session.titles}`.trimEnd();
}

async function selectSession(
	ctx: ExtensionContext,
	sessions: TmuxSession[],
	title: string,
	help: string,
): Promise<TmuxSession | null> {
	if (!ctx.hasUI) {
		notice(ctx, `${title} requires interactive Pi TUI mode.`, "error");
		return null;
	}

	const items: SelectItem[] = sessions.map((session) => ({
		value: session.name,
		label: `${session.name}${session.current ? " (current)" : ""}  ${session.attached}`,
		description: session.titles || "(no pane titles)",
	}));

	const selectedName = await ctx.ui.custom<string | null>((tui, theme, _keybindings, done) => {
		const container = new Container();
		container.addChild(new DynamicBorder((str: string) => theme.fg("accent", str)));
		container.addChild(new Text(theme.fg("accent", theme.bold(title)), 1, 0));

		const selectList = new SelectList(items, Math.min(items.length, 12), {
			selectedPrefix: (text) => theme.fg("accent", text),
			selectedText: (text) => theme.fg("accent", text),
			description: (text) => theme.fg("muted", text),
			scrollInfo: (text) => theme.fg("dim", text),
			noMatch: (text) => theme.fg("warning", text),
		});
		selectList.onSelect = (item) => done(item.value);
		selectList.onCancel = () => done(null);
		container.addChild(selectList);

		container.addChild(new Text(theme.fg("dim", help), 1, 0));
		container.addChild(new DynamicBorder((str: string) => theme.fg("accent", str)));

		return {
			render(width: number) {
				return container.render(width);
			},
			invalidate() {
				container.invalidate();
			},
			handleInput(data: string) {
				selectList.handleInput(data);
				tui.requestRender();
			},
		};
	});

	return selectedName ? (sessions.find((session) => session.name === selectedName) ?? null) : null;
}

async function chooseSession(
	ctx: ExtensionContext,
	sessions: TmuxSession[],
	query: string,
	title: string,
	help: string,
): Promise<TmuxSession | null> {
	if (sessions.length === 0) {
		notice(ctx, "No tmux sessions found.", "warning");
		return null;
	}

	if (!query) {
		return selectSession(ctx, sessions, title, help);
	}

	const matches = resolveMatches(sessions, query);
	if (matches.length === 0) {
		notice(ctx, `${title}: no session matches '${query}'.`, "error");
		return null;
	}
	if (matches.length === 1) return matches[0]!;

	if (!ctx.hasUI) {
		notice(
			ctx,
			`${title}: '${query}' is ambiguous (${matches.map((session) => session.name).join(", ")}).`,
			"error",
		);
		return null;
	}

	return selectSession(ctx, matches, `${title}: '${query}'`, help);
}

async function joinSession(pi: ExtensionAPI, ctx: ExtensionContext, session: TmuxSession) {
	if (!process.env.TMUX) {
		notice(ctx, "/tjoin requires Pi to be running inside a tmux client.", "error");
		return;
	}

	notice(ctx, `Joining ${describeSession(session)}`, "info");
	await tmux(pi, ["switch-client", "-t", session.name]);
}

async function killSession(pi: ExtensionAPI, ctx: ExtensionContext, session: TmuxSession, force: boolean) {
	if (session.current && !force) {
		notice(ctx, `/tkill refuses to kill the current Pi tmux session '${session.name}' without --force.`, "error");
		return;
	}

	if (!ctx.hasUI) {
		notice(ctx, "/tkill requires interactive Pi TUI mode for confirmation.", "error");
		return;
	}

	const warning = session.current
		? `This is the current Pi tmux session. Killing it will terminate this Pi TUI.\n\n${describeSession(session)}`
		: describeSession(session);
	const ok = await ctx.ui.confirm("Kill tmux session?", warning);
	if (!ok) return;

	await tmux(pi, ["kill-session", "-t", session.name]);
	notice(ctx, `Killed ${describeSession(session)}`, "info");
}

function parseKillArgs(args: string): { force: boolean; query: string } {
	let query = args.trim();
	let force = false;
	const forceMatch = query.match(/^(?:--force|-f)(?:\s+|$)/);
	if (forceMatch) {
		force = true;
		query = query.slice(forceMatch[0].length).trim();
	}
	return { force, query };
}

export default function tmuxSessionsExtension(pi: ExtensionAPI) {
	pi.registerCommand("tjoin", {
		description: "Pick or match a tmux session and switch this tmux client to it",
		handler: async (args, ctx) => {
			try {
				const sessions = await listSessions(pi);
				const session = await chooseSession(
					ctx,
					sessions,
					args.trim(),
					"Join tmux session",
					"type to filter • ↑↓ navigate • enter join • esc cancel",
				);
				if (session) await joinSession(pi, ctx, session);
			} catch (error) {
				notice(ctx, `tjoin: ${error instanceof Error ? error.message : String(error)}`, "error");
			}
		},
	});

	pi.registerCommand("tkill", {
		description: "Pick or match a tmux session and kill it after confirmation",
		handler: async (args, ctx) => {
			try {
				const { force, query } = parseKillArgs(args);
				const sessions = await listSessions(pi);
				const session = await chooseSession(
					ctx,
					sessions,
					query,
					"Kill tmux session",
					"type to filter • ↑↓ navigate • enter choose • esc cancel",
				);
				if (session) await killSession(pi, ctx, session, force);
			} catch (error) {
				notice(ctx, `tkill: ${error instanceof Error ? error.message : String(error)}`, "error");
			}
		},
	});
}
