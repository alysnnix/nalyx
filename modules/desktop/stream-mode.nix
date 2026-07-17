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
      pkgs.moonlight-qt
      pkgs.gum
      pkgs.sway
      pkgs.systemd
    ];
    text = ''
      prev_profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

      leave() {
        powerprofilesctl set "$prev_profile" || true
        ${sudoBin} ${systemctlBin} start syncthing || true
        swaymsg exit || true
      }

      # Setup: economia de bateria (o refresh/resolucao ja vem do sway)
      powerprofilesctl set power-saver || true
      ${sudoBin} ${systemctlBin} stop syncthing || true

      while true; do
        choice="$(gum choose \
          --header "  MODO STREAM  ·  setas navegam, Enter seleciona" \
          "▶  Moonlight (stream)" \
          "📶  WiFi" \
          "🔵  Bluetooth" \
          "🚪  Sair (voltar ao login)")" || continue

        case "$choice" in
          *Moonlight*) moonlight || true ;;
          *WiFi*) nmtui || true ;;
          *Bluetooth*) bluetuith || true ;;
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
    input "type:touchpad" {
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
        ];
      }
    ];
  };
}
