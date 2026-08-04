# Self-hosted omp collab: a content-blind relay + the browser guest client,
# both built from the pinned oh-my-pi source (MIT, can1357/oh-my-pi). This lets
# `/collab` run entirely on the tailnet, never touching the public my.omp.sh.
#
# Version-coupled to the installed omp (the wire protocol must match): bump
# `tag` + the two hashes in lockstep whenever omp updates.
{
  lib,
  stdenvNoCC,
  bun,
  cacert,
  fetchFromGitHub,
  writeShellApplication,
}:
let
  src = fetchFromGitHub {
    owner = "can1357";
    repo = "oh-my-pi";
    tag = "v17.0.8";
    hash = "sha256-f+3+K8yrcIg6JuDl8HK6h3gMuIKC96+CHoP2xOf01/g=";
  };
in
{
  # The collab-web browser guest client, built from source. Fixed-output:
  # `bun install` needs the network, and bun's bundle is content-hash-named +
  # minified so the dist is reproducible. Only the ~900K dist is stored
  # (node_modules is intermediate and discarded).
  web = stdenvNoCC.mkDerivation {
    pname = "omp-collab-web";
    version = "17.0.8";
    inherit src;
    nativeBuildInputs = [
      bun
      cacert
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      bun install --ignore-scripts --no-progress
      bun --cwd=packages/collab-web run build
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      cp -R packages/collab-web/dist "$out"
      runHook postInstall
    '';
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-ajrTbXSU45p4u+NfVdKzcGtRtOKE3pVUzrdJ8IcpWnY=";
  };

  # Content-blind WebSocket relay (zero runtime deps; runs under Bun).
  relay = writeShellApplication {
    name = "omp-collab-relay";
    runtimeInputs = [ bun ];
    text = ''exec bun ${./relay.ts} "$@"'';
  };
}
