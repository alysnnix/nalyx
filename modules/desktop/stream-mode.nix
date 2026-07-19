{
  pkgs,
  lib,
  vars,
  config,
  ...
}:

let
  cfg = config.modules.desktop.stream-mode;

  sudoBin = "/run/wrappers/bin/sudo";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";
  rfkillBin = "${pkgs.util-linux}/bin/rfkill";

  # Economia agressiva de CPU: desliga o turbo boost e poe o EPP de todos os
  # cores em "power". Roda como root via sudo (escreve em sysfs). Cada write e
  # guardado por -e caso o path nao exista no hardware.
  batterySave = pkgs.writeShellScript "stream-battery-save" ''
    if [ -e /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
      echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      [ -e "$f" ] && echo power > "$f"
    done
  '';

  # Reverte a economia agressiva: turbo de volta e EPP em balance_performance
  # (padrao tipico do governor powersave do intel_pstate).
  batteryRestore = pkgs.writeShellScript "stream-battery-restore" ''
    if [ -e /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
      echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      [ -e "$f" ] && echo balance_performance > "$f"
    done
  '';

  # Menu TUI em loop. Roda dentro de foot, dentro de sway (kiosk, tela preta).
  # Ao abrir aplica economia de bateria; a opcao "Sair" desfaz e encerra o sway
  # (volta ao login).
  streamMenu = pkgs.writeShellApplication {
    name = "stream-menu";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.power-profiles-daemon
      pkgs.networkmanager
      pkgs.bluetuith
      pkgs.brightnessctl
      pkgs.moonlight-qt
      pkgs.fzf
      pkgs.sway
      pkgs.systemd
    ];
    text = ''
      prev_profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

      leave() {
        ${sudoBin} ${batteryRestore} || true
        powerprofilesctl set "$prev_profile" || true
        ${sudoBin} ${systemctlBin} start syncthing || true
        swaymsg exit || true
      }

      # Setup: economia agressiva de bateria + brilho inicial em 50%
      # (o refresh/resolucao ja vem do sway).
      powerprofilesctl set power-saver || true
      ${sudoBin} ${batterySave} || true
      brightnessctl set 50% || true
      ${sudoBin} ${systemctlBin} stop syncthing || true

      while true; do
        # bateria atual no cabecalho (atualiza cada vez que volta ao menu)
        bat="$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 || true)"
        header="MODO STREAM"
        [ -n "$bat" ] && header="MODO STREAM  -  bateria: $bat%"

        # rotulo do toggle reflete o estado atual do radio bluetooth
        if ${rfkillBin} list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
          bt_label="Bluetooth: desligado"
        else
          bt_label="Bluetooth: ligado"
        fi

        labels=( "Moonlight" "Brilho +" "Brilho -" "WiFi" "$bt_label" "Bluetooth (gerenciar)" "Sair" )

        # centraliza o texto na horizontal: espacos a esquerda ate o meio da
        # tela (a caixa ocupa a largura toda para nada ser cortado).
        cols="$(tput cols 2>/dev/null || echo 80)"
        maxlen=''${#header}
        for it in "''${labels[@]}"; do
          [ ''${#it} -gt "$maxlen" ] && maxlen=''${#it}
        done
        pad=$(( (cols - maxlen) / 2 ))
        [ "$pad" -lt 0 ] && pad=0
        sp="$(printf "%*s" "$pad" "")"

        # fzf em tela cheia usa a tela alternativa: menu sempre limpo e
        # centralizado na vertical (margin) e horizontal (padding).
        choice="$(for it in "''${labels[@]}"; do printf '%s%s\n' "$sp" "$it"; done \
          | fzf --layout=reverse \
                --disabled \
                --info=hidden \
                --prompt="" \
                --pointer=" " \
                --header="''${sp}$header" \
                --header-first \
                --margin=35%,0 \
                --cycle)" || continue

        case "$choice" in
          *Moonlight*)
            # logs do moonlight vao para arquivo (tela limpa + diagnostico)
            { echo "=== $(date) ==="; moonlight; } >> /tmp/moonlight.log 2>&1 || true
            ;;
          *"Brilho +"*) brightnessctl set +10% || true ;;
          *"Brilho -"*) brightnessctl set 10%- || true ;;
          *WiFi*) nmtui || true ;;
          *"gerenciar"*) bluetuith || true ;;
          *"Bluetooth: ligado"*) ${sudoBin} ${rfkillBin} block bluetooth || true ;;
          *"Bluetooth: desligado"*) ${sudoBin} ${rfkillBin} unblock bluetooth || true ;;
          *Sair*)
            leave
            break
            ;;
        esac
      done
    '';
  };

  # Config minima do sway para o modo stream (kiosk). Ao contrario do cage, o
  # sway habilita tap-to-click no touchpad e implementa os protocolos de captura
  # de input (pointer-constraints/relative-pointer/keyboard-shortcuts-inhibit)
  # que o Moonlight precisa para encaminhar teclado e mouse durante o stream.
  swayConfig = pkgs.writeText "stream-sway.conf" ''
    # O wildcard "*" garante o match do touchpad independente de como o
    # libinput o tipa (o identificador "type:touchpad" nao pegou).
    input * {
        tap enabled
        natural_scroll enabled
    }

    output * {
        mode 1920x1080@60Hz
    }

    default_border none

    bar {
        mode invisible
    }

    # Moonlight sempre fullscreen (captura teclado/mouse quando focado)
    for_window [app_id="moonlight"] fullscreen enable
    for_window [app_id="Moonlight"] fullscreen enable
    for_window [title="Moonlight"] fullscreen enable

    # Saida de emergencia caso o menu trave (encerra o sway, volta ao login)
    bindsym Mod4+Shift+q exit

    # Diagnostico temporario: despeja os inputs vistos pelo sway (para
    # descobrir o identificador/tipo do touchpad caso o tap ainda falhe).
    exec ${pkgs.sway}/bin/swaymsg -t get_inputs > /tmp/stream-inputs.json

    # Menu do modo stream, com fonte grande
    exec ${pkgs.foot}/bin/foot -o font=monospace:size=28 -e ${streamMenu}/bin/stream-menu
  '';

  # Sessao Wayland minima: sway com a config do kiosk.
  sessionLauncher = pkgs.writeShellApplication {
    name = "stream-session";
    runtimeInputs = [
      pkgs.sway
      pkgs.foot
    ];
    text = ''
      exec sway -c ${swayConfig}
    '';
  };

  streamSession =
    (pkgs.writeTextFile {
      name = "stream-session-desktop";
      destination = "/share/wayland-sessions/stream.desktop";
      text = ''
        [Desktop Entry]
        Name=Stream
        Comment=Menu minimo para streaming via Moonlight sobre Tailscale
        Exec=${sessionLauncher}/bin/stream-session
        Type=Application
        DesktopNames=stream
      '';
    }).overrideAttrs
      (_: {
        passthru.providedSessions = [ "stream" ];
      });
in
{
  options.modules.desktop.stream-mode = {
    enable = lib.mkEnableOption "Sessao minima com menu TUI para streaming via Moonlight";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      streamMenu
      sessionLauncher
    ];

    # A sessao "Stream" aparece no seletor de sessao do login (GDM).
    services.displayManager.sessionPackages = [ streamSession ];

    security.sudo.extraRules = [
      {
        users = [ vars.user.name ];
        commands = [
          {
            command = "${systemctlBin} stop syncthing";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${systemctlBin} start syncthing";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${batterySave}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${batteryRestore}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${rfkillBin} block bluetooth";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${rfkillBin} unblock bluetooth";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
