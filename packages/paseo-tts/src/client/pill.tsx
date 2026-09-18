import { useRpc, type PluginComposerPillProps } from "@getpaseo/plugin/client";
import { Icon } from "@getpaseo/plugin/client/react-native";
import { useQuery } from "@tanstack/react-query";
import { Text, View } from "react-native";
import { readState, type SpeechState } from "../shared/tts";

const IDLE: SpeechState = { phase: "idle", chunk: 0, chunks: 0, message: null };

export function SpeakPill({ theme }: PluginComposerPillProps) {
  const callState = useRpc(readState);
  const { data } = useQuery({
    queryKey: ["tts-state"],
    queryFn: () => callState({}),
    refetchInterval: 700,
    refetchIntervalInBackground: true,
  });
  const state = data ?? IDLE;

  const { icon, label, color } = describe(state, theme.colors);
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
      <Icon name={icon} size={14} color={color} />
      <Text style={{ color, fontSize: 12 }}>{label}</Text>
    </View>
  );
}

function describe(state: SpeechState, colors: PluginComposerPillProps["theme"]["colors"]) {
  switch (state.phase) {
    case "summarizing":
      return { icon: "Sparkles", label: "Resumindo…", color: colors.accent };
    case "synthesizing":
      return { icon: "LoaderCircle", label: "Gerando áudio…", color: colors.accent };
    case "speaking":
      return {
        icon: "Square",
        label: state.chunks > 1 ? `Falando ${state.chunk}/${state.chunks}` : "Falando",
        color: colors.accent,
      };
    case "error":
      return { icon: "TriangleAlert", label: "Falhou", color: colors.statusDanger };
    default:
      return { icon: "Volume2", label: "Ouvir", color: colors.foregroundMuted };
  }
}
