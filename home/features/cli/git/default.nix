{
  pkgs,
  config,
  vars,
  lib,
  ...
}:

let
  gitHooks = import ./hooks { inherit pkgs lib; };
in
{
  imports = [ ./options.nix ];

  # The hook logic is on PATH as well as behind core.hooksPath. A repo that
  # sets its own core.hooksPath (husky points it at .husky/_) shadows ours,
  # and there the fix is one line in that repo's own hook calling these:
  #
  #   exec git-commit-trailer "$@"   in prepare-commit-msg
  #   exec git-commit-lint "$1"      in commit-msg
  #
  # `git-hooks-doctor` reports which of the two situations a repo is in.
  home.packages = [
    pkgs.gitflow
    gitHooks.commitTrailer
    gitHooks.commitLint
    gitHooks.doctor
  ];

  programs.git = {
    enable = true;

    settings = {
      user = {
        inherit (vars.user) name email;
      };
      pull.rebase = true;
      init.defaultBranch = "main";

      # Global on purpose. The commit convention has to hold in every repo on
      # the machine, including the ones cloned five minutes from now, and a
      # per repo hook only covers the repos someone remembered to set up.
      #
      # Setting core.hooksPath makes git ignore each repo's own .git/hooks
      # entirely, so every dispatcher in that directory delegates to the repo
      # local hook of the same name first. Per repo hooks keep working, this
      # repo's `nix develop` pre-commit hook included.
      #
      # This covers every repo except one that sets its own core.hooksPath,
      # which git lets win. See the home.packages comment above for that case.
      core.hooksPath = "${gitHooks.hooksDir}";
      gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
    };

    signing = {
      format = "ssh";
      signByDefault = true;
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };
  };

  # Verification is not symmetric with signing. A host signs with the one key it
  # holds, but it has to verify every identity you have ever used, or it reports
  # commits from your other machines as untrusted and trains you to ignore the
  # field entirely.
  #
  # Principals are matched as patterns by ssh-keygen, so a per-project module can
  # add `*@employer.example` and keep the address itself out of this public repo.
  home.file.".ssh/allowed_signers".text =
    lib.concatMapStringsSep "\n" (e: "${e.principal} ${e.key}") (
      [
        {
          principal = vars.user.email;
          key = vars.user.publicKey;
        }
      ]
      ++ config.modules.cli.git.extraSigners
    )
    + "\n";
}
