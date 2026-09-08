{
  user = {
    name = "aly";
    # This is the address verified on the GitHub account, so pushed commits are
    # attributed to the user instead of rendering with the blank default avatar.
    # It is the default committer identity; the Seazone profile overrides it at
    # runtime through a git include (see home/profiles/szn).
    email = "aly@alysson.dev";
    # Used for authorizedKeys on the personal hosts, so it stays the personal
    # key alone: the work laptop has no business reaching the desktop or the
    # homelab over SSH. `signers` below is the list for verification.
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnnv86issRRn6YtBs60h/hjkWwQy76V1/VflqqLPmxf aly@alysson.dev";

    # Identities whose commit signatures should verify on every host, written to
    # ~/.ssh/allowed_signers by home/features/cli/git.
    #
    # Both live here rather than one per profile because verification is not
    # symmetric with signing: the work laptop still has to verify years of
    # commits signed by the personal key, and this machine has to verify the
    # work ones. Only the private key is ever machine-specific.
    #
    # The principal is a pattern, which ssh-keygen matches against the signer
    # identity. That is deliberate for the work entry: nalyx is a public repo,
    # so it names the employer's domain and never the address itself. The real
    # address comes from szn_email at runtime (see home/profiles/szn).
    signers = [
      {
        principal = "aly@alysson.dev";
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnnv86issRRn6YtBs60h/hjkWwQy76V1/VflqqLPmxf";
      }
      {
        # The "Seazone" key on the alysnnix account, generated for the managed
        # laptop so the personal private key never lands on it. Note it grants
        # the same account-wide access as the other one: an SSH key on GitHub
        # is a credential for the account, not for a repository.
        principal = "*@seazone.com.br";
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKdZP61iTU7w0Z8rMLY14bUlopgG1HUvx/LHp1hPYz8l";
      }
    ];

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
