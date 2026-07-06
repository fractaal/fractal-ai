import { access, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MEMORY_BODY_LIMIT_BYTES = 50 * 1024;
const MEMORY_BLOCK_HEADING = "# memory";

function projectMemorySlug(directory: string): string {
	const absolute = path.resolve(directory);
	const parts = absolute.split(path.sep).filter(Boolean);
	return `-${parts.join("-")}`;
}

function memoryPathForDirectory(directory: string): string {
	return path.join(os.homedir(), ".claude", "projects", projectMemorySlug(directory), "memory", "MEMORY.md");
}

function findGitRoot(cwd: string): string | undefined {
	try {
		return execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], {
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
	} catch {
		return undefined;
	}
}

async function pathExists(file: string): Promise<boolean> {
	try {
		await access(file, constants.R_OK);
		return true;
	} catch {
		return false;
	}
}

async function resolveClaudeMemory(cwd: string): Promise<{ projectDirectory: string; memoryPath: string; exists: boolean }> {
	const gitRoot = findGitRoot(cwd);
	const candidates = Array.from(new Set([gitRoot, cwd].filter(Boolean) as string[]));

	for (const projectDirectory of candidates) {
		const memoryPath = memoryPathForDirectory(projectDirectory);
		if (await pathExists(memoryPath)) return { projectDirectory, memoryPath, exists: true };
	}

	const projectDirectory = gitRoot || cwd;
	return { projectDirectory, memoryPath: memoryPathForDirectory(projectDirectory), exists: false };
}

function formatKb(bytes: number): string {
	return `${(bytes / 1024).toFixed(1)}KB`;
}

function truncateUtf8(text: string, limitBytes: number): { text: string; truncated: boolean; originalBytes: number } {
	const bytes = Buffer.from(text, "utf8");
	if (bytes.length <= limitBytes) return { text, truncated: false, originalBytes: bytes.length };

	return {
		text: bytes.subarray(0, limitBytes).toString("utf8").replace(/\uFFFD$/, ""),
		truncated: true,
		originalBytes: bytes.length,
	};
}

function buildMemoryBlock(memoryPath: string, memoryText: string, originalBytes: number, truncated: boolean): string {
	const lines = [
		MEMORY_BLOCK_HEADING,
		"",
		"Your Claude Code project memories are shown below. These are durable cross-conversation context, not one-off chat history.",
		"Tend this memory garden: consult it for general project/user context, keep it current, and update it when you learn facts future sessions should not have to rediscover.",
		"When you learn durable operational facts, standing user preferences, recurring procedures, or decisions, write them back to the appropriate memory file and keep MEMORY.md as the index.",
		"Treat MEMORY.md primarily as an index: read referenced memory files before relying on detailed procedures.",
		"",
		`Contents of ${memoryPath} (durable memory index, persists across conversations):`,
		"",
		memoryText,
	];

	if (truncated) {
		lines.push(
			"",
			`WARNING: MEMORY.md is ${formatKb(originalBytes)} (body limit: ${formatKb(MEMORY_BODY_LIMIT_BYTES)}) - only part of it was loaded. Keep index entries short; move detail into topic files.`,
		);
	}

	return lines.join("\n");
}

export default function claudeMemoryExtension(pi: ExtensionAPI) {
	let lastResolved: { projectDirectory: string; memoryPath: string; exists: boolean } | undefined;

	pi.on("session_start", async (_event, ctx) => {
		lastResolved = await resolveClaudeMemory(ctx.cwd);
		if (ctx.hasUI && lastResolved.exists) {
			ctx.ui.notify(`Claude MEMORY.md will be injected from ${lastResolved.memoryPath}`, "info");
		}
	});

	pi.on("before_agent_start", async (event, ctx) => {
		const resolved = await resolveClaudeMemory(ctx.cwd);
		lastResolved = resolved;

		if (!resolved.exists) return;
		if (event.systemPrompt.includes(`${MEMORY_BLOCK_HEADING}\n`) && event.systemPrompt.includes(resolved.memoryPath)) return;

		let memoryText: string;
		try {
			memoryText = await readFile(resolved.memoryPath, "utf8");
		} catch (error: any) {
			if (error?.code === "ENOENT") return;
			throw error;
		}

		const truncated = truncateUtf8(memoryText, MEMORY_BODY_LIMIT_BYTES);
		return {
			systemPrompt: `${event.systemPrompt}\n\n${buildMemoryBlock(
				resolved.memoryPath,
				truncated.text,
				truncated.originalBytes,
				truncated.truncated,
			)}`,
		};
	});

	pi.registerCommand("claude-memory", {
		description: "Show the Claude Code MEMORY.md path Pi will inject for this cwd",
		handler: async (_args, ctx) => {
			lastResolved = await resolveClaudeMemory(ctx.cwd);
			ctx.ui.notify(
				lastResolved.exists
					? `Injecting ${lastResolved.memoryPath}`
					: `No Claude MEMORY.md found at ${lastResolved.memoryPath}`,
				lastResolved.exists ? "info" : "warning",
			);
		},
	});
}
