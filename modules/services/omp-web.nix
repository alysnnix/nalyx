# omp-web: browse and continue your omp chats, served on loopback.
#
# Topology (Option B — Windows-hosted tailscale serve):
# This unit only runs the service on 127.0.0.1. WSL2 forwards that port to the
# Windows host's localhost, where the Windows Tailscale app exposes it to the
# tailnet (nothing on the LAN or public internet):
#   tailscale serve --bg http://localhost:8790     # run once on Windows
#
# The service runs as the user so the spawned `omp --mode rpc` sees ~/.omp auth
# and the project cwd. Access is gated by Google OIDC + an email allowlist; the
# client id/secret and allowed email come from a SOPS secret in the private repo
# (decrypted to /run/secrets/omp_web_env). Missing secret => auth fails closed.
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  user = vars.user.name;
  port = 8790; # loopback; forwarded to the Windows host by WSL2
  ompWeb = pkgs.callPackage ../../packages/omp-web { };
in
{
  systemd.services.omp-web = {
    description = "omp-web: browse and continue omp sessions";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      OMP_WEB_HOST = "127.0.0.1";
      OMP_WEB_PORT = toString port;
      HOME = "/home/${user}";
      OMP_WEB_AUTH = "google";
    };
    serviceConfig = {
      ExecStart = lib.getExe ompWeb;
      User = user;
      Restart = "on-failure";
      RestartSec = "5s";
      # Google OIDC creds + allowed email (and optional OMP_WEB_BASE_URL) from a
      # SOPS secret in the private repo, decrypted at activation. Optional ("-")
      # so the unit still starts if absent; auth then fails closed.
      EnvironmentFile = "-/run/secrets/omp_web_env";
    };
  };
}
