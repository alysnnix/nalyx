{
  config,
  pkgs,
  lib,
  vars,
  ...
}:

{
  programs.git = {
    enable = true;

    settings = {
      user = {
        inherit (vars.user) name email;
      };
      pull.rebase = true;
      init.defaultBranch = "main";
      gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
    };

    signing = {
      format = "ssh";
      signByDefault = true;
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };
  };

  home.activation.fetchAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SIGNERS_FILE="${config.home.homeDirectory}/.ssh/allowed_signers"
    mkdir -p "$(dirname "$SIGNERS_FILE")"

    # Remove symlink from previous home.file approach
    [ -L "$SIGNERS_FILE" ] && rm "$SIGNERS_FILE"

    KEY=$(${pkgs.curl}/bin/curl -sf "${vars.user.publicKeyUrl}" | head -1)
    if [ -n "$KEY" ]; then
      echo "${vars.user.email} $KEY" > "$SIGNERS_FILE"
    fi
  '';
}
