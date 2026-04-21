{ pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      go

      gopls
      gotools
      golangci-lint

      delve
      gotestsum

      gomodifytags
      impl
      iferr
    ];

    sessionVariables = {
      GOPATH = "$HOME/go";
      GOBIN = "$HOME/go/bin";
    };

    sessionPath = [
      "$HOME/go/bin"
    ];
  };
}
