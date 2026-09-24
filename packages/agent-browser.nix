# agent-browser - prebuilt Rust binary from GitHub releases.
# The binary is a plain dynamically-linked ELF (only libc/libm/libpthread/libdl),
# so autoPatchelfHook is enough - no FHS sandbox needed.
#
# Upstream's `agent-browser install` downloads Chrome-for-Testing at runtime, which
# produces a non-NixOS ELF that cannot run here. We pre-wire
# AGENT_BROWSER_EXECUTABLE_PATH to the nixpkgs Chrome so that step is never needed.
# --set-default (not --set) keeps a user or project override working.
{
  pkgs,
  lib,
  chrome ? pkgs.google-chrome,
  ...
}:

let
  version = "0.38.1";

  assets = {
    x86_64-linux = {
      name = "agent-browser-linux-x64";
      sha256 = "sha256-UQAUmhkDIRyIneTlRb822QgDdAzqT5mqImUWSfkgXqE=";
    };
    aarch64-linux = {
      name = "agent-browser-linux-arm64";
      sha256 = "sha256-k3sxXuB2Hopi95UN3P75s9PY6NXrnJ0r+eI+VyVmRRE=";
    };
  };

  system = pkgs.stdenv.hostPlatform.system;
  asset = assets.${system} or (throw "agent-browser: unsupported system ${system}");
in
pkgs.stdenv.mkDerivation {
  pname = "agent-browser";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/${asset.name}";
    inherit (asset) sha256;
  };

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];

  # The asset is a bare executable, not an archive.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/agent-browser
    runHook postInstall
  '';

  # `--profile` reuses a copy of a real Chrome profile, whose cookies are
  # encrypted with the session keyring (gnome-keyring, `v11` cookies). Chrome
  # then needs two things a service like the Paseo daemon does not have: the
  # session D-Bus, and `--password-store=gnome-libsecret`, since it only
  # auto-detects the keyring from XDG_CURRENT_DESKTOP and Hyprland is not on its
  # list. Without them the profile opens logged out. Both are added only when
  # they apply: the bus only if unset and the socket exists, the store only
  # when gnome-keyring is running, so hosts without a keyring (WSL, servers)
  # keep Chrome's own default. Prepended to AGENT_BROWSER_ARGS so an explicit
  # `--password-store` from the caller comes later and wins.
  postFixup = ''
    wrapProgram $out/bin/agent-browser \
      --set-default AGENT_BROWSER_EXECUTABLE_PATH ${lib.getExe chrome} \
      --run '_ab_rt="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
    if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$_ab_rt/bus" ]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$_ab_rt/bus"
    fi
    if [ -S "$_ab_rt/keyring/control" ]; then
      export AGENT_BROWSER_ARGS="--password-store=gnome-libsecret''${AGENT_BROWSER_ARGS:+,$AGENT_BROWSER_ARGS}"
    fi
    unset _ab_rt'
  '';

  meta = {
    description = "Browser automation CLI for AI agents, driving Chrome over CDP";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    platforms = lib.attrNames assets;
    mainProgram = "agent-browser";
  };
}
