import type { PluginServerContext } from "@getpaseo/plugin/server";
import { readConfig, writeConfig } from "./server/config";
import { currentState, isBusy, speak, stop } from "./server/speech";
import {
  readConfig as readConfigRpc,
  readState,
  speakText,
  stopSpeech,
  toggleLastAnswer,
  writeConfig as writeConfigRpc,
} from "./shared/tts";

/** Last completed answer per agent, so a press never depends on a timeline refetch succeeding. */
const lastAnswers = new Map<string, string>();

export default function contribute(server: PluginServerContext) {
  server.on("agent.turn_ended", async (event) => {
    if (event.outcome.kind === "canceled") return;
    const answer = lastAssistantText(event.timeline);
    console.log(`[paseo-tts] turn ended ${event.agent.id}: ${answer.length} chars`);
    if (answer.length === 0) return;
    lastAnswers.set(event.agent.id, answer);

    const config = await readConfig();
    if (config.autoSpeak) await speak(answer, config, { summarize: true }).catch(() => undefined);
  });

  server.handle(toggleLastAnswer, async ({ agentId }, { paseo }) => {
    if (isBusy()) {
      console.log(`[paseo-tts] stop requested while ${currentState().phase}`);
      stop();
      return { action: "stopped" as const, characters: 0 };
    }

    let answer = lastAnswers.get(agentId) ?? "";
    if (answer.length === 0) {
      const timeline = await paseo.agents
        .ref(agentId)
        .timeline.refetch({ direction: "tail", limit: 200 });
      answer = lastAssistantText(timeline.entries.map((entry) => entry.item));
      console.log(
        `[paseo-tts] refetched ${timeline.entries.length} entries for ${agentId}: ${answer.length} chars`,
      );
    }
    if (answer.length === 0) return { action: "empty" as const, characters: 0 };

    const characters = await speak(answer, await readConfig(), { summarize: true });
    return { action: characters > 0 ? ("speaking" as const) : ("empty" as const), characters };
  });

  server.handle(speakText, async ({ text, summarize }) => {
    const characters = await speak(text, await readConfig(), { summarize: summarize ?? false });
    return { action: characters > 0 ? ("speaking" as const) : ("empty" as const), characters };
  });

  server.handle(stopSpeech, () => ({ stopped: stop() }));
  server.handle(readState, () => currentState());
  server.handle(readConfigRpc, () => readConfig());
  server.handle(writeConfigRpc, (patch) => writeConfig(patch));

  return () => {
    stop();
    lastAnswers.clear();
  };
}

/**
 * Joins the assistant text produced after the most recent user message.
 *
 * Narrowed structurally instead of importing `AgentTimelineItem`: the plugin bundler resolves even
 * type-only imports, so a `@getpaseo/protocol` import makes the plugin unloadable unless its
 * node_modules ships with the source.
 */
function lastAssistantText(timeline: readonly unknown[]): string {
  const parts: string[] = [];
  for (const entry of timeline) {
    const item = entry as { type?: unknown; text?: unknown };
    if (item.type === "user_message") parts.length = 0;
    else if (item.type === "assistant_message" && typeof item.text === "string") {
      parts.push(item.text);
    }
  }
  return parts.join("\n\n").trim();
}
