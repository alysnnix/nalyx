{ vars, ... }:
{
  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
      };

      "github.com" = {
        hostname = "github.com";
        user = vars.user.social.github;
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };
}
