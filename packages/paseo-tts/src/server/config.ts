import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { configSchema, type TtsConfig } from "../shared/tts";

const CONFIG_PATH = join(process.env.HOME ?? ".", ".config", "paseo-tts", "config.json");

/**
 * The daemon owns the configuration so automatic reading keeps working with no app connected.
 * Unknown or corrupt values fall back to schema defaults instead of failing the read.
 */
export async function readConfig(): Promise<TtsConfig> {
  try {
    const parsed = configSchema.safeParse(JSON.parse(await readFile(CONFIG_PATH, "utf8")));
    if (parsed.success) return parsed.data;
    console.error("[paseo-tts] invalid config, using defaults", parsed.error.message);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      console.error("[paseo-tts] could not read config, using defaults", error);
    }
  }
  return configSchema.parse({});
}

export async function writeConfig(patch: Partial<TtsConfig>): Promise<TtsConfig> {
  const next = configSchema.parse({ ...(await readConfig()), ...patch });
  await mkdir(dirname(CONFIG_PATH), { recursive: true });
  await writeFile(CONFIG_PATH, `${JSON.stringify(next, null, 2)}\n`, "utf8");
  return next;
}
