import { spawn } from "node:child_process";
import { appendFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Pi counterpart to claude/hooks/prerender-sessions.sh: keep the Obsidian
// vault's prerendered session Markdown files in sync with Pi's live transcripts
// so /read-agent-sessions search stays current without manual re-runs.
//
// Fires on `agent_end` — Pi's analogue to Claude Code's Stop event. The
// prerender script is spawned detached so it never blocks the next Pi turn;
// an in-process latch coalesces overlapping fires (the next agent_end just
// queues a single re-run after the current one returns) and skips Pi's own
// post-shutdown cleanup so we don't strand a child process at exit.

const RAS_SCRIPT = path.join(
	os.homedir(),
	".fractal-ai/skills/read-agent-sessions/scripts/read-agent-sessions",
);
const LOG_DIR = path.join(os.homedir(), ".pi", "agent", "state");
const LOG_FILE = path.join(LOG_DIR, "prerender-sessions.log");

export default function autoPrerenderExtension(pi: ExtensionAPI) {
	let running = false;
	let queued = false;
	let shuttingDown = false;

	function runPrerender(): void {
		if (shuttingDown) return;
		if (!existsSync(RAS_SCRIPT)) return;
		if (running) {
			queued = true;
			return;
		}

		running = true;

		const child = spawn(RAS_SCRIPT, ["prerender"], {
			detached: true,
			stdio: ["ignore", "pipe", "pipe"],
		});

		const chunks: Buffer[] = [];
		child.stdout?.on("data", (chunk: Buffer) => chunks.push(chunk));
		child.stderr?.on("data", (chunk: Buffer) => chunks.push(chunk));

		const finish = async () => {
			running = false;
			try {
				await mkdir(LOG_DIR, { recursive: true });
				const header = `── ${new Date().toISOString()} Pi agent_end prerender ──\n`;
				const body = Buffer.concat(chunks).toString("utf8");
				await appendFile(LOG_FILE, header + body + (body.endsWith("\n") ? "" : "\n"));
			} catch {
				// Best-effort logging — failure here must not surface in Pi.
			}
			if (queued && !shuttingDown) {
				queued = false;
				runPrerender();
			}
		};

		child.on("close", () => {
			void finish();
		});
		child.on("error", () => {
			void finish();
		});

		child.unref();
	}

	pi.on("agent_end", async () => {
		runPrerender();
	});

	pi.on("session_shutdown", async () => {
		shuttingDown = true;
		queued = false;
	});
}
