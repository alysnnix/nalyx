import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

export const VOICES = [
  "alloy",
  "ash",
  "ballad",
  "coral",
  "echo",
  "fable",
  "nova",
  "onyx",
  "sage",
  "shimmer",
  "verse",
] as const;

export const MODELS = ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"] as const;

export const SUMMARY_MODELS = [
  "claude-haiku-4-5",
  "claude-sonnet-4-5",
  "claude-sonnet-4-6",
] as const;

export const configSchema = z.object({
  model: z.enum(MODELS).default("gpt-4o-mini-tts"),
  voice: z.enum(VOICES).default("coral"),
  speed: z.number().min(0.25).max(4).default(1.1),
  instructions: z
    .string()
    .default("Fale em português do Brasil, com tom natural, ritmo tranquilo e sem pressa."),
  autoSpeak: z.boolean().default(false),
  maxCharacters: z.number().int().min(200).max(40000).default(6000),
  /** Rewrites the answer as a spoken briefing instead of reading the raw Markdown. */
  voiceSummary: z.boolean().default(true),
  summaryModel: z.enum(SUMMARY_MODELS).default("claude-haiku-4-5"),
});

export type TtsConfig = z.output<typeof configSchema>;

export const speechStateSchema = z.object({
  phase: z.enum(["idle", "summarizing", "synthesizing", "speaking", "error"]),
  chunk: z.number().int(),
  chunks: z.number().int(),
  message: z.string().nullable(),
});

export type SpeechState = z.output<typeof speechStateSchema>;

export const readState = defineRpc({
  name: "tts.state",
  input: z.object({}),
  output: speechStateSchema,
});

export const readConfig = defineRpc({
  name: "tts.read-config",
  input: z.object({}),
  output: configSchema,
});

export const writeConfig = defineRpc({
  name: "tts.write-config",
  input: configSchema.partial(),
  output: configSchema,
});

const speechResult = z.object({
  action: z.enum(["speaking", "stopped", "empty"]),
  characters: z.number().int(),
});

/** Speaks the agent's last answer, or stops playback when something is already running. */
export const toggleLastAnswer = defineRpc({
  name: "tts.toggle-last",
  input: z.object({ agentId: z.string() }),
  output: speechResult,
});

export const speakText = defineRpc({
  name: "tts.speak-text",
  input: z.object({ text: z.string(), summarize: z.boolean().optional() }),
  output: speechResult,
});

export const stopSpeech = defineRpc({
  name: "tts.stop",
  input: z.object({}),
  output: z.object({ stopped: z.boolean() }),
});
