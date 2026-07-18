import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { clampThinkingLevel, streamOpenAIResponses } from "@earendil-works/pi-ai/compat";

export default function fastMode(pi: ExtensionAPI) {
	pi.registerProvider("aab-gateway-fast", {
		api: "aab-openai-responses-fast",
		streamSimple(model, context, options) {
			const responseModel = { ...model, api: "openai-responses" as const };
			const clampedReasoning = options?.reasoning
				? clampThinkingLevel(responseModel, options.reasoning)
				: undefined;
			const reasoningEffort = clampedReasoning === "off" ? undefined : clampedReasoning;

			return streamOpenAIResponses(responseModel, context, {
				...options,
				maxTokens: options?.maxTokens ?? model.maxTokens,
				reasoningEffort,
				serviceTier: "priority",
			});
		},
	});
}
