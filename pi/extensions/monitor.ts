import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createInterface, type Interface as ReadlineInterface } from "node:readline";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DEFAULT_BATCH_MS = 1000;
const DEFAULT_MAX_LINES_PER_MESSAGE = 20;
const DEFAULT_MAX_BUFFER_LINES = 500;
const DEFAULT_MAX_LINE_BYTES = 4096;

type MonitorStatus = "running" | "exited" | "failed" | "error" | "stopped";
type MonitorStream = "stdout" | "stderr" | "monitor";
type StatusUiContext = {
	hasUI: boolean;
	ui: {
		setStatus: (key: string, value?: string) => void;
		theme?: { fg?: (color: string, text: string) => string };
	};
};

interface LineEntry {
	time: string;
	stream: MonitorStream;
	line: string;
}

interface Monitor {
	id: string;
	name: string;
	command: string;
	cwd: string;
	status: MonitorStatus;
	startedAt: string;
	exitedAt?: string;
	exitCode?: number | null;
	signal?: NodeJS.Signals | null;
	lineCount: number;
	droppedLineCount: number;
	lines: LineEntry[];
	pending: string[];
	deliveryErrors: LineEntry[];
	flushTimer?: NodeJS.Timeout;
	flushing: boolean;
	inject: boolean;
	batchMs: number;
	maxLinesPerMessage: number;
	maxBufferLines: number;
	maxLineBytes: number;
	process: ChildProcessWithoutNullStreams;
	stdoutReader?: ReadlineInterface;
	stderrReader?: ReadlineInterface;
	stopRequested: boolean;
	shutdown: boolean;
}

function objectSchema(properties: Record<string, unknown>, required: string[] = []) {
	return { type: "object", properties, required, additionalProperties: false };
}

function stringSchema(description: string) {
	return { type: "string", description };
}

function numberSchema(description: string) {
	return { type: "number", description };
}

function booleanSchema(description: string) {
	return { type: "boolean", description };
}

function resolveCwd(base: string, cwd?: string): string {
	if (!cwd) return base;
	const normalized = cwd.startsWith("@") ? cwd.slice(1) : cwd;
	return path.isAbsolute(normalized) ? normalized : path.resolve(base, normalized);
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
	return Math.min(max, Math.max(min, Math.trunc(value)));
}

function truncateUtf8Line(line: string, maxBytes: number): { line: string; truncated: boolean } {
	const bytes = Buffer.from(line, "utf8");
	if (bytes.length <= maxBytes) return { line, truncated: false };

	const truncated = bytes.subarray(0, maxBytes).toString("utf8").replace(/\uFFFD$/, "");
	return {
		line: `${truncated}… [line truncated to ${maxBytes} bytes from ${bytes.length} bytes]`,
		truncated: true,
	};
}

function pushTail(monitor: Monitor, entry: LineEntry) {
	monitor.lines.push(entry);
	if (monitor.lines.length > monitor.maxBufferLines) {
		monitor.lines.splice(0, monitor.lines.length - monitor.maxBufferLines);
	}
}

function sendDeferredMessage(pi: ExtensionAPI, monitor: Monitor, text: string) {
	if (monitor.shutdown) return;

	try {
		pi.sendMessage(
			{
				customType: "monitor",
				content: text,
				display: true,
				details: {
					source: "pi-monitor",
					monitorID: monitor.id,
					monitorName: monitor.name,
					command: monitor.command,
					cwd: monitor.cwd,
				},
			},
			{ deliverAs: "steer", triggerTurn: true },
		);
	} catch (error) {
		monitor.deliveryErrors.push({
			time: new Date().toISOString(),
			stream: "monitor",
			line: error instanceof Error ? error.message : String(error),
		});
	}
}

function flushPending(pi: ExtensionAPI, monitor: Monitor) {
	if (monitor.flushing) return;
	monitor.flushing = true;
	if (monitor.flushTimer) clearTimeout(monitor.flushTimer);
	monitor.flushTimer = undefined;

	try {
		while (!monitor.shutdown && monitor.pending.length > 0) {
			const lines = monitor.pending.splice(0, monitor.maxLinesPerMessage);
			const heading = [
				`Monitor ${monitor.name} (${monitor.id}) produced ${lines.length} line${lines.length === 1 ? "" : "s"}.`,
				`Command: ${monitor.command}`,
				`CWD: ${monitor.cwd}`,
				"",
			].join("\n");

			sendDeferredMessage(pi, monitor, `${heading}${lines.join("\n")}`);
		}
	} finally {
		monitor.flushing = false;
	}
}

