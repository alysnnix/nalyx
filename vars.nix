{
  user = {
    name = "aly";
    # This is the address verified on the GitHub account, so pushed commits are
    # attributed to the user instead of rendering with the blank default avatar.
    # The publicKey comment below is kept in sync with it (git/default.nix builds
    # .ssh/allowed_signers from both, so the signing identity follows along).
    email = "aly@alysson.dev";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnnv86issRRn6YtBs60h/hjkWwQy76V1/VflqqLPmxf aly@alysson.dev";

    social = {
      github = "alysnnix";
    };
  };

  terminal = "kitty";
  editor = "nvim";
  desktop = "hyprland";
  shell = "caelestia";

  homelab = {
    address = "homelab.local";
  };

  weather = {
    location = "";
  };
}
