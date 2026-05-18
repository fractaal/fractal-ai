import path from "node:path";
import { completeSimple, type Message } from "@earendil-works/pi-ai";
import { buildSessionContext, convertToLlm, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

const CUSTOM_ENTRY_TYPE = "pi-auto-rename";
const DEFAULT_MIN_USER_TURNS_BETWEEN_RENAMES = 50;
const MAX_TITLE_LENGTH = 100;

const RENAME_REQUEST = `You are on an ephemeral fork whose only job is naming the current Pi conversation branch.

Return exactly one title and nothing else.
Do not call tools.

Rules:
- 3-7 words when possible.
- Specific over generic; it should make sense in a session picker six weeks from now.
- Reflect the actual focus/outcome of the conversation, not just the repository name.
- No markdown, no bullets, no quotes, no trailing period.
- Optionally prefix with exactly one of [In Progress], [Blocked], or [Complete] only when the status is obvious.
- Maximum 100 characters.

Good examples:
Vertex proxy POSTHOG_KEY wiring
[In Progress] Hyprland rice overlay bootstrap
[Complete] Pi fractal-ai MCP bridge

Bad examples:
Coding Help
Session Summary
Untitled
Working on project`;

function configuredMinTurns(): number {
	const raw = process.env.PI_AUTO_RENAME_MIN_TURNS;
	if (!raw) return DEFAULT_MIN_USER_TURNS_BETWEEN_RENAMES;
	const parsed = Number.parseInt(raw, 10);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MIN_USER_TURNS_BETWEEN_RENAMES;
}

function isBareName(name: string | undefined, sessionId: string): boolean {
	const value = (name ?? "").trim();
	if (!value) return true;
	if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) return true;
	if (/^[0-9a-f]{6,32}$/i.test(value)) return true;
	if (/^[0-9]{4,}$/.test(value)) return true;
	if (value === sessionId || value === sessionId.slice(0, 8)) return true;
	return false;
}

function sanitizeTitle(raw: string): string {
	let title = raw
		.replace(/```[a-zA-Z0-9_-]*\n?/g, "")
		.replace(/```/g, "")
		.split("\n")
		.map((line) => line.trim())
		.find(Boolean) ?? "";

	title = title
		.replace(/^title\s*:\s*/i, "")
		.replace(/^session\s*name\s*:\s*/i, "")
		.replace(/^[-*]\s+/, "")
		.replace(/[\r\n\t\x00-\x1f\x7f]+/g, " ")
		.replace(/\s+/g, " ")
		.trim();

	if ((title.startsWith('"') && title.endsWith('"')) || (title.startsWith("'") && title.endsWith("'"))) {
		title = title.slice(1, -1).trim();
	}

	if (title.length > MAX_TITLE_LENGTH) {
		title = title.slice(0, MAX_TITLE_LENGTH).replace(/\s+\S*$/, "").trim();
	}

	return title;
}

function fallbackTitle(ctx: ExtensionContext): string {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i];
		if (entry.type !== "message" || entry.message.role !== "user") continue;
		const text = messageText(entry.message);
		if (!text) continue;
		return sanitizeTitle(text).split(/\s+/).slice(0, 7).join(" ") || "Pi session";
	}
	return path.basename(ctx.cwd) || "Pi session";
}

function messageText(message: any): string {
	const content = message.content;
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((part): part is { type: string; text: string } => part?.type === "text" && typeof part.text === "string")
		.map((part) => part.text)
		.join("\n");
}

function buildEphemeralRenameMessages(ctx: ExtensionContext): Message[] {
	const sessionContext = buildSessionContext(ctx.sessionManager.getBranch());
	const llmMessages = convertToLlm(sessionContext.messages);
	if (llmMessages.length === 0) {
		throw new Error("No conversation yet");
	}

	return [
		...llmMessages,
		{
			role: "user",
			content: [{ type: "text", text: `${RENAME_REQUEST}\n\nCurrent cwd: ${ctx.cwd}` }],
			timestamp: Date.now(),
		},
	];
}

async function generateTitle(pi: ExtensionAPI, ctx: ExtensionContext): Promise<string> {
	if (!ctx.model) {
		throw new Error("No model selected");
	}

	const messages = buildEphemeralRenameMessages(ctx);
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
	if (!auth.ok) throw new Error(auth.error);
	const thinkingLevel = pi.getThinkingLevel();

	const response = await completeSimple(
		ctx.model,
		{ systemPrompt: ctx.getSystemPrompt(), messages },
		{
			apiKey: auth.apiKey,
			headers: auth.headers,
			signal: ctx.signal,
			maxTokens: 64,
			timeoutMs: 30_000,
			maxRetries: 1,
			reasoning: thinkingLevel === "off" ? undefined : thinkingLevel,
			// The fork is local-only: nothing is appended to the Pi session. Reuse the
			// live session ID intentionally so provider-side cache/transport affinity stays warm.
			sessionId: ctx.sessionManager.getSessionId(),
		},
	);

	if (response.stopReason === "aborted") {
		throw new Error("Rename generation aborted");
	}

	const raw = response.content
		.filter((part): part is { type: "text"; text: string } => part.type === "text")
		.map((part) => part.text)
		.join("\n");
	const title = sanitizeTitle(raw);
	if (!title) {
		throw new Error("Model returned an empty title");
	}
	return title;
}

