import type { PluginCleanup } from "@getpaseo/plugin";
import type { PluginClientContext } from "@getpaseo/plugin/client";
import { SpeakPill } from "./client/pill";
import { VoiceSettings } from "./client/settings";
import { speakText, stopSpeech, toggleLastAnswer } from "./shared/tts";

export default function contribute(client: PluginClientContext) {
  const registrations: PluginCleanup[] = [
    client.addSettingsScreen({
      id: "voice",
      title: "Voz",
      icon: "Volume2",
      Component: VoiceSettings,
    }),
    client.addCommandCenterItem({
      id: "speak-last",
      title: "Ouvir a última resposta",
      icon: "Volume2",
      keywords: ["tts", "voz", "falar", "audio", "speak"],
      context: "agent",
      async onSelect({ rpc, agent }) {
        await rpc(toggleLastAnswer, { agentId: agent.id });
      },
    }),
    client.addCommandCenterItem({
      id: "stop-speech",
      title: "Parar a leitura em voz alta",
      icon: "VolumeX",
      keywords: ["tts", "voz", "silenciar", "stop"],
      context: "global",
      async onSelect({ rpc }) {
        await rpc(stopSpeech, {});
      },
    }),
    client.addSlashCommand({
      name: "ouvir",
      description: "Lê em voz alta a última resposta, ou o texto informado",
      argumentHint: "[texto]",
      context: "agent",
      async onSubmit({ args, agent, rpc }) {
        if (args.length > 0) await rpc(speakText, { text: args });
        else await rpc(toggleLastAnswer, { agentId: agent.id });
      },
    }),
  ];

  const pills = new Map<string, PluginCleanup>();
  let stopped = false;

  const register = (agent: { id: string; workspaceId?: string | null }) => {
    if (stopped || !agent.workspaceId) return;
    pills.get(agent.id)?.();
    pills.set(
      agent.id,
      client.addComposerPill({
        id: "speak-last",
        title: "Ouvir a última resposta (aperte de novo para parar)",
        workspaceId: agent.workspaceId,
        agentId: agent.id,
        Component: SpeakPill,
        async onPress() {
          const result = await client.rpc(toggleLastAnswer, { agentId: agent.id });
          if (result.action === "empty") {
            throw new Error("Ainda não há resposta concluída para ler neste agente.");
          }
        },
      }),
    );
  };

  const unsubscribe = client.paseo.agents.subscribe((update) => {
    if (update.kind === "remove") {
      pills.get(update.agentId)?.();
      pills.delete(update.agentId);
      return;
    }
    register(update.agent);
  });

  void client.paseo.agents
    .list()
    .then(({ entries }) => {
      for (const entry of entries) register(entry.agent);
      return undefined;
    })
    .catch((error: unknown) => {
      if (!stopped) console.error("[paseo-tts] could not list agents", error);
    });

  return () => {
    stopped = true;
    unsubscribe();
    for (const pill of pills.values()) pill();
    pills.clear();
    for (const remove of registrations) remove();
  };
}
