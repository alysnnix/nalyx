# omp-web: a zero-dependency Bun service that serves a local web UI to browse
# and continue omp sessions. Runs the agent by spawning `omp --mode rpc`.
#
# Loopback-only; tailnet exposure/TLS is handled by the NixOS module in front.
{
  lib,
  bun,
  omp,
  writeShellApplication,
}:
writeShellApplication {
  name = "omp-web";
  runtimeInputs = [
    bun
    omp
  ];
  text = ''
    # Pin the omp binary this service drives (overridable via the environment).
    export OMP_BIN="''${OMP_BIN:-${lib.getExe omp}}"
    exec bun run ${./.}/server.js
  '';
}
