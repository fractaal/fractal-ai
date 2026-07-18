import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const ENTRY_TYPE = "codex-fast-mode";
const PROVIDER = "openai-codex";
const SUPPORTED_MODELS = new Set(["gpt-5.4", "gpt-5.5", "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra"]);

function supportsFastMode(ctx: ExtensionContext): boolean {
	return ctx.model?.provider === PROVIDER && SUPPORTED_MODELS.has(ctx.model.id);
}

function updateStatus(ctx: ExtensionContext, enabled: boolean): void {
	ctx.ui.setStatus(ENTRY_TYPE, supportsFastMode(ctx) ? `Fast ${enabled ? "on" : "off"}` : undefined);
}

export default function codexFastModeExtension(pi: ExtensionAPI) {
	let enabled = false;

	function restoreState(ctx: ExtensionContext): void {
		enabled = false;
		for (const entry of ctx.sessionManager.getBranch()) {
			if (
				entry.type === "custom" &&
				entry.customType === ENTRY_TYPE &&
				typeof entry.data === "object" &&
				entry.data !== null &&
				"enabled" in entry.data &&
				typeof entry.data.enabled === "boolean"
			) {
				enabled = entry.data.enabled;
			}
		}
		updateStatus(ctx, enabled);
	}

	pi.on("session_start", (_event, ctx) => {
		restoreState(ctx);
	});

	pi.on("session_tree", (_event, ctx) => {
		restoreState(ctx);
	});

	pi.on("model_select", (_event, ctx) => {
		updateStatus(ctx, enabled);
	});

	pi.on("before_provider_request", (event, ctx) => {
		if (!enabled || !supportsFastMode(ctx)) return;
		if (typeof event.payload !== "object" || event.payload === null || Array.isArray(event.payload)) return;
		return { ...event.payload, service_tier: "priority" };
	});

	pi.registerCommand("fast", {
		description: "Toggle OpenAI Codex Fast mode for this session (increased plan usage).",
		handler: async (_args, ctx) => {
			if (!supportsFastMode(ctx)) {
				ctx.ui.notify(`Fast mode is unavailable for ${ctx.model?.id ?? "the current model"}.`, "warning");
				return;
			}

			enabled = !enabled;
			pi.appendEntry(ENTRY_TYPE, { enabled });
			updateStatus(ctx, enabled);
			ctx.ui.notify(
				enabled ? "Fast mode enabled with increased plan usage." : "Fast mode disabled.",
				"info",
			);
		},
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(ENTRY_TYPE, undefined);
	});
}
