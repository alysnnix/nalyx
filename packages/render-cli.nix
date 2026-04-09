# Render.com CLI - fetches pre-built binary from GitHub releases
{
  pkgs,
  lib,
  ...
}:

let
  version = "2.15.1";
in
pkgs.stdenv.mkDerivation {
  pname = "render-cli";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/render-oss/cli/releases/download/v${version}/cli_${version}_linux_amd64.zip";
    sha256 = "sha256-rh2CAHI7nVaJgYf2gWY8wQgB/nD8DhXyfoHsML5sAL8=";
  };

  nativeBuildInputs = [ pkgs.unzip ];

  sourceRoot = ".";

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp cli_v${version} $out/bin/render
    chmod +x $out/bin/render
  '';

  meta = {
    description = "Command line tool for Render.com";
    homepage = "https://github.com/render-oss/cli";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "render";
  };
}
