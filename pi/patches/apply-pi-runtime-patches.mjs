#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { accessSync, constants, copyFileSync, existsSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { delimiter, dirname, extname, join, resolve } from "node:path";
import { homedir } from "node:os";

const PACKAGE_NAME = "@earendil-works/pi-coding-agent";

const OLD_COMPACTION_BLOCK = "    // Walk backwards from newest, accumulating estimated message sizes\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        if (entry.type !== \"message\")\n            continue;\n        // Estimate this message's size\n        const messageTokens = estimateTokens(entry.message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include any non-message entries (bash, settings, etc.)\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (prevEntry.type === \"message\") {\n            // Stop if we hit any message\n            break;\n        }\n        // Include this non-message entry (bash, settings change, etc.)\n        cutIndex--;\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isUserMessage = cutEntry.type === \"message\" && cutEntry.message.role === \"user\";\n    const turnStartIndex = isUserMessage ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isUserMessage && turnStartIndex !== -1,\n    };\n}\n";
const PREVIOUS_COMPACTION_BLOCK = "    // Walk backwards from newest, accumulating estimated message sizes.\n    // Count every entry that will later become compaction summary input, not\n    // just raw `message` entries. `custom_message` entries are valid user-role\n    // cut points and are converted to LLM messages by getMessageFromEntry(); if\n    // they are not counted here, active-goal checkpoints can be retained as\n    // \"free\" context and then explode the summarization prompt.\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        const message = getMessageFromEntryForCompaction(entry);\n        if (!message)\n            continue;\n        const messageTokens = estimateTokens(message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include adjacent metadata entries (bash,\n    // settings, custom state, etc.), but do not cross another entry that would\n    // itself become compaction summary input. That would retain uncounted\n    // custom_message/branch_summary text behind the chosen budget boundary.\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (getMessageFromEntryForCompaction(prevEntry)) {\n            break;\n        }\n        // Include this non-message entry (bash, settings change, custom state, etc.)\n        cutIndex--;\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isTurnStartEntry =\n        (cutEntry.type === \"message\" && cutEntry.message.role === \"user\") ||\n            cutEntry.type === \"branch_summary\" ||\n            cutEntry.type === \"custom_message\";\n    const turnStartIndex = isTurnStartEntry ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isTurnStartEntry && turnStartIndex !== -1,\n    };\n}\n";
const PREVIOUS_REPLAY_SAFE_COMPACTION_BLOCK = "    const messageRole = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        return typeof message?.role === \"string\" ? message.role : undefined;\n    };\n    const assistantToolCallIds = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        if (message?.role !== \"assistant\" || !Array.isArray(message.content)) {\n            return [];\n        }\n        const ids = [];\n        for (const block of message.content) {\n            if (!block || typeof block !== \"object\" || block.type !== \"toolCall\") {\n                continue;\n            }\n            if (typeof block.id === \"string\" && block.id.length > 0) {\n                ids.push(block.id);\n                continue;\n            }\n            if (typeof block.toolCallId === \"string\" && block.toolCallId.length > 0) {\n                ids.push(block.toolCallId);\n            }\n        }\n        return ids;\n    };\n    const assistantHasToolCall = (index) => assistantToolCallIds(index).length > 0;\n    const toolResultCallId = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        if (message?.role !== \"toolResult\") {\n            return undefined;\n        }\n        return typeof message.toolCallId === \"string\" && message.toolCallId.length > 0 ? message.toolCallId : undefined;\n    };\n    const toolCallIdAliases = (id) => {\n        const pipeIndex = id.indexOf(\"|\");\n        return pipeIndex > 0 ? [id, id.slice(0, pipeIndex)] : [id];\n    };\n    const toolCallIdMatches = (left, right) => {\n        const rightAliases = new Set(toolCallIdAliases(right));\n        return toolCallIdAliases(left).some((alias) => rightAliases.has(alias));\n    };\n    const findAssistantToolCallIndex = (toolCallId, beforeIndex) => {\n        for (let i = beforeIndex - 1; i >= startIndex; i--) {\n            if (assistantToolCallIds(i).some((id) => toolCallIdMatches(id, toolCallId))) {\n                return i;\n            }\n        }\n        return -1;\n    };\n    const previousMessageIndex = (beforeIndex) => {\n        for (let i = beforeIndex - 1; i >= startIndex; i--) {\n            if (getMessageFromEntryForCompaction(entries[i])) {\n                return i;\n            }\n        }\n        return -1;\n    };\n    // Walk backwards from newest, accumulating estimated message sizes.\n    // Count every entry that will later become compaction summary input, not\n    // just raw `message` entries. `custom_message` entries are valid user-role\n    // cut points and are converted to LLM messages by getMessageFromEntry(); if\n    // they are not counted here, active-goal checkpoints can be retained as\n    // \"free\" context and then explode the summarization prompt.\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        const message = getMessageFromEntryForCompaction(entry);\n        if (!message)\n            continue;\n        const messageTokens = estimateTokens(message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include adjacent metadata entries (bash,\n    // settings, custom state, etc.), but do not cross another entry that would\n    // itself become compaction summary input. That would retain uncounted\n    // custom_message/branch_summary text behind the chosen budget boundary.\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (getMessageFromEntryForCompaction(prevEntry)) {\n            break;\n        }\n        // Include this non-message entry (bash, settings change, custom state, etc.)\n        cutIndex--;\n    }\n    // Keep the literal live suffix valid for provider replay. OpenAI/Codex\n    // rejects a `toolResult`/function_call_output unless the matching assistant\n    // tool call is also present earlier in the same request. Most tool pairs are\n    // adjacent, but backgrounded tools can return several turns later, so an\n    // adjacency-only cut can leave an orphan tool result after compaction.\n    while (cutIndex > startIndex && cutIndex < endIndex) {\n        let moved = false;\n        const currentRole = messageRole(cutIndex);\n        if (currentRole === \"toolResult\") {\n            cutIndex--;\n            moved = true;\n        }\n        else {\n            const previousIndex = previousMessageIndex(cutIndex);\n            const currentIsPlainAssistant = currentRole === \"assistant\" && !assistantHasToolCall(cutIndex);\n            if (currentIsPlainAssistant && previousIndex >= startIndex && messageRole(previousIndex) === \"toolResult\") {\n                cutIndex = previousIndex;\n                moved = true;\n            }\n        }\n        for (let i = cutIndex; i < endIndex; i++) {\n            const toolCallId = toolResultCallId(i);\n            if (!toolCallId) {\n                continue;\n            }\n            const matchingCallIndex = findAssistantToolCallIndex(toolCallId, i);\n            if (matchingCallIndex === -1) {\n                // The matching tool call is already outside this compaction\n                // window, usually because an older boundary kept a delayed\n                // result without its call. Moving earlier cannot make that\n                // suffix replay-valid, so summarize the orphan result away and\n                // also summarize any immediate plain assistant follow-up that\n                // likely depended on it. If there is no safe later suffix, keep\n                // the whole window instead of materializing a broken compaction.\n                let nextIndex = i + 1;\n                while (nextIndex < endIndex) {\n                    const nextMessage = getMessageFromEntryForCompaction(entries[nextIndex]);\n                    if (!nextMessage) {\n                        nextIndex++;\n                        continue;\n                    }\n                    if (nextMessage.role === \"assistant\" && !assistantHasToolCall(nextIndex)) {\n                        nextIndex++;\n                        continue;\n                    }\n                    break;\n                }\n                cutIndex = nextIndex < endIndex ? nextIndex : startIndex;\n                moved = true;\n                break;\n            }\n            if (matchingCallIndex < cutIndex) {\n                cutIndex = matchingCallIndex;\n                moved = true;\n                break;\n            }\n        }\n        if (!moved) {\n            break;\n        }\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isTurnStartEntry =\n        (cutEntry.type === \"message\" && cutEntry.message.role === \"user\") ||\n            cutEntry.type === \"branch_summary\" ||\n            cutEntry.type === \"custom_message\";\n    const turnStartIndex = isTurnStartEntry ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isTurnStartEntry && turnStartIndex !== -1,\n    };\n}\n";
const NEW_COMPACTION_BLOCK = "    const messageRole = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        return typeof message?.role === \"string\" ? message.role : undefined;\n    };\n    const assistantToolCallIds = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        if (message?.role !== \"assistant\" || !Array.isArray(message.content)) {\n            return [];\n        }\n        const ids = [];\n        for (const block of message.content) {\n            if (!block || typeof block !== \"object\" || block.type !== \"toolCall\") {\n                continue;\n            }\n            if (typeof block.id === \"string\" && block.id.length > 0) {\n                ids.push(block.id);\n                continue;\n            }\n            if (typeof block.toolCallId === \"string\" && block.toolCallId.length > 0) {\n                ids.push(block.toolCallId);\n            }\n        }\n        return ids;\n    };\n    const assistantHasToolCall = (index) => assistantToolCallIds(index).length > 0;\n    const toolResultCallId = (index) => {\n        const message = getMessageFromEntryForCompaction(entries[index]);\n        if (message?.role !== \"toolResult\") {\n            return undefined;\n        }\n        return typeof message.toolCallId === \"string\" && message.toolCallId.length > 0 ? message.toolCallId : undefined;\n    };\n    const toolCallIdAliases = (id) => {\n        const pipeIndex = id.indexOf(\"|\");\n        return pipeIndex > 0 ? [id, id.slice(0, pipeIndex)] : [id];\n    };\n    const toolCallIdMatches = (left, right) => {\n        const rightAliases = new Set(toolCallIdAliases(right));\n        return toolCallIdAliases(left).some((alias) => rightAliases.has(alias));\n    };\n    const findAssistantToolCallIndex = (toolCallId, beforeIndex) => {\n        for (let i = beforeIndex - 1; i >= startIndex; i--) {\n            if (assistantToolCallIds(i).some((id) => toolCallIdMatches(id, toolCallId))) {\n                return i;\n            }\n        }\n        return -1;\n    };\n    const previousMessageIndex = (beforeIndex) => {\n        for (let i = beforeIndex - 1; i >= startIndex; i--) {\n            if (getMessageFromEntryForCompaction(entries[i])) {\n                return i;\n            }\n        }\n        return -1;\n    };\n    // Walk backwards from newest, accumulating estimated message sizes.\n    // Count every entry that will later become compaction summary input, not\n    // just raw `message` entries. `custom_message` entries are valid user-role\n    // cut points and are converted to LLM messages by getMessageFromEntry(); if\n    // they are not counted here, active-goal checkpoints can be retained as\n    // \"free\" context and then explode the summarization prompt.\n    let accumulatedTokens = 0;\n    let cutIndex = cutPoints[0]; // Default: keep from first message (not header)\n    for (let i = endIndex - 1; i >= startIndex; i--) {\n        const entry = entries[i];\n        const message = getMessageFromEntryForCompaction(entry);\n        if (!message)\n            continue;\n        const messageTokens = estimateTokens(message);\n        accumulatedTokens += messageTokens;\n        // Check if we've exceeded the budget\n        if (accumulatedTokens >= keepRecentTokens) {\n            // Find the closest valid cut point at or after this entry\n            for (let c = 0; c < cutPoints.length; c++) {\n                if (cutPoints[c] >= i) {\n                    cutIndex = cutPoints[c];\n                    break;\n                }\n            }\n            break;\n        }\n    }\n    // Scan backwards from cutIndex to include adjacent metadata entries (bash,\n    // settings, custom state, etc.), but do not cross another entry that would\n    // itself become compaction summary input. That would retain uncounted\n    // custom_message/branch_summary text behind the chosen budget boundary.\n    while (cutIndex > startIndex) {\n        const prevEntry = entries[cutIndex - 1];\n        // Stop at session header or compaction boundaries\n        if (prevEntry.type === \"compaction\") {\n            break;\n        }\n        if (getMessageFromEntryForCompaction(prevEntry)) {\n            break;\n        }\n        // Include this non-message entry (bash, settings change, custom state, etc.)\n        cutIndex--;\n    }\n    // Keep the literal live suffix valid for provider replay. OpenAI/Codex\n    // rejects a `toolResult`/function_call_output unless the matching assistant\n    // tool call is also present earlier in the same request. Most tool pairs are\n    // adjacent, but backgrounded tools can return several turns later, so an\n    // adjacency-only cut can leave an orphan tool result after compaction.\n    while (cutIndex > startIndex && cutIndex < endIndex) {\n        let moved = false;\n        const currentRole = messageRole(cutIndex);\n        if (currentRole === \"toolResult\") {\n            cutIndex--;\n            moved = true;\n        }\n        else {\n            const previousIndex = previousMessageIndex(cutIndex);\n            const currentIsPlainAssistant = currentRole === \"assistant\" && !assistantHasToolCall(cutIndex);\n            if (currentIsPlainAssistant && previousIndex >= startIndex && messageRole(previousIndex) === \"toolResult\") {\n                cutIndex = previousIndex;\n                moved = true;\n            }\n        }\n        for (let i = cutIndex; i < endIndex; i++) {\n            const toolCallId = toolResultCallId(i);\n            if (!toolCallId) {\n                continue;\n            }\n            const matchingCallIndex = findAssistantToolCallIndex(toolCallId, i);\n            if (matchingCallIndex === -1) {\n                // The matching tool call is already outside this compaction\n                // window, usually because an older boundary kept a delayed\n                // result without its call. Moving earlier cannot make that\n                // suffix replay-valid, so summarize the orphan result away and\n                // also summarize any immediate plain assistant follow-up that\n                // likely depended on it. If there is no safe later suffix, keep\n                // the whole window instead of materializing a broken compaction.\n                let nextIndex = i + 1;\n                while (nextIndex < endIndex) {\n                    const nextMessage = getMessageFromEntryForCompaction(entries[nextIndex]);\n                    if (!nextMessage) {\n                        nextIndex++;\n                        continue;\n                    }\n                    if (nextMessage.role === \"toolResult\") {\n                        nextIndex++;\n                        continue;\n                    }\n                    if (nextMessage.role === \"assistant\" && !assistantHasToolCall(nextIndex)) {\n                        nextIndex++;\n                        continue;\n                    }\n                    break;\n                }\n                cutIndex = nextIndex < endIndex ? nextIndex : startIndex;\n                moved = true;\n                break;\n            }\n            if (matchingCallIndex < cutIndex) {\n                cutIndex = matchingCallIndex;\n                moved = true;\n                break;\n            }\n        }\n        if (!moved) {\n            break;\n        }\n    }\n    // Determine if this is a split turn\n    const cutEntry = entries[cutIndex];\n    const isTurnStartEntry =\n        (cutEntry.type === \"message\" && cutEntry.message.role === \"user\") ||\n            cutEntry.type === \"branch_summary\" ||\n            cutEntry.type === \"custom_message\";\n    const turnStartIndex = isTurnStartEntry ? -1 : findTurnStartIndex(entries, cutIndex, startIndex);\n    return {\n        firstKeptEntryIndex: cutIndex,\n        turnStartIndex,\n        isSplitTurn: !isTurnStartEntry && turnStartIndex !== -1,\n    };\n}\n";

