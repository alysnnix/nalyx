import { spawn, type ChildProcess } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SpeechState, TtsConfig } from "../shared/tts";
import { summarizeForVoice } from "./summary";
import { FFPLAY } from "./tools";

const SPEECH_ENDPOINT = "https://api.openai.com/v1/audio/speech";
const CHUNK_LIMIT = 3500;
const ERROR_LINGER_MS = 20_000;

let generation = 0;
let player: ChildProcess | null = null;
let state: SpeechState = { phase: "idle", chunk: 0, chunks: 0, message: null };
let errorClear: NodeJS.Timeout | null = null;

export function currentState(): SpeechState {
  return state;
}

export function isBusy(): boolean {
  return state.phase === "summarizing" || state.phase === "synthesizing" || state.phase === "speaking";
}

/** Stops playback, invalidates work in flight, and clears any lingering error. */
export function stop(): boolean {
  const wasBusy = isBusy();
  generation += 1;
  player?.kill("SIGKILL");
  player = null;
  setState({ phase: "idle", chunk: 0, chunks: 0, message: null });
  return wasBusy;
}

/**
 * Runs the whole pipeline for one answer and resolves when audio actually starts playing, so a
 * caller's pending state covers summarization and the first synthesis instead of lying about it.
 */
export async function speak(
  text: string,
  config: TtsConfig,
  options: { summarize: boolean },
): Promise<number> {
  stop();
  const run = generation;

  let spoken = text;
  if (options.summarize && config.voiceSummary) {
    setState({ phase: "summarizing", chunk: 0, chunks: 0, message: null });
    try {
      spoken = await summarizeForVoice(strippedForSummary(text), config);
    } catch (error) {
      console.error("[paseo-tts]", error);
      spoken = text;
    }
    if (run !== generation) return 0;
  }

  const chunks = splitForSpeech(spokenText(spoken), config.maxCharacters);
  if (chunks.length === 0) {
    setState({ phase: "idle", chunk: 0, chunks: 0, message: null });
    return 0;
  }

  setState({ phase: "synthesizing", chunk: 1, chunks: chunks.length, message: null });
  let first: Buffer;
  try {
    first = await synthesize(chunks[0] as string, config);
  } catch (error) {
    fail(run, error);
    throw error;
  }
  if (run !== generation) return 0;

  void playSequence(chunks, first, config, run);
  return chunks.reduce((total, chunk) => total + chunk.length, 0);
}

async function playSequence(
  chunks: string[],
  first: Buffer,
  config: TtsConfig,
  run: number,
): Promise<void> {
  let audio = first;
  for (let index = 0; index < chunks.length; index += 1) {
    if (run !== generation) return;
    setState({ phase: "speaking", chunk: index + 1, chunks: chunks.length, message: null });

    const upcoming = chunks[index + 1];
    const pending =
      upcoming === undefined ? null : synthesize(upcoming, config).catch((error: unknown) => error);

    await play(audio, run);
    if (run !== generation || pending === null) break;

    const next = await pending;
    if (run !== generation) return;
    if (!Buffer.isBuffer(next)) {
      fail(run, next);
      return;
    }
    audio = next;
  }
  if (run === generation) setState({ phase: "idle", chunk: 0, chunks: 0, message: null });
}

