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
  version = "0.35.1";

  assets = {
    x86_64-linux = {
      name = "agent-browser-linux-x64";
      sha256 = "sha256-IYdLevvhKiJdAcfz99Y1wsL3QGYPbvXnkWc3xgxPH68=";
    };
    aarch64-linux = {
      name = "agent-browser-linux-arm64";
      sha256 = "sha256-TCTx+i9wSGWgxNb5Br+BFpMYiGgXQrvwgMA9zrFHrJ4=";
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

  postFixup = ''
    wrapProgram $out/bin/agent-browser \
      --set-default AGENT_BROWSER_EXECUTABLE_PATH ${lib.getExe chrome}
  '';

  meta = {
    description = "Browser automation CLI for AI agents, driving Chrome over CDP";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    platforms = lib.attrNames assets;
    mainProgram = "agent-browser";
  };
}
