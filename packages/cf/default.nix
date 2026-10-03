# cf - the Cloudflare CLI, from the npm registry tarball.
# The tarball ships a prebuilt `dist/` but no lockfile, and its devDependencies
# point at `file:../../vendor/...` paths that only exist in the monorepo. So
# postPatch drops devDependencies and scripts, and a lockfile generated from
# that trimmed package.json is vendored here. On a bump:
#   curl -sL <tarball> | tar xz && cd package
#   jq 'del(.devDependencies, .scripts)' package.json > p && mv p package.json
#   npm install --package-lock-only --ignore-scripts
# then copy package-lock.json here and refresh both hashes.
#
# miniflare pulls the prebuilt workerd binary (linked against libc++) and sharp
# pulls prebuilt libvips; autoPatchelfHook rewrites both for NixOS, same as the
# nixpkgs wrangler package.
{
  pkgs,
  lib,
  ...
}:

let
  version = "1.0.0-beta.12";
in
pkgs.buildNpmPackage {
  pname = "cf";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/cf/-/cf-${version}.tgz";
    hash = "sha256-LGaN+SuptzxQq1uElbwA71HzBk3en/cLPZwCyOTLMHY=";
  };

  sourceRoot = "package";

  postPatch = ''
    ${lib.getExe pkgs.jq} 'del(.devDependencies, .scripts)' package.json > package.json.new
    mv package.json.new package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-wGIS0T7y77kS9WgrJZe+R0DkRUkx2H6S+PfR2PpijKg=";

  # `dist/` is already built.
  dontNpmBuild = true;

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [
    pkgs.llvmPackages.libcxx
    pkgs.llvmPackages.libunwind
  ];

  # Same reason as nixpkgs wrangler: workerd ignores the system trust store.
  makeWrapperArgs = [
    "--set-default"
    "SSL_CERT_FILE"
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  ];

  # npm installs sharp's musl builds too (it does not filter optional deps by
  # libc); they are dead weight on glibc and would fail autoPatchelf.
  postInstall = ''
    rm -rf $out/lib/node_modules/cf/node_modules/@img/sharp-*linuxmusl-*
  '';

  meta = {
    description = "Cloudflare CLI for accounts, zones, DNS, Workers and more";
    homepage = "https://developers.cloudflare.com/cf/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "cf";
  };
}
