import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createInterface, type Interface as ReadlineInterface } from "node:readline";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DEFAULT_BATCH_MS = 1000;
const DEFAULT_MAX_LINES_PER_MESSAGE = 20;
const DEFAULT_MAX_BUFFER_LINES = 500;
const DEFAULT_MAX_LINE_BYTES = 4096;
const MAX_LINES_PER_DELIVERY_CYCLE = 64;
const MAX_STATUS_TAIL_LINES = 7;
const MAX_STATUS_TAIL_BYTES = 16 * 1024;
const MAX_STATUS_TAIL_ENTRY_BYTES = 512;
const MAX_INJECTED_LINE_BYTES = 1024;
const MAX_INJECTED_OUTPUT_LINES_PER_MONITOR = 256;
const MAX_INJECTED_OUTPUT_BYTES_PER_MONITOR = 64 * 1024;
const MAX_METADATA_BYTES = 512;
const MAX_DELIVERY_ERRORS = 5;
const MAX_STATUS_RESPONSE_BYTES = 20 * 1024;
const MAX_DEFERRED_MESSAGE_BYTES = 20 * 1024;
const MAX_MONITOR_LIST_ITEMS = 20;
const MAX_LINES_PER_SECOND = 32;
const RATE_WINDOW_MS = 1000;

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
	injectedOutputLineCount: number;
	injectedOutputByteCount: number;
	droppedLineCount: number;
	lines: LineEntry[];
	pending: string[];
	deliveryErrors: LineEntry[];
	recentLineTimes: number[];
	injectionPaused: boolean;
	guardrailTriggeredAt?: string;
	guardrailReason?: string;
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

function truncateUtf8WithSuffix(line: string, maxBytes: number, suffix: string): string {
	const bytes = Buffer.from(line, "utf8");
	if (bytes.length <= maxBytes) return line;

	const suffixBytes = Buffer.byteLength(suffix, "utf8");
	const contentBytes = Math.max(0, maxBytes - suffixBytes);
	const truncated = bytes.subarray(0, contentBytes).toString("utf8").replace(/\uFFFD$/, "");
	return `${truncated}${suffix}`;
}

function truncateUtf8Line(line: string, maxBytes: number): { line: string; truncated: boolean } {
	const bytes = Buffer.from(line, "utf8");
	if (bytes.length <= maxBytes) return { line, truncated: false };

	const suffix = `… [line truncated to ${maxBytes} bytes from ${bytes.length} bytes]`;
	return {
		line: truncateUtf8WithSuffix(line, maxBytes, suffix),
		truncated: true,
	};
}

