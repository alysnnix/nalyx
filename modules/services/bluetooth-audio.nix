# Áudio Bluetooth preso em A2DP.
#
# O headset deste desktop caía sozinho para HSP/HFP e o som virava mono em
# 8-16 kHz, abafado e arrastado. O rastro no log é sempre o mesmo par:
#
#   spa.bluez5: Failure in Bluetooth audio transport .../sep2/fd0
#   kernel: Bluetooth: hci1: SCO packet for unknown connection handle 3
#
# SCO é o transporte do perfil de headset, e é para onde o WirePlumber troca
# assim que alguém abre o microfone do fone. A troca derruba o A2DP, o nó de
# saída morre e é recriado (os índices subindo 99 -> 106 -> 112 no log são o
# mesmo nó renascendo em loop), e o áudio engasga a cada ciclo.
#
# Duas defesas, porque cada uma sozinha tem furo:
#
#   - bluez5.roles sem hsp_*/hfp_*: o perfil nem é oferecido, então não existe
#     caminho para o driver abrir SCO. É a garantia real.
#   - autoswitch-to-headset-profile = false: impede a política do WirePlumber
#     de tentar a troca, o que evita o ciclo de erro mesmo em dispositivo que
#     anuncie os perfis por conta própria.
#
# O custo é explícito: o microfone do fone Bluetooth deixa de existir. Aceitável
# aqui porque a captura já vem da webcam C920e, com o HyperX SoloCast de
# reserva, e ambos são USB.
#
# hardware.bluetooth fica declarado neste módulo em vez de herdado: o módulo do
# GNOME o liga por mkDefault, então sem isto a pilha de áudio Bluetooth sumiria
# junto se o host trocasse de desktop.
{
  lib,
  config,
  ...
}:
let
  cfg = config.modules.services.bluetoothAudio;
in
{
  options.modules.services.bluetoothAudio.enable =
    lib.mkEnableOption "Bluetooth audio restrito a A2DP, sem HSP/HFP";

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.pipewire.wireplumber.extraConfig."51-bluez-a2dp-only" = {
      "monitor.bluez.properties" = {
        "bluez5.roles" = [
          "a2dp_sink"
          "a2dp_source"
        ];
        # SBC XQ sobe a taxa do SBC quando o fone não tem codec melhor, e o
        # controle de volume por hardware evita o ganho duplicado que aparece
        # quando o WirePlumber atenua em software por cima do fone.
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-hw-volume" = true;
      };

      "wireplumber.settings" = {
        "bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
  };
}