function userTurnCountSinceLastSessionInfo(ctx: ExtensionContext): number {
	const entries = ctx.sessionManager.getBranch();
	let lastSessionInfoIndex = -1;
	for (let i = entries.length - 1; i >= 0; i--) {
		if (entries[i]?.type === "session_info") {
			lastSessionInfoIndex = i;
			break;
		}
	}

	let count = 0;
	for (let i = lastSessionInfoIndex + 1; i < entries.length; i++) {
		const entry = entries[i];
		if (entry?.type === "message" && entry.message.role === "user") count += 1;
	}
	return count;
}

function totalUserTurns(ctx: ExtensionContext): number {
	return ctx.sessionManager
		.getBranch()
		.filter((entry) => entry.type === "message" && entry.message.role === "user").length;
}

function terminalTitle(name: string | undefined, cwd: string): string {
	const rawLabel = name?.trim() || path.basename(cwd) || cwd;
	const label = sanitizeTitle(rawLabel) || "pi";
	return `π ${label}`;
}

function updateTitle(ctx: ExtensionContext, name = ctx.sessionManager.getSessionName()): void {
	ctx.ui.setTitle(terminalTitle(name, ctx.cwd));
}

function queueTitleUpdate(ctx: ExtensionContext, name: string): void {
	setTimeout(() => {
		try {
			updateTitle(ctx, name);
		} catch {
			// The session may have been switched/reloaded before the timer fired.
		}
	}, 0);
}

function applySessionName(pi: ExtensionAPI, ctx: ExtensionContext, name: string, source: "auto" | "manual" | "generated"): void {
	const cleaned = sanitizeTitle(name);
	if (!cleaned) throw new Error("Session name cannot be empty");
	const userTurns = totalUserTurns(ctx);
	pi.setSessionName(cleaned);
	pi.appendEntry(CUSTOM_ENTRY_TYPE, { source, name: cleaned, userTurns });
	queueTitleUpdate(ctx, cleaned);
}

export default function autoRenameExtension(pi: ExtensionAPI) {
	let autoRenameInFlight = false;
	let lastAutoErrorSessionId: string | undefined;

	async function renameIntelligently(ctx: ExtensionContext, source: "auto" | "generated"): Promise<string> {
		try {
			const generated = await generateTitle(pi, ctx);
			applySessionName(pi, ctx, generated, source);
			return generated;
		} catch (error) {
			if (source === "generated") throw error;
			const fallback = fallbackTitle(ctx);
			applySessionName(pi, ctx, fallback, source);
			throw error;
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		updateTitle(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (autoRenameInFlight) return;
		if (totalUserTurns(ctx) === 0) return;

		const currentName = pi.getSessionName();
		const sessionId = ctx.sessionManager.getSessionId();
		const needsBareRename = isBareName(currentName, sessionId);
		const needsDriftRename = !needsBareRename && userTurnCountSinceLastSessionInfo(ctx) >= configuredMinTurns();
		if (!needsBareRename && !needsDriftRename) return;

		autoRenameInFlight = true;
		ctx.ui.setStatus("rename", "renaming session…");
		try {
			const name = await renameIntelligently(ctx, "auto");
			ctx.ui.notify(`Renamed session: ${name}`, "info");
			lastAutoErrorSessionId = undefined;
		} catch (error) {
			// The fallback title has already been applied. Notify once per session so a missing
			// model key does not spam every agent_end.
			if (lastAutoErrorSessionId !== sessionId) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Auto-rename used fallback title (${message})`, "warning");
				lastAutoErrorSessionId = sessionId;
			}
		} finally {
			ctx.ui.setStatus("rename", undefined);
			autoRenameInFlight = false;
		}
	});

	pi.registerCommand("rename", {
		description: "Rename the current session. Usage: /rename [explicit name]; no args generates a title.",
		handler: async (args, ctx) => {
			const explicitName = args.trim();
			try {
				if (!ctx.isIdle()) {
					ctx.ui.setStatus("rename", "waiting for current turn…");
					await ctx.waitForIdle();
				}

				ctx.ui.setStatus("rename", "renaming session…");
				if (explicitName) {
					applySessionName(pi, ctx, explicitName, "manual");
					ctx.ui.notify(`Renamed session: ${sanitizeTitle(explicitName)}`, "info");
					return;
				}

				const generated = await renameIntelligently(ctx, "generated");
				ctx.ui.notify(`Renamed session: ${generated}`, "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Rename failed: ${message}`, "error");
			} finally {
				ctx.ui.setStatus("rename", undefined);
			}
		},
	});
}