function displayText(text: string, maxBytes = MAX_METADATA_BYTES) {
	return truncateUtf8Line(text, maxBytes).line;
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
					monitorName: displayText(monitor.name),
					command: displayText(monitor.command),
					cwd: displayText(monitor.cwd),
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

function pauseInjectionForGuardrail(pi: ExtensionAPI, monitor: Monitor, reason: string) {
	if (monitor.injectionPaused || monitor.shutdown) return;

	const triggeredAt = new Date().toISOString();
	monitor.injectionPaused = true;
	monitor.guardrailTriggeredAt = triggeredAt;
	monitor.guardrailReason = reason;
	const monitorPending = monitor.pending.filter((line) => line.startsWith("[monitor] "));
	const droppedPending = monitor.pending.length - monitorPending.length;
	monitor.pending = [];
	if (monitor.flushTimer) clearTimeout(monitor.flushTimer);
	monitor.flushTimer = undefined;

	const warning = [
		`⚠️ Monitor guardrail paused injected output for ${displayText(monitor.name)} (${monitor.id}).`,
		reason,
		"Monitors should inject sparse, high-signal events. If you are watching a chatty source, re-run this monitor with the command filtered for the signal you care about — pipe through grep, or wrap the tail in a small script that emits one compact line per meaningful event — instead of streaming raw output.",
		"The process is still running and its bounded tail buffer is still retained.",
		`Use monitor_status with id=${monitor.id} to inspect recent output, or monitor_stop if this monitor is no longer useful.`,
		`Dropped ${droppedPending} queued injected line${droppedPending === 1 ? "" : "s"} to protect session context.`,
	].join("\n");

	pushTail(monitor, { time: triggeredAt, stream: "monitor", line: warning });
	sendDeferredMessage(pi, monitor, warning);
	for (const line of monitorPending) {
		sendDeferredMessage(pi, monitor, line);
	}
}

function pruneRecentLineTimes(monitor: Monitor, now = Date.now()) {
	const cutoff = now - RATE_WINDOW_MS;
	while (monitor.recentLineTimes.length > 0 && monitor.recentLineTimes[0]! < cutoff) {
		monitor.recentLineTimes.shift();
	}
}

function recordOutputRate(pi: ExtensionAPI, monitor: Monitor, now: number) {
	monitor.recentLineTimes.push(now);
	pruneRecentLineTimes(monitor, now);

	if (monitor.inject && !monitor.injectionPaused && monitor.recentLineTimes.length > MAX_LINES_PER_SECOND) {
		pauseInjectionForGuardrail(
			pi,
			monitor,
			`Output exceeded ${MAX_LINES_PER_SECOND} lines in ${RATE_WINDOW_MS / 1000} second (${monitor.recentLineTimes.length} lines observed).`,
		);
	}
}

function recordInjectedOutputBudget(pi: ExtensionAPI, monitor: Monitor, injectedLine: string) {
	monitor.injectedOutputLineCount += 1;
	monitor.injectedOutputByteCount += Buffer.byteLength(injectedLine, "utf8") + 1;
	if (monitor.injectedOutputByteCount > MAX_INJECTED_OUTPUT_BYTES_PER_MONITOR) {
		pauseInjectionForGuardrail(
			pi,
			monitor,
			`Injected output exceeded ${MAX_INJECTED_OUTPUT_BYTES_PER_MONITOR} bytes for this monitor. Filter the monitored command for the signal you care about (e.g. pipe through grep, or a wrapper script emitting one line per event) so it injects a sparse stream rather than a raw firehose.`,
		);
		return;
	}
	if (monitor.injectedOutputLineCount > MAX_INJECTED_OUTPUT_LINES_PER_MONITOR) {
		pauseInjectionForGuardrail(
			pi,
			monitor,
			`Injected output exceeded ${MAX_INJECTED_OUTPUT_LINES_PER_MONITOR} stdout/stderr lines for this monitor. Filter the monitored command for the signal you care about (e.g. pipe through grep, or a wrapper script emitting one line per event) so it injects a sparse stream rather than a raw firehose.`,
		);
	}
}

function buildMonitorHeading(monitor: Monitor, lineCount: number) {
	return [
		`Monitor ${displayText(monitor.name)} (${monitor.id}) produced ${lineCount} line${lineCount === 1 ? "" : "s"}.`,
		"",
	].join("\n");
}

function takePendingLinesForMessage(monitor: Monitor) {
	const lines: string[] = [];
	while (monitor.pending.length > 0 && lines.length < monitor.maxLinesPerMessage) {
		const candidate = monitor.pending[0]!;
		const projectedLines = [...lines, candidate];
		const projectedText = `${buildMonitorHeading(monitor, projectedLines.length)}${projectedLines.join("\n")}`;
		if (lines.length > 0 && Buffer.byteLength(projectedText, "utf8") > MAX_DEFERRED_MESSAGE_BYTES) break;
		lines.push(monitor.pending.shift()!);
	}
	return lines;
}

function flushPending(pi: ExtensionAPI, monitor: Monitor) {
	if (monitor.flushing) return;
	monitor.flushing = true;
	if (monitor.flushTimer) clearTimeout(monitor.flushTimer);
	monitor.flushTimer = undefined;

	try {
		if (!monitor.injectionPaused && monitor.pending.length > MAX_LINES_PER_DELIVERY_CYCLE) {
			pauseInjectionForGuardrail(
				pi,
				monitor,
				`A single delivery cycle queued ${monitor.pending.length} lines, above the ${MAX_LINES_PER_DELIVERY_CYCLE}-line guardrail.`,
			);
			return;
		}

		while (!monitor.shutdown && !monitor.injectionPaused && monitor.pending.length > 0) {
			const lines = takePendingLinesForMessage(monitor);
			const heading = buildMonitorHeading(monitor, lines.length);

			sendDeferredMessage(pi, monitor, `${heading}${lines.join("\n")}`);
		}
	} finally {
		monitor.flushing = false;
	}
}

function scheduleFlush(pi: ExtensionAPI, monitor: Monitor) {
	if (!monitor.inject || monitor.injectionPaused || monitor.shutdown || monitor.flushTimer || monitor.flushing) return;

	if (monitor.batchMs === 0) {
		flushPending(pi, monitor);
		return;
	}

	monitor.flushTimer = setTimeout(() => flushPending(pi, monitor), monitor.batchMs);
}

function enqueueLine(pi: ExtensionAPI, monitor: Monitor, stream: MonitorStream, rawLine: string) {
	const now = Date.now();
	const truncated = truncateUtf8Line(rawLine, monitor.maxLineBytes);
	if (truncated.truncated) monitor.droppedLineCount += 1;

	const entry: LineEntry = {
		time: new Date().toISOString(),
		stream,
		line: truncated.line,
	};

	pushTail(monitor, entry);
	monitor.lineCount += 1;

	const injectedLine = `[${stream}] ${truncateUtf8Line(truncated.line, MAX_INJECTED_LINE_BYTES).line}`;

	if (stream !== "monitor") {
		recordOutputRate(pi, monitor, now);
		if (monitor.inject && !monitor.injectionPaused) recordInjectedOutputBudget(pi, monitor, injectedLine);
	}

	if (monitor.inject && !monitor.injectionPaused) {
		monitor.pending.push(injectedLine);
		scheduleFlush(pi, monitor);
	} else if (monitor.inject && stream === "monitor") {
		sendDeferredMessage(pi, monitor, `[monitor] ${truncated.line}`);
	}
}

function buildStatusTail(monitor: Monitor, maxEntries: number) {
	const tail: LineEntry[] = [];
	let bytes = 0;
	let omittedForByteCap = 0;

	for (const entry of monitor.lines.slice(-maxEntries).reverse()) {
		const rendered = { ...entry, line: truncateUtf8Line(entry.line, MAX_STATUS_TAIL_ENTRY_BYTES).line };
		const entryBytes = Buffer.byteLength(JSON.stringify(rendered), "utf8") + 2;
		if (tail.length > 0 && bytes + entryBytes > MAX_STATUS_TAIL_BYTES) {
			omittedForByteCap += 1;
			continue;
		}
		bytes += entryBytes;
		tail.unshift(rendered);
	}

	return { tail, bytes, omittedForByteCap };
}

function summarizeMonitor(monitor: Monitor, tail = 20) {
	pruneRecentLineTimes(monitor);
	return {
		id: monitor.id,
		name: displayText(monitor.name),
		command: displayText(monitor.command),
		cwd: displayText(monitor.cwd),
		status: monitor.status,
		pid: monitor.process.pid,
		startedAt: monitor.startedAt,
		exitedAt: monitor.exitedAt,
		exitCode: monitor.exitCode,
		signal: monitor.signal,
		lineCount: monitor.lineCount,
		injectedOutputLineCount: monitor.injectedOutputLineCount,
		injectedOutputByteCount: monitor.injectedOutputByteCount,
		droppedLineCount: monitor.droppedLineCount,
		pendingLines: monitor.pending.length,
		injectionPaused: monitor.injectionPaused,
		guardrailTriggeredAt: monitor.guardrailTriggeredAt,
		guardrailReason: monitor.guardrailReason,
		recentLinesPerSecond: monitor.recentLineTimes.length,
		deliveryErrors: monitor.deliveryErrors.slice(-MAX_DELIVERY_ERRORS).map((entry) => ({
			...entry,
			line: displayText(entry.line),
		})),
		tail: tail > 0 ? monitor.lines.slice(-tail) : [],
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
			"Start an intentionally long-running shell command in the background and stream sparse, meaningful stdout/stderr events back into this Pi session over time. Use for dev servers, watch-mode tests, persistent services, and long-running logs (tail -f, journalctl -f, docker/kubectl logs, deployment logs). Logs are usually chatty: filter the command for the signal you care about rather than streaming it raw — pipe through grep, or for a busy source point monitor_start at a small wrapper script that tails the source and emits one compact line per meaningful event. Stream a source unfiltered only when it is already naturally sparse, which is uncommon. Do not use for ordinary one-shot commands that should finish; use bash for those. Output is batched, line-limited, guarded, and retained as a tail buffer.",
		promptSnippet:
			"Start an intentionally long-running background command — a dev server, watch test, or a filtered/scripted log stream — and stream sparse, meaningful events asynchronously; not for one-shot commands.",
		promptGuidelines: [
			"Use bash, not monitor_start, for ordinary one-shot commands expected to finish, including ls, rg/grep/find, git status/diff, builds, linters, formatters, migrations, scripts, and non-watch tests; give bash an appropriate timeout if needed.",
			"Use monitor_start for intentionally long-running work whose output is watched over time or stopped later: dev servers, watch-mode tests, persistent services, and long-running logs (tail -f, journalctl -f, docker/kubectl logs, deployment logs).",
			"Logs and other chatty sources should be filtered for signal, not streamed raw. For a simple case, pipe the command through grep. For a busy source, point monitor_start at a small wrapper script that tails the source, matches only the events that matter, and emits one compact, self-contained line per event — a short TYPE prefix per line lets the reader route by event class. Aim for one emitted line per meaningful event. Stream a source unfiltered only when it is already naturally sparse, which is uncommon for real logs.",
			"Do not use monitor_start merely because a command may take a while; if final output or exit status matters, use bash.",
			`Injected output is guardrailed: more than ${MAX_LINES_PER_DELIVERY_CYCLE} queued lines in one delivery cycle, more than ${MAX_LINES_PER_SECOND} lines/second, more than ${MAX_INJECTED_OUTPUT_LINES_PER_MONITOR} total stdout/stderr lines, or more than ${MAX_INJECTED_OUTPUT_BYTES_PER_MONITOR} injected bytes pauses injection and emits a warning — filter the command at the source to stay under these.`,
			"Use monitor_status or monitor_list to inspect monitors created by monitor_start, and use monitor_stop when a running monitor is no longer needed.",
		],
		parameters: objectSchema(
			{
				command: stringSchema("Shell command to run via /bin/bash -lc."),
				cwd: stringSchema("Working directory. Relative paths resolve from the current Pi cwd."),
				name: stringSchema("Human-readable monitor name."),
				inject: booleanSchema("Whether output should be queued back into the session. Defaults to true."),
				batchMs: numberSchema("Milliseconds to batch lines before delivery. Use 0 for per-line delivery. Defaults to 1000."),
				maxLinesPerMessage: numberSchema("Maximum output lines per monitor message. Defaults to 20; capped at 64 by the sparse-output guardrail."),
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
				injectedOutputLineCount: 0,
				injectedOutputByteCount: 0,
				droppedLineCount: 0,
				lines: [],
				pending: [],
				deliveryErrors: [],
				recentLineTimes: [],
				injectionPaused: false,
				flushing: false,
				inject: params.inject !== false,
				batchMs: clampNumber(params.batchMs, DEFAULT_BATCH_MS, 0, 60_000),
				maxLinesPerMessage: clampNumber(params.maxLinesPerMessage, DEFAULT_MAX_LINES_PER_MESSAGE, 1, MAX_LINES_PER_DELIVERY_CYCLE),
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
							`Started monitor ${displayText(monitor.name)} (${id}).`,
							`PID: ${child.pid}`,
							`CWD: ${displayText(cwd)}`,
							`Deferred delivery: ${monitor.inject ? `enabled, batchMs=${monitor.batchMs}` : "disabled"}`,
							`Guardrails: pause injection above ${MAX_LINES_PER_DELIVERY_CYCLE} queued lines/delivery cycle, ${MAX_LINES_PER_SECOND} lines/second, ${MAX_INJECTED_OUTPUT_LINES_PER_MONITOR} total stdout/stderr lines, or ${MAX_INJECTED_OUTPUT_BYTES_PER_MONITOR} injected bytes.`,
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
				tail: numberSchema(`Number of recent retained lines to include. Defaults to 20; capped at ${MAX_STATUS_TAIL_LINES} by the sparse-output guardrail.`),
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
			const requestedTail = clampNumber(params.tail, 20, 0, 500);
			const cappedTail = Math.min(requestedTail, MAX_STATUS_TAIL_LINES);
			const statusTail = cappedTail > 0 ? buildStatusTail(monitor, cappedTail) : { tail: [], bytes: 0, omittedForByteCap: 0 };
			const guardrailNotes = [
				requestedTail > cappedTail
					? `Requested ${requestedTail} tail lines; returned at most ${cappedTail}. monitor_status returns a capped recent tail, not a full log — filter the monitored command for the signal you care about, or redirect its full output to a file you can read separately.`
					: undefined,
				statusTail.omittedForByteCap > 0
					? `Omitted ${statusTail.omittedForByteCap} older tail entr${statusTail.omittedForByteCap === 1 ? "y" : "ies"} to keep status output under ${MAX_STATUS_TAIL_BYTES} bytes.`
					: undefined,
			].filter((note): note is string => Boolean(note));
			const summary = {
				...summarizeMonitor(monitor, 0),
				tail: statusTail.tail,
				statusTailBytes: statusTail.bytes,
				statusTailGuardrail: guardrailNotes.length > 0 ? guardrailNotes.join(" ") : undefined,
			};
			let text = JSON.stringify(summary, null, 2);
			while (Buffer.byteLength(text, "utf8") > MAX_STATUS_RESPONSE_BYTES && summary.tail.length > 0) {
				summary.tail.shift();
				summary.statusTailGuardrail = [
					summary.statusTailGuardrail,
					`Trimmed oldest tail entries to keep the serialized status response under ${MAX_STATUS_RESPONSE_BYTES} bytes.`,
				]
					.filter(Boolean)
					.join(" ");
				text = JSON.stringify(summary, null, 2);
			}
			return {
				content: [
					{
						type: "text" as const,
						text,
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
			const all = [...monitors.values()];
			const running = all.filter((monitor) => monitor.status === "running");
			const notRunning = all.filter((monitor) => monitor.status !== "running");
			const selected =
				running.length >= MAX_MONITOR_LIST_ITEMS
					? running.slice(-MAX_MONITOR_LIST_ITEMS)
					: [...running, ...notRunning.slice(-(MAX_MONITOR_LIST_ITEMS - running.length))];
			const omitted = Math.max(0, all.length - selected.length);
			const omittedRunning = Math.max(0, running.length - selected.filter((monitor) => monitor.status === "running").length);
			const result = selected.map((monitor) => summarizeMonitor(monitor, 0));
			const summary = {
				monitors: result,
				omittedOlderMonitors: omitted,
				omittedRunningMonitors: omittedRunning,
				listGuardrail:
					omitted > 0
						? `Returned ${result.length} monitors, prioritizing running monitors; omitted ${omitted} older monitor${omitted === 1 ? "" : "s"}${omittedRunning > 0 ? ` (${omittedRunning} still running)` : ""} to keep monitor_list bounded.`
						: undefined,
			};
			return {
				content: [{ type: "text" as const, text: JSON.stringify(summary, null, 2) }],
				details: summary,
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
				content: [{ type: "text" as const, text: `Sent ${signal} to monitor ${displayText(monitor.name)} (${params.id}).` }],
				details: summarizeMonitor(monitor, 0),
			};
		},
	});
}
