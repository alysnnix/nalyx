{
  pkgs,
  lib,
  # Mirrors `hasDesktop` in home/default.nix. WSL is a terminal host whose
  # graphical layer belongs to Windows, so anything that ships a window is as
  # out of place here as it is on a server. Same `config`-position-only rule as
  # `terminalOnly` below.
  isWsl ? false,
  isServer ? false,
  # Terminal-only host: keep the shell, the agents and the CLI toolchain, drop
  # everything that ships a window. Distinct from `isServer`, which describes a
  # headless machine that still syncs with the personal fleet; this describes a
  # managed work laptop where the graphical layer belongs to someone else.
  #
  # Read only from `config` positions below, never from `imports`. A specialArg
  # with a default that is consulted while building the module tree sends the
  # module system to `_module.args`, which needs `config`, and that recurses.
  # Conditional imports are gated by real options instead (see ../syncthing).
  terminalOnly ? false,
  ...
}:
# Paseo, outro front end para os agentes de codigo que esta config ja instala.
#
# A topologia tem duas metades e elas nao moram no mesmo lugar. O daemon roda
# onde o codigo esta, nao onde a janela esta, entao ele e declarado no nivel
# NixOS pelo host que hospeda os repositorios: `services.paseo` em
# hosts/wsl/default.nix, com o modulo vindo do flake do proprio Paseo.
#
# Este arquivo cuida so do lado home-manager, e sao duas coisas: o CLI `paseo`,
# que vai para todo host porque e util em qualquer terminal, e o app desktop,
# que so faz sentido onde existe uma janela para abrir. Um host sem sessao
# grafica (WSL, servidor, laptop gerenciado) fica com o CLI e nada mais; o
# cliente, quando precisa, e o web UI embutido no navegador ou a build nativa
# da plataforma que tunela ate o daemon por SSH.
let
  # The same guard home/default.nix uses for the graphical tree, plus the
  # terminal-only work laptop, which that file never has to consider.
  hasDesktop = !isWsl && !isServer && !terminalOnly;
in
{
  home.packages = [
    pkgs.paseo
  ]
  # An Electron app with a window, so it follows the same rule as the rest of
  # the graphical tree. The daemon is the half that matters and it is a plain
  # service: on WSL it is declared in hosts/wsl and the client lives on the
  # Windows side, either the bundled web UI in a browser or the Windows build
  # of this same app tunnelling in over SSH.
  ++ lib.optionals hasDesktop [
    pkgs.paseo-desktop
  ];

  # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
  # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
  # The `.AppImage` name is what the launcher probes for, not a description of
  # the target: nix/desktop-package.nix produces a shell wrapper around
  # electron, never an AppImage.
  home.file."Applications/Paseo.AppImage" = lib.mkIf hasDesktop {
    source = lib.getExe pkgs.paseo-desktop;
  };
}
