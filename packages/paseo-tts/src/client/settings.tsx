import { useRpc, type PluginSurfaceProps } from "@getpaseo/plugin/client";
import {
  SettingsAction,
  SettingsCard,
  SettingsInput,
  SettingsRow,
  SettingsSection,
  SettingsSelect,
  SettingsSwitch,
} from "@getpaseo/plugin/client/ui";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Text, View } from "react-native";
import {
  MODELS,
  SUMMARY_MODELS,
  VOICES,
  readConfig,
  speakText,
  stopSpeech,
  writeConfig,
  type TtsConfig,
} from "../shared/tts";

const SPEED_OPTIONS = ["0.8", "0.9", "1", "1.1", "1.25", "1.5"].map((value) => ({
  label: `${value}x`,
  value,
}));

const SAMPLE = "Beleza, é assim que eu vou soar quando ler a resposta do agente pra você.";

export function VoiceSettings({ theme }: PluginSurfaceProps) {
  const callRead = useRpc(readConfig);
  const callWrite = useRpc(writeConfig);
  const callSpeakText = useRpc(speakText);
  const callStop = useRpc(stopSpeech);
  const queries = useQueryClient();

  const config = useQuery({ queryKey: ["tts-config"], queryFn: () => callRead({}) });
  const save = useMutation({
    mutationFn: (patch: Partial<TtsConfig>) => callWrite(patch),
    onSuccess: (next) => queries.setQueryData(["tts-config"], next),
  });

  if (!config.data) {
    return (
      <SettingsSection title="Voz">
        <SettingsCard>
          <SettingsRow
            label={config.error ? "Não consegui ler a configuração" : "Carregando…"}
            error={config.error ? config.error.message : undefined}
          />
        </SettingsCard>
      </SettingsSection>
    );
  }

  const values = config.data;

  return (
    <View>
      <SettingsSection title="Voz">
        <SettingsCard>
          <SettingsSelect
            label="Voz"
            value={values.voice}
            options={VOICES.map((voice) => ({ label: voice, value: voice }))}
            onValueChange={(voice) => save.mutate({ voice })}
          />
          <SettingsSelect
            label="Modelo"
            hint="gpt-4o-mini-tts aceita instruções de estilo; tts-1 é mais barato e direto."
            value={values.model}
            options={MODELS.map((model) => ({ label: model, value: model }))}
            onValueChange={(model) => save.mutate({ model })}
          />
          <SettingsSelect
            label="Velocidade"
            value={String(values.speed)}
            options={SPEED_OPTIONS}
            onValueChange={(speed) => save.mutate({ speed: Number(speed) })}
          />
          <SettingsInput
            label="Instruções de estilo"
            hint="Só vale para gpt-4o-mini-tts."
            initialValue={values.instructions}
            placeholder="Fale em português do Brasil, tom natural"
            onChangeText={(instructions) => save.mutate({ instructions })}
          />
        </SettingsCard>
      </SettingsSection>

      <SettingsSection title="Comportamento">
        <SettingsCard>
          <SettingsSwitch
            label="Resumir para voz antes de falar"
            hint="Reescreve a resposta como um briefing falado: sem código, sem tabela, direto nas conclusões e nos próximos passos."
            value={values.voiceSummary}
            onValueChange={(voiceSummary) => save.mutate({ voiceSummary })}
          />
          <SettingsSelect
            label="Modelo do resumo"
            hint="Roda pelo CLI do omp, com a autenticação que já existe na máquina."
            value={values.summaryModel}
            options={SUMMARY_MODELS.map((model) => ({ label: model, value: model }))}
            onValueChange={(summaryModel) => save.mutate({ summaryModel })}
          />
          <SettingsSwitch
            label="Ler automaticamente ao fim do turno"
            hint="Toda resposta concluída é lida em voz alta, sem apertar nada."
            value={values.autoSpeak}
            onValueChange={(autoSpeak) => save.mutate({ autoSpeak })}
          />
          <SettingsAction
            label="Testar a voz"
            actionLabel="Ouvir"
            onPress={() => void callSpeakText({ text: SAMPLE })}
          />
          <SettingsAction
            label="Parar a leitura"
            actionLabel="Parar"
            onPress={() => void callStop({})}
          />
        </SettingsCard>
      </SettingsSection>

      <SettingsSection title="Como funciona">
        <SettingsCard>
          <SettingsRow label="Síntese">
            <Text style={{ color: theme.colors.foregroundMuted }}>
              OpenAI /v1/audio/speech, chamada pelo daemon.
            </Text>
          </SettingsRow>
          <SettingsRow label="Reprodução">
            <Text style={{ color: theme.colors.foregroundMuted }}>
              ffplay na máquina do daemon, não no aparelho que mostra o app.
            </Text>
          </SettingsRow>
        </SettingsCard>
      </SettingsSection>
    </View>
  );
}
