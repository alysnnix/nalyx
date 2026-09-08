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

  # Every identity in vars, not just this host's. A host that cannot verify the
  # other identity's signatures reports every commit from the other machine as
  # untrusted, which trains you to ignore the field. Principals may be patterns
  # (`*@domain`), which is how the work address stays out of this public repo.
  home.file.".ssh/allowed_signers".text =
    lib.concatMapStringsSep "\n" (s: "${s.principal} ${s.key}") vars.user.signers + "\n";
}