function scheduleFlush(pi: ExtensionAPI, monitor: Monitor) {
	if (!monitor.inject || monitor.shutdown || monitor.flushTimer || monitor.flushing) return;

	if (monitor.batchMs === 0) {
		flushPending(pi, monitor);
		return;
	}

	monitor.flushTimer = setTimeout(() => flushPending(pi, monitor), monitor.batchMs);
}

function enqueueLine(pi: ExtensionAPI, monitor: Monitor, stream: MonitorStream, rawLine: string) {
	const truncated = truncateUtf8Line(rawLine, monitor.maxLineBytes);
	if (truncated.truncated) monitor.droppedLineCount += 1;

	const entry: LineEntry = {
		time: new Date().toISOString(),
		stream,
		line: truncated.line,
	};

	pushTail(monitor, entry);
	monitor.lineCount += 1;

	if (monitor.inject) {
		monitor.pending.push(`[${stream}] ${truncated.line}`);
		scheduleFlush(pi, monitor);
	}
}

function summarizeMonitor(monitor: Monitor, tail = 20) {
	return {
		id: monitor.id,
		name: monitor.name,
		command: monitor.command,
		cwd: monitor.cwd,
		status: monitor.status,
		pid: monitor.process.pid,
		startedAt: monitor.startedAt,
		exitedAt: monitor.exitedAt,
		exitCode: monitor.exitCode,
		signal: monitor.signal,
		lineCount: monitor.lineCount,
		droppedLineCount: monitor.droppedLineCount,
		pendingLines: monitor.pending.length,
		deliveryErrors: monitor.deliveryErrors,
		tail: monitor.lines.slice(-tail),
	};
}

function stopMonitor(pi: ExtensionAPI, monitor: Monitor, signal: NodeJS.Signals | string = "SIGTERM") {
	if (monitor.status !== "running") return;
	monitor.stopRequested = true;
	try {
		process.kill(-monitor.process.pid!, signal as NodeJS.Signals);
		enqueueLine(pi, monitor, "monitor", `sent ${signal}`);
	} catch (error) {
		enqueueLine(
			pi,
			monitor,
			"monitor",
			`failed to send ${signal}: ${error instanceof Error ? error.message : String(error)}`,
		);
	}
}

