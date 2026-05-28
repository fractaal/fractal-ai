import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	createAssistantMessageEventStream,
	streamSimpleOpenAICodexResponses,
	type AssistantMessage,
	type AssistantMessageEvent,
	type Context,
	type Model,
	type SimpleStreamOptions,
} from "@earendil-works/pi-ai";

const DEFAULT_FIRST_EVENT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_ATTEMPTS = 999;

class FirstEventTimeoutError extends Error {
	constructor(attempt: number, timeoutMs: number) {
		super(`Codex stream produced no first event within ${timeoutMs}ms on attempt ${attempt}`);
		this.name = "FirstEventTimeoutError";
	}
}

class RetryablePreOutputCodexError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "RetryablePreOutputCodexError";
	}
}

function parsePositiveInt(value: string | undefined, fallback: number): number {
	if (!value) return fallback;
	const parsed = Number(value);
	if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
	return Math.floor(parsed);
}

function chainAbortSignal(parent?: AbortSignal): { controller: AbortController; cleanup: () => void } {
	const controller = new AbortController();
	if (!parent) return { controller, cleanup: () => {} };

	if (parent.aborted) {
		controller.abort(parent.reason);
		return { controller, cleanup: () => {} };
	}

	const onAbort = () => controller.abort(parent.reason);
	parent.addEventListener("abort", onAbort, { once: true });
	return {
		controller,
		cleanup: () => parent.removeEventListener("abort", onAbort),
	};
}

function makeErrorMessage(model: Model<any>, errorMessage: string): AssistantMessage {
	return {
		role: "assistant",
		content: [],
		api: model.api,
		provider: model.provider,
		model: model.id,
		usage: {
			input: 0,
			output: 0,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 0,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason: "error",
		errorMessage,
		timestamp: Date.now(),
	};
}

function isRetryablePreOutputCodexError(event: AssistantMessageEvent): boolean {
	if (event.type !== "error") return false;

	const message = event.error.errorMessage ?? "";
	return (
		/previous_response_not_found/i.test(message) ||
		/previous response with id ['"][^'"]+['"] not found/i.test(message) ||
		/"param"\s*:\s*"previous_response_id"/i.test(message)
	);
}

function isFirstRealProviderEvent(event: AssistantMessageEvent): boolean {
	// The Codex SSE path emits `start` after HTTP headers/body exist but before an
	// actual SSE data event is read. Buffer `start` so a stalled body can still be
	// aborted and retried without leaving a half-started assistant message in pi.
	return event.type !== "start";
}

function streamCodexWithFirstEventWatchdog(
	model: Model<any>,
	context: Context,
	options?: SimpleStreamOptions,
) {
	const output = createAssistantMessageEventStream();
	const timeoutMs = parsePositiveInt(process.env.PI_CODEX_FIRST_EVENT_TIMEOUT_MS, DEFAULT_FIRST_EVENT_TIMEOUT_MS);
	const maxAttempts = parsePositiveInt(process.env.PI_CODEX_FIRST_EVENT_MAX_ATTEMPTS, DEFAULT_MAX_ATTEMPTS);

	void (async () => {
		let lastRetryableError: Error | undefined;

		for (let attempt = 1; attempt <= maxAttempts; attempt++) {
			if (options?.signal?.aborted) {
				const message = makeErrorMessage(model, "Request was aborted");
				message.stopReason = "aborted";
				output.push({ type: "error", reason: "aborted", error: message });
				return;
			}

			const { controller, cleanup } = chainAbortSignal(options?.signal);
			const bufferedEvents: AssistantMessageEvent[] = [];
			let sawRealProviderEvent = false;

			try {
				const attemptStream = streamSimpleOpenAICodexResponses(model as any, context, {
					...(options as any),
					signal: controller.signal,
				});

				const iterator = attemptStream[Symbol.asyncIterator]();

				while (true) {
					const nextEvent = iterator.next();
					let result: IteratorResult<AssistantMessageEvent>;

					if (sawRealProviderEvent) {
						result = await nextEvent;
					} else {
						let timer: ReturnType<typeof setTimeout> | undefined;
						try {
							result = await Promise.race([
								nextEvent,
								new Promise<IteratorResult<AssistantMessageEvent>>((_, reject) => {
									timer = setTimeout(() => {
										controller.abort(new FirstEventTimeoutError(attempt, timeoutMs));
										reject(new FirstEventTimeoutError(attempt, timeoutMs));
									}, timeoutMs);
								}),
							]);
						} finally {
							if (timer) clearTimeout(timer);
						}
					}

					if (result.done) {
						if (!sawRealProviderEvent) {
							throw new FirstEventTimeoutError(attempt, timeoutMs);
						}
						return;
					}

					const event = result.value;
					if (!sawRealProviderEvent) {
						bufferedEvents.push(event);
						if (isRetryablePreOutputCodexError(event)) {
							throw new RetryablePreOutputCodexError(event.error.errorMessage ?? "Codex previous response was not found");
						}
						if (!isFirstRealProviderEvent(event)) continue;

						sawRealProviderEvent = true;
						for (const buffered of bufferedEvents) output.push(buffered);
						bufferedEvents.length = 0;
						continue;
					}

					output.push(event);
				}
			} catch (error) {
				if (options?.signal?.aborted) {
					const message = makeErrorMessage(model, "Request was aborted");
					message.stopReason = "aborted";
					output.push({ type: "error", reason: "aborted", error: message });
					return;
				}

				if (
					!sawRealProviderEvent &&
					(error instanceof FirstEventTimeoutError || error instanceof RetryablePreOutputCodexError)
				) {
					lastRetryableError = error;
					if (attempt < maxAttempts) {
						console.warn(
							`[codex-watchdog] attempt ${attempt}/${maxAttempts} failed before output (${error.message}); retrying`,
						);
						continue;
					}
				}

				const message = makeErrorMessage(model, error instanceof Error ? error.message : String(error));
				output.push({ type: "error", reason: "error", error: message });
				return;
			} finally {
				cleanup();
			}
		}

		const message = makeErrorMessage(
			model,
			lastRetryableError?.message ?? `Codex stream produced no first event after ${maxAttempts} attempts`,
		);
		output.push({ type: "error", reason: "error", error: message });
	})();

	return output;
}

export default function (pi: ExtensionAPI) {
	pi.registerProvider("openai-codex", {
		api: "openai-codex-responses",
		streamSimple: streamCodexWithFirstEventWatchdog,
	});

	pi.on("session_start", (_event, ctx) => {
		const timeoutMs = parsePositiveInt(process.env.PI_CODEX_FIRST_EVENT_TIMEOUT_MS, DEFAULT_FIRST_EVENT_TIMEOUT_MS);
		const maxAttempts = parsePositiveInt(process.env.PI_CODEX_FIRST_EVENT_MAX_ATTEMPTS, DEFAULT_MAX_ATTEMPTS);
		ctx.ui.setStatus("codex-watchdog", `codex watchdog: ${Math.round(timeoutMs / 1000)}s × ${maxAttempts}`);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus("codex-watchdog", undefined);
	});
}
