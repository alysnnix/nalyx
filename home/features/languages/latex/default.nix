{
  pkgs,
  lib,
  osConfig,
  ...
}:
let
  isWSL = osConfig.wsl.enable or false;
in
{
  home.packages =
    with pkgs;
    [
      texlive.combined.scheme-medium
      texlab
      ghostscript
      poppler-utils
      perlPackages.YAMLTiny
      perlPackages.FileHomeDir
    ]
    ++ lib.optionals (!isWSL) [
      zathura
    ];
}