async function synthesize(text: string, config: TtsConfig): Promise<Buffer> {
  const apiKey = await resolveApiKey();
  const body: Record<string, unknown> = {
    model: config.model,
    voice: config.voice,
    input: text,
    response_format: "mp3",
  };
  if (config.speed !== 1) body.speed = config.speed;
  if (config.model === "gpt-4o-mini-tts" && config.instructions.trim().length > 0) {
    body.instructions = config.instructions;
  }

  const response = await fetch(SPEECH_ENDPOINT, {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`OpenAI recusou a síntese (${response.status}): ${detail}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function play(audio: Buffer, run: number): Promise<void> {
  const directory = await mkdtemp(join(tmpdir(), "paseo-tts-"));
  const file = join(directory, "speech.mp3");
  await writeFile(file, audio);
  try {
    if (run !== generation) return;
    const { promise, resolve } = Promise.withResolvers<void>();
    const child = spawn(FFPLAY, ["-nodisp", "-autoexit", "-loglevel", "error", file], {
      stdio: "ignore",
      env: playbackEnv(),
    });
    player = child;
    child.once("error", (error) => {
      fail(run, new Error(`ffplay não iniciou: ${error.message}`));
      if (player === child) player = null;
      resolve();
    });
    child.once("exit", () => {
      if (player === child) player = null;
      resolve();
    });
    await promise;
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function fail(run: number, error: unknown): void {
  if (run !== generation) return;
  const message = error instanceof Error ? error.message : String(error);
  console.error("[paseo-tts]", message);
  setState({ phase: "error", chunk: 0, chunks: 0, message });
  errorClear = setTimeout(() => {
    if (state.phase === "error") setState({ phase: "idle", chunk: 0, chunks: 0, message: null });
  }, ERROR_LINGER_MS);
  errorClear.unref();
}

function setState(next: SpeechState): void {
  if (errorClear && next.phase !== "error") {
    clearTimeout(errorClear);
    errorClear = null;
  }
  state = next;
}

/**
 * The daemon is started without a session bus, so the player needs an explicit runtime directory
 * to reach the user's PipeWire/PulseAudio socket.
 */
function playbackEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  if (!env.XDG_RUNTIME_DIR && typeof process.getuid === "function") {
    env.XDG_RUNTIME_DIR = `/run/user/${process.getuid()}`;
  }
  return env;
}

let cachedKey: string | null = null;

async function resolveApiKey(): Promise<string> {
  if (cachedKey) return cachedKey;
  const fromEnv = process.env.OPENAI_API_KEY?.trim();
  if (fromEnv) {
    cachedKey = fromEnv;
    return cachedKey;
  }
  const keyFile = join(process.env.HOME ?? "", ".config", "paseo-tts", "openai-key");
  try {
    const fromFile = (await readFile(keyFile, "utf8")).trim();
    if (fromFile) {
      cachedKey = fromFile;
      return cachedKey;
    }
  } catch {
    // fall through to the explicit error below
  }
  throw new Error(`Sem chave OpenAI: defina OPENAI_API_KEY no daemon ou escreva ${keyFile}.`);
}

/** Drops what nobody wants narrated before the summarizer even sees the answer. */
export function strippedForSummary(markdown: string): string {
  return markdown
    .replace(/```[\s\S]*?```/g, "\n[trecho de código na tela]\n")
    .replace(/~~~[\s\S]*?~~~/g, "\n[trecho de código na tela]\n")
    .replace(/^\s*\|.*\|\s*$/gm, "[tabela na tela]")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Turns Markdown meant for the eye into a line a voice can read without spelling out syntax. */
export function spokenText(markdown: string): string {
  return strippedForSummary(markdown)
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " imagem ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s{0,3}>\s?/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/^\s*\d+\.\s+/gm, "")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/(\*\*|__)(.*?)\1/g, "$2")
    .replace(/(\*|_)(?=\S)(.*?)(?<=\S)\1/g, "$2")
    .replace(/\[trecho de código na tela\]/g, "Tem um trecho de código na tela para você olhar.")
    .replace(/\[tabela na tela\]/g, "Tem uma tabela na tela.")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Splits text into request-sized chunks, preferring paragraph then sentence boundaries. */
export function splitForSpeech(text: string, maxCharacters: number): string[] {
  const trimmed = text.slice(0, maxCharacters).trim();
  if (trimmed.length === 0) return [];

  const chunks: string[] = [];
  let current = "";
  for (const piece of trimmed.split(/(?<=\n\n)|(?<=[.!?…]\s)/)) {
    if (current.length + piece.length > CHUNK_LIMIT && current.trim().length > 0) {
      chunks.push(current.trim());
      current = "";
    }
    if (piece.length > CHUNK_LIMIT) {
      for (let at = 0; at < piece.length; at += CHUNK_LIMIT) {
        chunks.push(piece.slice(at, at + CHUNK_LIMIT).trim());
      }
      continue;
    }
    current += piece;
  }
  if (current.trim().length > 0) chunks.push(current.trim());
  return chunks.filter((chunk) => chunk.length > 0);
}