const PATCHES = [
	{
		name: "compaction accounting and replay-safe tail",
		target: "dist/core/compaction/compaction.js",
		backupName: "compaction.js",
		replacements: [
			{
				oldText: [OLD_COMPACTION_BLOCK, PREVIOUS_COMPACTION_BLOCK, PREVIOUS_REPLAY_SAFE_COMPACTION_BLOCK],
				newText: NEW_COMPACTION_BLOCK,
			},
		],
	},
	{
		name: "indefinite agent-level retries",
		target: "dist/core/settings-manager.js",
		backupName: "settings-manager.js",
		replacements: [
			{
				oldText: "            maxRetries: this.settings.retry?.maxRetries ?? 3,\n",
				newText: "            maxRetries: this.settings.retry?.maxRetries ?? Number.POSITIVE_INFINITY,\n",
			},
		],
	},
	{
		name: "indefinite retry lifecycle and 10s cap",
		target: "dist/core/agent-session.js",
		backupName: "agent-session.js",
		replacements: [
			{
				oldText: [
					"// ============================================================================\n// Constants\n// ============================================================================\n/** Standard thinking levels */\nconst THINKING_LEVELS = [\"off\", \"minimal\", \"low\", \"medium\", \"high\"];\n// ============================================================================\n",
					"// ============================================================================\n// Constants\n// ============================================================================\n/** Standard thinking levels */\nconst THINKING_LEVELS = [\"off\", \"minimal\", \"low\", \"medium\", \"high\"];\n/** Maximum agent-level retry backoff. Indefinite retry should keep trying, not sleep for days. */\nconst MAX_AGENT_RETRY_DELAY_MS = 60000;\n// ============================================================================\n",
				],
				newText: "// ============================================================================\n// Constants\n// ============================================================================\n/** Standard thinking levels */\nconst THINKING_LEVELS = [\"off\", \"minimal\", \"low\", \"medium\", \"high\"];\n/** Maximum agent-level retry backoff. Indefinite retry should keep trying, not sleep for days. */\nconst MAX_AGENT_RETRY_DELAY_MS = 10000;\n// ============================================================================\n",
			},
			{
				oldText: "        if (!settings.enabled || this._retryAttempt >= settings.maxRetries) {\n            return false;\n        }\n",
				newText: "        const hasRetryLimit = Number.isFinite(settings.maxRetries);\n        if (!settings.enabled || (hasRetryLimit && this._retryAttempt >= settings.maxRetries)) {\n            return false;\n        }\n",
			},
			{
				oldText: "        if (this._retryAttempt > settings.maxRetries) {\n            // Preserve the completed attempt count so post-run handling can emit the final failure.\n            this._retryAttempt--;\n            return false;\n        }\n",
				newText: "        const hasRetryLimit = Number.isFinite(settings.maxRetries);\n        if (hasRetryLimit && this._retryAttempt > settings.maxRetries) {\n            // Preserve the completed attempt count so post-run handling can emit the final failure.\n            this._retryAttempt--;\n            return false;\n        }\n",
			},
			{
				oldText: "        const delayMs = settings.baseDelayMs * 2 ** (this._retryAttempt - 1);\n",
				newText: "        const uncappedDelayMs = settings.baseDelayMs * 2 ** (this._retryAttempt - 1);\n        const delayMs = Math.min(uncappedDelayMs, MAX_AGENT_RETRY_DELAY_MS);\n",
			},
			{
				oldText: [
					"            maxAttempts: settings.maxRetries,\n",
					"            maxAttempts: hasRetryLimit ? settings.maxRetries : 0,\n",
				],
				newText: "            maxAttempts: hasRetryLimit ? settings.maxRetries : null,\n",
			},
		],
	},
	{
		name: "interactive retry infinity display",
		target: "dist/modes/interactive/interactive-mode.js",
		backupName: "interactive-mode.js",
		replacements: [
			{
				oldText: [
					"                const retryMessage = (seconds) => `Retrying (${event.attempt}/${event.maxAttempts}) in ${seconds}s... (${keyText(\"app.interrupt\")} to cancel)`;\n",
					"                const maxAttempts = event.maxAttempts > 0 ? String(event.maxAttempts) : \"∞\";\n                const retryMessage = (seconds) => `Retrying (${event.attempt}/${maxAttempts}) in ${seconds}s... (${keyText(\"app.interrupt\")} to cancel)`;\n",
				],
				newText: "                const maxAttempts = event.maxAttempts !== null && event.maxAttempts > 0 ? String(event.maxAttempts) : \"∞\";\n                const retryMessage = (seconds) => `Retrying (${event.attempt}/${maxAttempts}) in ${seconds}s... (${keyText(\"app.interrupt\")} to cancel)`;\n",
			},
		],
	},
	{
		name: "retry event type for unbounded attempts",
		target: "dist/core/agent-session.d.ts",
		backupName: "agent-session.d.ts",
		replacements: [
			{
				oldText: "    maxAttempts: number;\n",
				newText: "    maxAttempts: number | null;\n",
			},
		],
	},
	{
		name: "retry settings documentation",
		target: "docs/settings.md",
		backupName: "settings.md",
		replacements: [
			{
				oldText: "| `retry.maxRetries` | number | `3` | Maximum agent-level retry attempts |\n",
				newText: "| `retry.maxRetries` | number | `∞` when unset | Maximum agent-level retry attempts. Omit for indefinite retries; set a finite number to cap attempts. |\n",
			},
			{
				oldText: [
					"| `retry.baseDelayMs` | number | `2000` | Base delay for agent-level exponential backoff (2s, 4s, 8s) |\n",
					"| `retry.baseDelayMs` | number | `2000` | Base delay for agent-level exponential backoff (2s, 4s, 8s, capped at 60s) |\n",
				],
				newText: "| `retry.baseDelayMs` | number | `2000` | Base delay for agent-level exponential backoff (2s, 4s, 8s, capped at 10s) |\n",
			},
			{
				oldText: "    \"maxRetries\": 3,\n    \"baseDelayMs\": 2000,\n",
				newText: "    \"baseDelayMs\": 2000,\n",
			},
			{
				oldText: "  \"retry\": {\n    \"enabled\": true,\n    \"maxRetries\": 3\n  },\n",
				newText: "  \"retry\": {\n    \"enabled\": true\n  },\n",
			},
		],
	},
	{
		name: "RPC retry event documentation",
		target: "docs/rpc.md",
		backupName: "rpc.md",
		replacements: [
			{
				oldText: "  \"maxAttempts\": 3,\n  \"delayMs\": 2000,\n",
				newText: "  \"maxAttempts\": null,\n  \"delayMs\": 2000,\n",
			},
			{
				oldText: "```\n\n```json\n{\n  \"type\": \"auto_retry_end\",\n",
				newText: "```\n\n`maxAttempts` is a number when `retry.maxRetries` is configured. It is `null` for the default unbounded retry mode.\n\n```json\n{\n  \"type\": \"auto_retry_end\",\n",
			},
			{
				oldText: "On final failure (max retries exceeded):\n",
				newText: "On final failure (max retries exceeded for a finite `retry.maxRetries` setting):\n",
			},
		],
	},
	{
		name: "compaction stop-the-world barrier",
		target: "dist/core/agent-session.js",
		backupName: "agent-session-stw.js",
		replacements: [
			{
				oldText: "    // Compaction state\n    _compactionAbortController = undefined;\n    _autoCompactionAbortController = undefined;\n    _overflowRecoveryAttempted = false;\n",
				newText: "    // Compaction state\n    _compactionAbortController = undefined;\n    _autoCompactionAbortController = undefined;\n    _overflowRecoveryAttempted = false;\n    /** Stop-the-world barrier: extension-triggered turns are deferred while core compacts/retries. */\n    _compactionBarrier = undefined;\n    _deferredCompactionMessages = [];\n",
			},
			{
				oldText: "    _emitQueueUpdate() {\n        this._emit({\n            type: \"queue_update\",\n            steering: [...this._steeringMessages],\n            followUp: [...this._followUpMessages],\n        });\n    }\n    // Track last assistant message for auto-compaction check\n",
				newText: "    _emitQueueUpdate() {\n        this._emit({\n            type: \"queue_update\",\n            steering: [...this._steeringMessages],\n            followUp: [...this._followUpMessages],\n        });\n    }\n    _isCompactionBarrierActive() {\n        return this._compactionBarrier !== undefined;\n    }\n    _enterCompactionBarrier(reason, willRetry) {\n        if (this._compactionBarrier) {\n            this._compactionBarrier.reason = reason;\n            this._compactionBarrier.willRetry = this._compactionBarrier.willRetry || willRetry;\n            return;\n        }\n        this._compactionBarrier = { reason, willRetry, startedAt: Date.now() };\n        this._drainAgentQueuesForCompaction();\n    }\n    _exitCompactionBarrier(options = {}) {\n        if (!this._compactionBarrier)\n            return;\n        const flush = options.flushDeferred !== false;\n        this._compactionBarrier = undefined;\n        if (flush) {\n            this._flushDeferredCompactionMessages();\n        }\n        // If recovery failed/cancelled, keep deferred work parked instead of\n        // silently discarding it or replaying it into a still-overflowing context.\n        this._emitQueueUpdate();\n    }\n    _drainAgentQueuesForCompaction() {\n        const steering = this.agent.steeringQueue?.drain?.() ?? [];\n        const followUps = this.agent.followUpQueue?.drain?.() ?? [];\n        for (const message of steering) {\n            this._deferCompactionMessage({ type: \"agentQueued\", mode: \"steer\", message });\n        }\n        for (const message of followUps) {\n            this._deferCompactionMessage({ type: \"agentQueued\", mode: \"followUp\", message });\n        }\n        if (steering.length > 0) {\n            this._steeringMessages = [];\n        }\n        if (followUps.length > 0) {\n            this._followUpMessages = [];\n        }\n    }\n    _deferCompactionMessage(entry) {\n        this._deferredCompactionMessages.push(entry);\n        this._emitQueueUpdate();\n    }\n    _flushDeferredCompactionMessages() {\n        if (this._deferredCompactionMessages.length === 0)\n            return;\n        const deferred = this._deferredCompactionMessages;\n        this._deferredCompactionMessages = [];\n        for (const entry of deferred) {\n            if (entry.type === \"user\") {\n                if (entry.mode === \"steer\") {\n                    void this._queueSteer(entry.text, entry.images);\n                }\n                else {\n                    void this._queueFollowUp(entry.text, entry.images);\n                }\n                continue;\n            }\n            const message = entry.message;\n            if (entry.type === \"agentQueued\") {\n                if (entry.mode === \"steer\") {\n                    this.agent.steer(message);\n                }\n                else {\n                    this.agent.followUp(message);\n                }\n                continue;\n            }\n            if (entry.options?.deliverAs === \"nextTurn\") {\n                this._pendingNextTurnMessages.push(message);\n            }\n            else if (entry.options?.triggerTurn || entry.options?.deliverAs === \"followUp\") {\n                this.agent.followUp(message);\n            }\n            else if (entry.options?.deliverAs === \"steer\") {\n                this.agent.steer(message);\n            }\n            else {\n                this.agent.state.messages.push(message);\n                this.sessionManager.appendCustomMessageEntry(message.customType, message.content, message.display, message.details);\n                this._emit({ type: \"message_start\", message });\n                this._emit({ type: \"message_end\", message });\n            }\n        }\n    }\n    _shouldEnterOverflowBarrier(assistantMsg) {\n        if (!this.settingsManager.getCompactionSettings().enabled)\n            return false;\n        const contextWindow = this.model?.contextWindow ?? 0;\n        const sameModel = this.model && assistantMsg.provider === this.model.provider && assistantMsg.model === this.model.id;\n        return !!sameModel && isContextOverflow(assistantMsg, contextWindow);\n    }\n    // Track last assistant message for auto-compaction check\n",
			},
			{
				oldText: "    _handleAgentEvent = async (event) => {\n        // When a user message starts, check if it's from either queue and remove it BEFORE emitting\n",
				newText: "    _handleAgentEvent = async (event) => {\n        let preExtensionAssistantMessage;\n        if (event.type === \"message_end\" && event.message.role === \"assistant\") {\n            preExtensionAssistantMessage = structuredClone(event.message);\n            if (this._shouldEnterOverflowBarrier(preExtensionAssistantMessage)) {\n                this._enterCompactionBarrier(\"overflow\", preExtensionAssistantMessage.stopReason !== \"stop\");\n            }\n        }\n        // When a user message starts, check if it's from either queue and remove it BEFORE emitting\n",
			},
			{
				oldText: "        // Emit to extensions first\n        await this._emitExtensionEvent(event);\n        // Notify all listeners\n",
				newText: "        // Emit to extensions first\n        await this._emitExtensionEvent(event);\n        // Once core has classified an assistant message as overflow, extension\n        // hooks may observe it but may not mask or replace it before core\n        // compaction/retry handles the failure.\n        if (preExtensionAssistantMessage && this._shouldEnterOverflowBarrier(preExtensionAssistantMessage)) {\n            this._replaceMessageInPlace(event.message, preExtensionAssistantMessage);\n        }\n        // Notify all listeners\n",
			},
			{
				oldText: "            if (event.message.role === \"assistant\") {\n                this._lastAssistantMessage = event.message;\n                const assistantMsg = event.message;\n                if (assistantMsg.stopReason !== \"error\") {\n                    this._overflowRecoveryAttempted = false;\n                }\n",
				newText: "            if (event.message.role === \"assistant\") {\n                const assistantMsg = preExtensionAssistantMessage ?? event.message;\n                this._lastAssistantMessage = assistantMsg;\n                if (assistantMsg.stopReason !== \"error\") {\n                    this._overflowRecoveryAttempted = false;\n                }\n",
			},
			{
				oldText: "        if (await this._checkCompaction(msg)) {\n            return true;\n        }\n        // The agent loop drains both queues before emitting agent_end. Any messages\n        // here were queued by agent_end extension handlers and need a continuation.\n        return this.agent.hasQueuedMessages();\n",
				newText: "        if (await this._checkCompaction(msg)) {\n            return true;\n        }\n        if (this._isCompactionBarrierActive() && msg.stopReason !== \"error\") {\n            this._exitCompactionBarrier({ flushDeferred: true });\n        }\n        // The agent loop drains both queues before emitting agent_end. Any messages\n        // here were queued by agent_end extension handlers and need a continuation.\n        return this.agent.hasQueuedMessages();\n",
			},
			{
				oldText: "    async _queueSteer(text, images) {\n        this._steeringMessages.push(text);\n        this._emitQueueUpdate();\n        const content = [{ type: \"text\", text }];\n",
				newText: "    async _queueSteer(text, images) {\n        if (this._isCompactionBarrierActive()) {\n            this._deferCompactionMessage({ type: \"user\", mode: \"steer\", text, images });\n            return;\n        }\n        this._steeringMessages.push(text);\n        this._emitQueueUpdate();\n        const content = [{ type: \"text\", text }];\n",
			},
			{
				oldText: "    async _queueFollowUp(text, images) {\n        this._followUpMessages.push(text);\n        this._emitQueueUpdate();\n        const content = [{ type: \"text\", text }];\n",
				newText: "    async _queueFollowUp(text, images) {\n        if (this._isCompactionBarrierActive()) {\n            this._deferCompactionMessage({ type: \"user\", mode: \"followUp\", text, images });\n            return;\n        }\n        this._followUpMessages.push(text);\n        this._emitQueueUpdate();\n        const content = [{ type: \"text\", text }];\n",
			},
			{
				oldText: "        const appMessage = {\n            role: \"custom\",\n            customType: message.customType,\n            content: message.content,\n            display: message.display,\n            details: message.details,\n            timestamp: Date.now(),\n        };\n        if (options?.deliverAs === \"nextTurn\") {\n",
				newText: "        const appMessage = {\n            role: \"custom\",\n            customType: message.customType,\n            content: message.content,\n            display: message.display,\n            details: message.details,\n            timestamp: Date.now(),\n        };\n        if (this._isCompactionBarrierActive()) {\n            this._deferCompactionMessage({ type: \"custom\", message: appMessage, options });\n            return;\n        }\n        if (options?.deliverAs === \"nextTurn\") {\n",
			},
			{
				oldText: "        // Use prompt() with expandPromptTemplates: false to skip command handling and template expansion\n        await this.prompt(text, {\n            expandPromptTemplates: false,\n            streamingBehavior: options?.deliverAs,\n            images,\n            source: \"extension\",\n        });\n",
				newText: "        if (this._isCompactionBarrierActive()) {\n            this._deferCompactionMessage({ type: \"user\", mode: options?.deliverAs ?? \"followUp\", text, images });\n            return;\n        }\n        // Use prompt() with expandPromptTemplates: false to skip command handling and template expansion\n        await this.prompt(text, {\n            expandPromptTemplates: false,\n            streamingBehavior: options?.deliverAs,\n            images,\n            source: \"extension\",\n        });\n",
			},
			{
				oldText: "    get pendingMessageCount() {\n        return this._steeringMessages.length + this._followUpMessages.length;\n    }\n",
				newText: "    get pendingMessageCount() {\n        return this._steeringMessages.length + this._followUpMessages.length + this._deferredCompactionMessages.length;\n    }\n",
			},
			{
				oldText: "            if (this._overflowRecoveryAttempted) {\n                this._emit({\n                    type: \"compaction_end\",\n                    reason: \"overflow\",\n                    result: undefined,\n                    aborted: false,\n                    willRetry: false,\n                    errorMessage: \"Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model.\",\n                });\n                return false;\n            }\n",
				newText: "            if (this._overflowRecoveryAttempted) {\n                this._emit({\n                    type: \"compaction_end\",\n                    reason: \"overflow\",\n                    result: undefined,\n                    aborted: false,\n                    willRetry: false,\n                    errorMessage: \"Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model.\",\n                });\n                this._exitCompactionBarrier({ flushDeferred: false });\n                return false;\n            }\n",
			},
			{
				oldText: "    async _runAutoCompaction(reason, willRetry) {\n        const settings = this.settingsManager.getCompactionSettings();\n        let started = false;\n        try {\n            if (!this.model) {\n                return false;\n            }\n",
				newText: "    async _runAutoCompaction(reason, willRetry) {\n        const settings = this.settingsManager.getCompactionSettings();\n        let started = false;\n        this._enterCompactionBarrier(reason, willRetry);\n        try {\n            if (!this.model) {\n                this._exitCompactionBarrier({ flushDeferred: false });\n                return false;\n            }\n",
			},
			{
				oldText: "                if (!authResult.ok || !authResult.apiKey) {\n                    return false;\n                }\n",
				newText: "                if (!authResult.ok || !authResult.apiKey) {\n                    this._exitCompactionBarrier({ flushDeferred: false });\n                    return false;\n                }\n",
			},
			{
				oldText: "            if (!preparation) {\n                return false;\n            }\n",
				newText: "            if (!preparation) {\n                this._exitCompactionBarrier({ flushDeferred: false });\n                return false;\n            }\n",
			},
			{
				oldText: "                if (extensionResult?.cancel) {\n                    this._emit({\n                        type: \"compaction_end\",\n                        reason,\n                        result: undefined,\n                        aborted: true,\n                        willRetry: false,\n                    });\n                    return false;\n                }\n",
				newText: "                if (extensionResult?.cancel) {\n                    this._emit({\n                        type: \"compaction_end\",\n                        reason,\n                        result: undefined,\n                        aborted: true,\n                        willRetry: false,\n                    });\n                    this._exitCompactionBarrier({ flushDeferred: false });\n                    return false;\n                }\n",
			},
			{
				oldText: "            if (this._autoCompactionAbortController.signal.aborted) {\n                this._emit({\n                    type: \"compaction_end\",\n                    reason,\n                    result: undefined,\n                    aborted: true,\n                    willRetry: false,\n                });\n                return false;\n            }\n",
				newText: "            if (this._autoCompactionAbortController.signal.aborted) {\n                this._emit({\n                    type: \"compaction_end\",\n                    reason,\n                    result: undefined,\n                    aborted: true,\n                    willRetry: false,\n                });\n                this._exitCompactionBarrier({ flushDeferred: false });\n                return false;\n            }\n",
			},
			{
				oldText: "            if (willRetry) {\n                const messages = this.agent.state.messages;\n                const lastMsg = messages[messages.length - 1];\n                if (lastMsg?.role === \"assistant\" && lastMsg.stopReason === \"error\") {\n                    this.agent.state.messages = messages.slice(0, -1);\n                }\n                return true;\n            }\n            // Auto-compaction can complete while follow-up/steering/custom messages are waiting.\n            // Continue once so queued messages are delivered.\n            return this.agent.hasQueuedMessages();\n",
				newText: "            if (willRetry) {\n                const messages = this.agent.state.messages;\n                const lastMsg = messages[messages.length - 1];\n                if (lastMsg?.role === \"assistant\" && lastMsg.stopReason === \"error\") {\n                    this.agent.state.messages = messages.slice(0, -1);\n                }\n                return true;\n            }\n            this._exitCompactionBarrier({ flushDeferred: true });\n            // Auto-compaction can complete while follow-up/steering/custom messages are waiting.\n            // Continue once so queued messages are delivered.\n            return this.agent.hasQueuedMessages();\n",
			},
			{
				oldText: "        catch (error) {\n            const errorMessage = error instanceof Error ? error.message : \"compaction failed\";\n            if (started) {\n",
				newText: "        catch (error) {\n            const errorMessage = error instanceof Error ? error.message : \"compaction failed\";\n            this._exitCompactionBarrier({ flushDeferred: false });\n            if (started) {\n",
			},
			{
				oldText: "            isIdle: () => !this.isStreaming,\n",
				newText: "            isIdle: () => !this.isStreaming && !this._isCompactionBarrierActive(),\n",
			},
			{
				oldText: "            hasPendingMessages: () => this.pendingMessageCount > 0,\n",
				newText: "            hasPendingMessages: () => this.pendingMessageCount > 0 || this._isCompactionBarrierActive(),\n",
			},
			{
				oldText: "            compact: (options) => {\n                void (async () => {\n                    try {\n                        const result = await this.compact(options?.customInstructions);\n                        options?.onComplete?.(result);\n                    }\n                    catch (error) {\n                        const err = error instanceof Error ? error : new Error(String(error));\n                        options?.onError?.(err);\n                    }\n                })();\n            },\n",
				newText: "            compact: (options) => {\n                if (this._isCompactionBarrierActive()) {\n                    return;\n                }\n                void (async () => {\n                    try {\n                        const result = await this.compact(options?.customInstructions);\n                        options?.onComplete?.(result);\n                    }\n                    catch (error) {\n                        const err = error instanceof Error ? error : new Error(String(error));\n                        options?.onError?.(err);\n                    }\n                })();\n            },\n",
			},
		],
	},
];

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