export default function monitorExtension(pi: ExtensionAPI) {
	const monitors = new Map<string, Monitor>();
	let latestStatusCtx: StatusUiContext | undefined;

	function rememberUi(ctx: StatusUiContext) {
		if (ctx.hasUI) latestStatusCtx = ctx;
	}

	function shortLabel(label: string, max = 34) {
		return label.length <= max ? label : `${label.slice(0, max - 1)}…`;
	}

	function formatMonitorStatus() {
		const active = [...monitors.values()].filter((monitor) => monitor.status === "running");
		if (active.length === 0) return undefined;

		if (active.length === 1) {
			const monitor = active[0]!;
			return `${monitor.stopRequested ? "monitor stopping" : "monitor"}: ${shortLabel(monitor.name)}`;
		}

		const labels = active
			.slice(0, 2)
			.map((monitor) => shortLabel(monitor.name, 18))
			.join(", ");
		const suffix = active.length > 2 ? ` +${active.length - 2}` : "";
		return `monitors: ${active.length} running (${labels}${suffix})`;
	}

	function colorMonitorStatus(ctx: StatusUiContext | undefined, text: string) {
		return ctx?.ui.theme?.fg?.("accent", text) ?? `\x1b[36m${text}\x1b[0m`;
	}

	function updateMonitorStatus(ctx?: StatusUiContext) {
		if (ctx) rememberUi(ctx);
		const statusCtx = ctx?.hasUI ? ctx : latestStatusCtx?.hasUI ? latestStatusCtx : undefined;
		const ui = statusCtx?.ui;
		if (!ui) return;
		const status = formatMonitorStatus();
		ui.setStatus("monitor", status ? colorMonitorStatus(statusCtx, status) : undefined);
	}

	function cleanupAll() {
		for (const monitor of monitors.values()) {
			monitor.shutdown = true;
			if (monitor.flushTimer) clearTimeout(monitor.flushTimer);
			monitor.stdoutReader?.close();
			monitor.stderrReader?.close();
			if (monitor.status === "running") {
				monitor.stopRequested = true;
				try {
					process.kill(-monitor.process.pid!, "SIGTERM");
				} catch {
					// Process group may already be gone.
				}
			}
		}
		monitors.clear();
	}

	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus("monitor", undefined);
		cleanupAll();
		latestStatusCtx = undefined;
	});

	pi.registerTool({
		name: "monitor_start",
		label: "Monitor Start",
		description:
			"Start an intentionally long-running shell command in the background and stream stdout/stderr back into this Pi session over time. Use for dev servers, watch-mode tests, tail -f, journalctl -f, docker/kubectl log streams, deployment logs, and persistent services. Do not use for ordinary one-shot commands that should finish; use bash for those.",
		promptSnippet:
			"Start an intentionally long-running background command and stream its output asynchronously; not for ordinary one-shot commands.",
		promptGuidelines: [
			"Use bash, not monitor_start, for ordinary one-shot commands expected to finish, including ls, rg/grep/find, git status/diff, builds, linters, formatters, migrations, scripts, and non-watch tests; give bash an appropriate timeout if needed.",
			"Use monitor_start only for intentionally long-running commands whose output needs to be watched over time or stopped later, such as dev servers, watch-mode tests, tail -f, journalctl -f, docker/kubectl log streams, deployment logs, or persistent services.",
			"Do not use monitor_start merely because a command may take a while; if final output or exit status matters, use bash.",
			"Use monitor_status or monitor_list to inspect monitors created by monitor_start, and use monitor_stop when a running monitor is no longer needed.",
		],
		parameters: objectSchema(
			{
				command: stringSchema("Shell command to run via /bin/bash -lc."),
				cwd: stringSchema("Working directory. Relative paths resolve from the current Pi cwd."),
				name: stringSchema("Human-readable monitor name."),
				inject: booleanSchema("Whether output should be queued back into the session. Defaults to true."),
				batchMs: numberSchema("Milliseconds to batch lines before delivery. Use 0 for per-line delivery. Defaults to 1000."),
				maxLinesPerMessage: numberSchema("Maximum output lines per monitor message. Defaults to 20."),
				maxBufferLines: numberSchema("Maximum lines retained for monitor_status tail output. Defaults to 500."),
				maxLineBytes: numberSchema("Maximum bytes retained per output line before truncating. Defaults to 4096."),
			},
			["command"],
		),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			rememberUi(ctx);
			const id = randomUUID().slice(0, 8);
			const cwd = resolveCwd(ctx.cwd, params.cwd);
			const child = spawn("/bin/bash", ["-lc", params.command], {
				cwd,
				detached: true,
				env: process.env,
				stdio: ["ignore", "pipe", "pipe"],
			}) as ChildProcessWithoutNullStreams;

			const monitor: Monitor = {
				id,
				name: params.name || id,
				command: params.command,
				cwd,
				status: "running",
				startedAt: new Date().toISOString(),
				lineCount: 0,
				droppedLineCount: 0,
				lines: [],
				pending: [],
				deliveryErrors: [],
				flushing: false,
				inject: params.inject !== false,
				batchMs: clampNumber(params.batchMs, DEFAULT_BATCH_MS, 0, 60_000),
				maxLinesPerMessage: clampNumber(params.maxLinesPerMessage, DEFAULT_MAX_LINES_PER_MESSAGE, 1, 200),
				maxBufferLines: clampNumber(params.maxBufferLines, DEFAULT_MAX_BUFFER_LINES, 1, 10_000),
				maxLineBytes: clampNumber(params.maxLineBytes, DEFAULT_MAX_LINE_BYTES, 128, 64 * 1024),
				process: child,
				stopRequested: false,
				shutdown: false,
			};

			monitors.set(id, monitor);
			updateMonitorStatus(ctx);

			monitor.stdoutReader = createInterface({ input: child.stdout });
			monitor.stderrReader = createInterface({ input: child.stderr });
			monitor.stdoutReader.on("line", (line) => enqueueLine(pi, monitor, "stdout", line));
			monitor.stderrReader.on("line", (line) => enqueueLine(pi, monitor, "stderr", line));

			child.on("error", (error) => {
				monitor.status = "error";
				monitor.exitedAt = new Date().toISOString();
				enqueueLine(pi, monitor, "monitor", `failed to start: ${error.message}`);
				flushPending(pi, monitor);
				if (!monitor.shutdown) updateMonitorStatus(ctx);
			});

			child.on("close", (code, signal) => {
				if (monitor.status !== "error") {
					monitor.status = monitor.stopRequested ? "stopped" : code === 0 ? "exited" : "failed";
				}
				monitor.exitedAt = new Date().toISOString();
				monitor.exitCode = code;
				monitor.signal = signal;
				enqueueLine(pi, monitor, "monitor", `exited with code ${code ?? "null"}${signal ? ` signal ${signal}` : ""}`);
				flushPending(pi, monitor);
				if (!monitor.shutdown) updateMonitorStatus(ctx);
			});

			return {
				content: [
					{
						type: "text" as const,
						text: [
							`Started monitor ${monitor.name} (${id}).`,
							`PID: ${child.pid}`,
							`CWD: ${cwd}`,
							`Deferred delivery: ${monitor.inject ? `enabled, batchMs=${monitor.batchMs}` : "disabled"}`,
							`Line cap: ${monitor.maxLineBytes} bytes; status tail buffer: ${monitor.maxBufferLines} lines.`,
							`Use monitor_status with id=${id} to inspect output, or monitor_stop to terminate it.`,
						].join("\n"),
					},
				],
				details: summarizeMonitor(monitor, 0),
			};
		},
	});

	pi.registerTool({
		name: "monitor_status",
		label: "Monitor Status",
		description: "Show status and recent output for a long-running background monitor created by monitor_start.",
		promptSnippet: "Show status and recent retained output for a monitor_start background process.",
		parameters: objectSchema(
			{
				id: stringSchema("Monitor ID returned by monitor_start."),
				tail: numberSchema("Number of recent retained lines to include. Defaults to 20."),
			},
			["id"],
		),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			rememberUi(ctx);
			const monitor = monitors.get(params.id);
			if (!monitor) {
				return { content: [{ type: "text" as const, text: `No monitor found for id ${params.id}.` }] };
			}

			flushPending(pi, monitor);
			return {
				content: [
					{
						type: "text" as const,
						text: JSON.stringify(summarizeMonitor(monitor, clampNumber(params.tail, 20, 0, 500)), null, 2),
					},
				],
				details: summarizeMonitor(monitor, 0),
			};
		},
	});

	pi.registerTool({
		name: "monitor_list",
		label: "Monitor List",
		description: "List all monitor_start background processes known to this Pi process.",
		promptSnippet: "List all monitor_start background processes known to this Pi process.",
		parameters: objectSchema({}),
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			rememberUi(ctx);
			const result = [...monitors.values()].map((monitor) => summarizeMonitor(monitor, 0));
			return {
				content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
				details: { monitors: result },
			};
		},
	});

	pi.registerTool({
		name: "monitor_stop",
		label: "Monitor Stop",
		description: "Terminate a running monitor_start background process by signaling its process group.",
		promptSnippet: "Terminate a running monitor_start background process by signaling its process group.",
		parameters: objectSchema(
			{
				id: stringSchema("Monitor ID returned by monitor_start."),
				signal: stringSchema("Signal to send to the process group. Defaults to SIGTERM."),
			},
			["id"],
		),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			rememberUi(ctx);
			const monitor = monitors.get(params.id);
			if (!monitor) {
				return { content: [{ type: "text" as const, text: `No monitor found for id ${params.id}.` }] };
			}
			if (monitor.status !== "running") {
				return { content: [{ type: "text" as const, text: `Monitor ${params.id} is already ${monitor.status}.` }] };
			}

			const signal = params.signal || "SIGTERM";
			stopMonitor(pi, monitor, signal);
			flushPending(pi, monitor);
			updateMonitorStatus(ctx);
			return {
				content: [{ type: "text" as const, text: `Sent ${signal} to monitor ${monitor.name} (${params.id}).` }],
				details: summarizeMonitor(monitor, 0),
			};
		},
	});
}
