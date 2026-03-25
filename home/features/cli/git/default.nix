{
  config,
  pkgs,
  vars,
  ...
}:

{
  programs.ssh = {
    enable = true;
    matchBlocks."*".addKeysToAgent = "yes";
  };

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

  home.file.".ssh/allowed_signers".text = "${vars.user.email} ${vars.user.publicKey}";
}