function oldTextCandidates(oldText) {
	return Array.isArray(oldText) ? oldText : [oldText];
}

function applyRuntimePatch(packageRoot, pkg, patch) {
	const target = join(packageRoot, patch.target);
	if (!existsSync(target)) throw new Error(`runtime file not found for ${patch.name}: ${target}`);
	if (!statSync(target).isFile()) throw new Error(`runtime patch target is not a file for ${patch.name}: ${target}`);

	let current = readFileSync(target, "utf8");
	let next = current;
	let changed = false;

	for (const replacement of patch.replacements) {
		if (next.includes(replacement.newText)) continue;
		const oldText = oldTextCandidates(replacement.oldText).find((candidate) => next.includes(candidate));
		if (!oldText) {
			throw new Error(`expected unpatched block for ${patch.name} was not found in ${target}; Pi may have changed upstream, inspect before patching`);
		}
		next = next.replace(oldText, replacement.newText);
		changed = true;
	}

	if (!changed) {
		console.log(`[pi-runtime-patches] ok: ${patch.name} patch already present in ${pkg.name}@${pkg.version}`);
		return;
	}

	const backupDir = join(homedir(), ".pi/agent/backups/pi-runtime-patches", timestamp());
	mkdirSync(backupDir, { recursive: true });
	copyFileSync(target, join(backupDir, patch.backupName));
	writeFileSync(target, next);
	console.log(`[pi-runtime-patches] applied ${patch.name} patch to ${pkg.name}@${pkg.version}`);
	console.log(`[pi-runtime-patches] backup: ${join(backupDir, patch.backupName)}`);
}

function applyRuntimePatches(packageRoot) {
	const packageJson = join(packageRoot, "package.json");
	const pkg = JSON.parse(readFileSync(packageJson, "utf8"));
	if (pkg.name !== PACKAGE_NAME) throw new Error(`refusing to patch unexpected package ${pkg.name ?? "<unknown>"} at ${packageRoot}`);
	for (const patch of PATCHES) {
		applyRuntimePatch(packageRoot, pkg, patch);
	}
}

try {
	applyRuntimePatches(findPackageRoot());
} catch (error) {
	console.error(`[pi-runtime-patches] ERROR: ${error instanceof Error ? error.message : String(error)}`);
	process.exit(1);
}
