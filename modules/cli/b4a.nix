{ pkgs, ... }:

let
  version = "1.0.358";
  sha256 = "sha256-4O2M92r9f4TjD7L+g5RkL3yJpXwF8tW7qY6nZ9hM0g=";
in
{
  home.packages = [
    (pkgs.stdenv.mkDerivation {
      pname = "b4a-cli";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/back4app/parse-cli/releases/download/release_${version}/b4a_linux";
        inherit sha256;
      };

      dontUnpack = true;

      installPhase = ''
        mkdir -p $out/bin
        cp $src $out/bin/b4a
        chmod +x $out/bin/b4a
      '';
    })
  ];
}
