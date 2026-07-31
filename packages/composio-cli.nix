# Composio CLI - prebuilt Bun binary from GitHub releases.
# The binary is Bun-compiled: patchelf corrupts it (the appended bundle offset
# breaks, segfault), so instead of rewriting the ELF interpreter we run it inside
# an FHS sandbox that provides the standard glibc loader. Same trick as nordvpn.
{
  pkgs,
  lib,
  ...
}:

let
  version = "0.3.1";
  target = "linux-x64";

  # Unpacked bundle: main binary plus its sidecar .mjs services and ACP adapters.
  # These must stay next to the binary (it resolves them relative to itself).
  bundle = pkgs.stdenv.mkDerivation {
    pname = "composio-cli-unwrapped";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/ComposioHQ/composio/releases/download/@composio/cli@${version}/composio-${target}.zip";
      sha256 = "sha256-kZ0kRWSoQk2+Pb9gHNzBAlwjBMUFaiB7LfyLHplL+dU=";
    };

    nativeBuildInputs = [ pkgs.unzip ];

    sourceRoot = "composio-${target}";

    # Prebuilt Bun binary: no ELF rewriting, stripping, or nixpkgs fixups.
    dontStrip = true;
    dontPatchELF = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r . $out/
      # Drop ACP adapters for other platforms (dead weight on x86_64-linux).
      rm -rf $out/acp-adapters/codex/darwin-x64 \
        $out/acp-adapters/codex/darwin-arm64 \
        $out/acp-adapters/codex/linux-arm64
      chmod +x $out/composio
      runHook postInstall
    '';
  };
in
pkgs.buildFHSEnv {
  name = "composio";
  runScript = "${bundle}/composio";

  targetPkgs = pkgs: [
    pkgs.glibc
    pkgs.cacert
  ];

  meta = {
    description = "Composio CLI - connect AI agents to 1000+ apps from the shell";
    homepage = "https://composio.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "composio";
  };
}
