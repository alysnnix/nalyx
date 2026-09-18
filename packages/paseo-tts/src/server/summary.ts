import { execFile } from "node:child_process";
import { tmpdir } from "node:os";
import type { TtsConfig } from "../shared/tts";
import { OMP } from "./tools";

const SYSTEM_PROMPT = [
  "Você transforma a resposta de um agente de programação em um briefing falado, em português do Brasil.",
  "Regras: prosa corrida, sem Markdown, sem listas, sem títulos, sem emoji, sem tabelas.",
  "NUNCA leia código, comandos, caminhos longos, diffs ou saída de terminal em voz alta.",
  "Quando houver código relevante, diga em uma frase o que ele faz e avise que está na tela para olhar.",
  "Priorize: o que foi feito, as conclusões, o que quebrou ou é arriscado, e o que ficou de ação.",
  "Entre 3 e 8 frases. Comece direto pelo conteúdo, sem saudação e sem dizer que isto é um resumo.",
].join(" ");

const SUMMARY_TIMEOUT_MS = 90_000;

/**
 * Rewrites an answer as something worth hearing. The agent CLI is used instead of an HTTP API
 * because the OpenAI project key on this daemon only grants access to speech models.
 */
export function summarizeForVoice(answer: string, config: TtsConfig): Promise<string> {
  const { promise, resolve, reject } = Promise.withResolvers<string>();
  const child = execFile(
    OMP,
    [
      "--print",
      "--mode",
      "text",
      "--model",
      config.summaryModel,
      "--cwd",
      tmpdir(),
      "--allow-home",
      "--system-prompt",
      SYSTEM_PROMPT,
      answer,
    ],
    { timeout: SUMMARY_TIMEOUT_MS, maxBuffer: 4 * 1024 * 1024 },
    (error, stdout) => {
      if (error) {
        reject(new Error(`Resumo para voz falhou: ${error.message}`));
        return;
      }
      const text = stdout.trim();
      if (text.length === 0) {
        reject(new Error("Resumo para voz veio vazio."));
        return;
      }
      resolve(text);
    },
  );
  child.stdin?.end();
  return promise;
}
