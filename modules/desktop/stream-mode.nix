{
  pkgs,
  lib,
  vars,
  config,
  ...
}:

let
  cfg = config.modules.desktop.stream-mode;

  overridePath = "/etc/sddm.conf.d/99-stream-mode.conf";
  sudoBin = "/run/wrappers/bin/sudo";
  teeBin = "${pkgs.coreutils}/bin/tee";
  rmBin = "${pkgs.coreutils}/bin/rm";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";

  # Menu TUI em loop. Roda dentro de foot, dentro de cage (tela preta, sem
  # desktop). Ao abrir aplica economia de bateria; a opcao "Sair" desfaz tudo
  # e volta ao Hyprland.
  streamMenu = pkgs.writeShellApplication {
    name = "stream-menu";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.power-profiles-daemon
      pkgs.wlr-randr
      pkgs.jq
      pkgs.networkmanager
      pkgs.bluetuith
      pkgs.moonlight-qt
      pkgs.gum
      pkgs.systemd
    ];
    text = ''
      prev_profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

      # Baixa o refresh para o maior modo <=60Hz na resolucao atual (economia
      # de bateria). Best-effort: precisa ser validado no painel do laptop.
      set_low_refresh() {
        local name mode
        name="$(wlr-randr --json | jq -r '.[0].name')" || return 0
        mode="$(wlr-randr --json | jq -r '
          .[0].modes as $m
          | ($m[] | select(.current)) as $c
          | (([ $m[] | select(.width==$c.width and .height==$c.height and .refresh<=61) ] | max_by(.refresh))
             // ([ $m[] | select(.width==$c.width and .height==$c.height) ] | min_by(.refresh)))
          | "\(.width)x\(.height)@\(.refresh | round)Hz"')" || return 0
        [ -n "$mode" ] && wlr-randr --output "$name" --mode "$mode" || true
      }

      leave() {
        powerprofilesctl set "$prev_profile" || true
        ${sudoBin} ${systemctlBin} start syncthing || true
        ${sudoBin} ${rmBin} -f ${overridePath} || true
        exec ${sudoBin} ${systemctlBin} restart display-manager
      }

      # Setup: economia de bateria
      powerprofilesctl set power-saver || true
      set_low_refresh
      ${sudoBin} ${systemctlBin} stop syncthing || true

      while true; do
        choice="$(gum choose \
          --header "  MODO STREAM  ·  setas navegam, Enter seleciona" \
          "▶  Moonlight (stream)" \
          "📶  WiFi" \
          "🔵  Bluetooth" \
          "🚪  Sair (voltar ao Hyprland)")" || continue

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

  # Sessao Wayland minima: cage (kiosk) rodando foot com o menu.
  sessionLauncher = pkgs.writeShellApplication {
    name = "stream-session";
    runtimeInputs = [
      pkgs.cage
      pkgs.foot
    ];
    text = ''
      exec cage -s -- foot -e ${streamMenu}/bin/stream-menu
    '';
  };

  # Comando para entrar no modo stream a partir do Hyprland.
  switchToStream = pkgs.writeShellApplication {
    name = "stream-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      printf '[Autologin]\nSession=stream\n' \
        | ${sudoBin} ${teeBin} ${overridePath} > /dev/null
      exec ${sudoBin} ${systemctlBin} restart display-manager
    '';
  };

  # Comando de escape manual (caso precise forcar a volta ao Hyprland).
  switchToHyprland = pkgs.writeShellApplication {
    name = "hyprland-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      ${sudoBin} ${rmBin} -f ${overridePath}
      exec ${sudoBin} ${systemctlBin} restart display-manager
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
      switchToStream
      switchToHyprland
    ];

    services.displayManager.sessionPackages = [ streamSession ];

    systemd.tmpfiles.rules = [
      "d /etc/sddm.conf.d 0755 root root -"
    ];

    security.sudo.extraRules = [
      {
        users = [ vars.user.name ];
        commands = [
          {
            command = "${teeBin} ${overridePath}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${rmBin} -f ${overridePath}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${systemctlBin} restart display-manager";
            options = [ "NOPASSWD" ];
          }
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
