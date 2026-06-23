#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { accessSync, constants, copyFileSync, existsSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { delimiter, dirname, extname, join, resolve } from "node:path";
import { homedir } from "node:os";

const PACKAGE_NAME = "@earendil-works/pi-coding-agent";
const OLD_COMPACTION_BLOCK = "    // Walk backwards from newest, accumulating estimated message sizes\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        if (entry.type !== \"message\")\n            continue;\n        // Estimate this message's size\n        const messageTokens = estimateTokens(entry.message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include any non-message entries (bash, settings, etc.)\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (prevEntry.type === \"message\") {\n            // Stop if we hit any message\n            break;\n        }\n        // Include this non-message entry (bash, settings change, etc.)\n        cutIndex--;\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isUserMessage = cutEntry.type === \"message\" && cutEntry.message.role === \"user\";\n    const turnStartIndex = isUserMessage ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isUserMessage && turnStartIndex !== -1,\n    };\n}\n";
const NEW_COMPACTION_BLOCK = "    // Walk backwards from newest, accumulating estimated message sizes.\n    // Count every entry that will later become compaction summary input, not\n    // just raw `message` entries. `custom_message` entries are valid user-role\n    // cut points and are converted to LLM messages by getMessageFromEntry(); if\n    // they are not counted here, active-goal checkpoints can be retained as\n    // \"free\" context and then explode the summarization prompt.\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        const message = getMessageFromEntryForCompaction(entry);\n        if (!message)\n            continue;\n        const messageTokens = estimateTokens(message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include adjacent metadata entries (bash,\n    // settings, custom state, etc.), but do not cross another entry that would\n    // itself become compaction summary input. That would retain uncounted\n    // custom_message/branch_summary text behind the chosen budget boundary.\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (getMessageFromEntryForCompaction(prevEntry)) {\n            break;\n        }\n        // Include this non-message entry (bash, settings change, custom state, etc.)\n        cutIndex--;\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isTurnStartEntry =\n        (cutEntry.type === \"message\" && cutEntry.message.role === \"user\") ||\n            cutEntry.type === \"branch_summary\" ||\n            cutEntry.type === \"custom_message\";\n    const turnStartIndex = isTurnStartEntry ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isTurnStartEntry && turnStartIndex !== -1,\n    };\n}\n";
const PATCH_MARKER = "active-goal checkpoints can be retained as";

function executableCandidates(dir, command) {
	const base = join(dir, command);
	if (process.platform !== "win32") return [base];
	const hasExt = extname(command) !== "";
	const extensions = (process.env.PATHEXT || ".COM;.EXE;.BAT;.CMD").split(";").filter(Boolean);
	return hasExt ? [base] : [base, ...extensions.map((ext) => `${base}${ext.toLowerCase()}`), ...extensions.map((ext) => `${base}${ext.toUpperCase()}`)];
}

function findOnPath(command) {
	for (const dir of (process.env.PATH ?? "").split(delimiter)) {
		if (!dir) continue;
		for (const candidate of executableCandidates(dir, command)) {
			try {
				accessSync(candidate, constants.X_OK);
				return realpathSync(candidate);
			} catch {
				// keep looking
			}
		}
	}
	return undefined;
}

function isPiPackageRoot(dir) {
	const packageJson = join(dir, "package.json");
	if (!existsSync(packageJson)) return false;
	try {
		const pkg = JSON.parse(readFileSync(packageJson, "utf8"));
		return pkg.name === PACKAGE_NAME;
	} catch {
		return false;
	}
}

function packageRootFromCliPath(piCli) {
	let dir = dirname(piCli);
	for (let i = 0; i < 10; i += 1) {
		if (isPiPackageRoot(dir)) return dir;
		const parent = dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return undefined;
}

function commandForCmdShim(command, args) {
	if (process.platform !== "win32" || !/\.(?:cmd|bat)$/i.test(command)) return { command, args };
	const comspec = process.env.ComSpec || "cmd.exe";
	const quotedCommand = `"${command.replace(/"/g, "\"\"")}"`;
	return { command: comspec, args: ["/d", "/s", "/c", `${quotedCommand} ${args.join(" ")}`] };
}

function packageRootFromNpmGlobalRoot() {
	const npm = findOnPath(process.platform === "win32" ? "npm.cmd" : "npm") ?? findOnPath("npm");
	if (!npm) return undefined;
	try {
		const npmCommand = commandForCmdShim(npm, ["root", "-g"]);
		const npmRoot = execFileSync(npmCommand.command, npmCommand.args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
		if (!npmRoot) return undefined;
		const candidate = join(npmRoot, "@earendil-works", "pi-coding-agent");
		return isPiPackageRoot(candidate) ? realpathSync(candidate) : undefined;
	} catch {
		return undefined;
	}
}

function findPackageRoot() {
	if (process.env.PI_CODING_AGENT_ROOT) {
		const root = resolve(process.env.PI_CODING_AGENT_ROOT);
		if (!isPiPackageRoot(root)) throw new Error(`PI_CODING_AGENT_ROOT is not ${PACKAGE_NAME}: ${root}`);
		return root;
	}
	const piCli = findOnPath(process.platform === "win32" ? "pi.cmd" : "pi") ?? findOnPath("pi");
	if (piCli) {
		const fromCli = packageRootFromCliPath(piCli);
		if (fromCli) return fromCli;
	}
	const fromNpm = packageRootFromNpmGlobalRoot();
	if (fromNpm) return fromNpm;
	throw new Error(`could not locate ${PACKAGE_NAME} package root${piCli ? ` from ${piCli} or npm root -g` : " because pi was not found on PATH"}`);
}

function timestamp() {
	return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function applyCompactionPatch(packageRoot) {
	const packageJson = join(packageRoot, "package.json");
	const pkg = JSON.parse(readFileSync(packageJson, "utf8"));
	if (pkg.name !== PACKAGE_NAME) throw new Error(`refusing to patch unexpected package ${pkg.name ?? "<unknown>"} at ${packageRoot}`);
	const target = join(packageRoot, "dist/core/compaction/compaction.js");
	if (!existsSync(target)) throw new Error(`compaction runtime file not found: ${target}`);
	if (!statSync(target).isFile()) throw new Error(`compaction runtime target is not a file: ${target}`);

	const current = readFileSync(target, "utf8");
	if (current.includes(PATCH_MARKER)) {
		console.log(`[pi-runtime-patches] ok: custom_message compaction accounting patch already present in ${pkg.name}@${pkg.version}`);
		return;
	}
	if (!current.includes(OLD_COMPACTION_BLOCK)) {
		throw new Error(`expected unpatched compaction block was not found in ${target}; Pi may have changed upstream, inspect before patching`);
	}

	const backupDir = join(homedir(), ".pi/agent/backups/pi-runtime-patches", timestamp());
	mkdirSync(backupDir, { recursive: true });
	copyFileSync(target, join(backupDir, "compaction.js"));
	writeFileSync(target, current.replace(OLD_COMPACTION_BLOCK, NEW_COMPACTION_BLOCK));
	console.log(`[pi-runtime-patches] applied custom_message compaction accounting patch to ${pkg.name}@${pkg.version}`);
	console.log(`[pi-runtime-patches] backup: ${join(backupDir, "compaction.js")}`);
}

try {
	applyCompactionPatch(findPackageRoot());
} catch (error) {
	console.error(`[pi-runtime-patches] ERROR: ${error instanceof Error ? error.message : String(error)}`);
	process.exit(1);
}
