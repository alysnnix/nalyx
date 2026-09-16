{ pkgs, ... }:

{
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-backgroundremoval
      # 3.2.1 still uses an OBS API deprecated in 32.2.  Upstream compiles
      # with -Werror, so keep this specific warning from aborting the build
      # until a compatible plugin release reaches nixpkgs.
      (obs-move-transition.overrideAttrs (old: {
        NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " -Wno-error=deprecated-declarations";
      }))
    ];
  };
}
