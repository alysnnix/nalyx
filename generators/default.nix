{
  inputs,
  vars,
  system,
  pkgs,
  lanzaboote,
  sops-nix,
  caelestia,
  claudeOverlay,
  privateHmModules,
  privateSrc,
}:

let
  # Mirroring the host wholesale produced a 9.6GB desktop image, which stopped
  # fitting on an 8GB stick. The image still ships the desktop, because
  # partitioning a disk by hand is where a typo destroys the other OS and
  # GParted needs a session to run in. What it drops is everything that has
  # nothing to do with installing: the day-job cloud CLIs, the editors, the
  # games and the AI tooling, via isInstaller.
  fnMountISO =
    {
      hostname,
      isServer ? false,
      hostVars ? vars,
      extraModules ? [ ],
    }:
    inputs.nixos-generators.nixosGenerate {
      inherit system;
      format = "install-iso";
      specialArgs = {
        inherit
          inputs
          lanzaboote
          sops-nix
          ;
        vars = hostVars;
      };

      modules = [
        ../hosts/${hostname}/default.nix
        sops-nix.nixosModules.sops
        { nixpkgs.overlays = [ claudeOverlay ]; }

        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            sharedModules = [
              caelestia.homeManagerModules.default
            ]
            ++ privateHmModules;
            extraSpecialArgs = {
              inherit
                inputs
                isServer
                ;
              vars = hostVars;
              isWsl = false;
              isInstaller = true;
              enableClaude = false;
              enableGemini = false;
              enableOpencode = false;
            };
          };
        }

        {
          services.getty.autologinUser = pkgs.lib.mkForce hostVars.user.name;

          # Set directly by hosts/desktop, so they survive isInstaller.
          # Nothing here is worth carrying on an installer.
          programs.steam.enable = pkgs.lib.mkForce false;
          programs.gamescope.enable = pkgs.lib.mkForce false;
          programs.gamemode.enable = pkgs.lib.mkForce false;

          # The point of keeping a desktop on the image: partition with a mouse
          # instead of typing a device path. firefox comes along because the
          # app payload is gone and looking something up mid-install is normal.
          #
          # nalyx-install is the guided path, and the reason Calamares is not
          # here: calamares-nixos-extensions builds a vanilla configuration.nix
          # from Python templates, so it cannot install a flake host. It would
          # hand over a NixOS with no lanzaboote, no private modules and none
          # of this repo. The script drives the real flake instead.
          #
          # Which host it installs is read from a file rather than interpolated
          # into the script, so bash ${...} in there stays bash.
          environment.etc."nalyx-install-host".text = hostname;

          environment.systemPackages = [
            pkgs.gparted
            pkgs.firefox
            (pkgs.writeShellScriptBin "nalyx-install" (builtins.readFile ../scripts/nalyx-install.sh))
            (pkgs.makeDesktopItem {
              name = "nalyx-install";
              desktopName = "Install nalyx (${hostname})";
              comment = "Partition a disk and install this host from the flake";
              icon = "drive-harddisk";
              # sudo needs no password on the image, see the polkit block above.
              exec = "${hostVars.terminal} sudo nalyx-install";
              categories = [ "System" ];
            })
          ];

          # GParted asks polkit for root, and no session here runs an agent, so
          # the dialog would never appear and it would just fail to start. The
          # live user is physically at the machine in a throwaway environment,
          # so wheel is trusted outright rather than prompting for a password
          # that only exists as the public "changeme" default.
          security.polkit.extraConfig = ''
            polkit.addRule(function(action, subject) {
              if (subject.isInGroup("wheel")) { return polkit.Result.YES; }
            });
          '';
          security.sudo.wheelNeedsPassword = pkgs.lib.mkForce false;
        }

        # Carry the private flake source on the installer image. Without it
        # `nixos-install --flake` resolves the private input from its locked
        # ssh:// URL, which the live environment has no key for, and the eval
        # dies before anything is written. On the ISO it can be passed by path:
        #
        #   nixos-install --flake /mnt/etc/nixos#<host> \
        #     --override-input private path:/iso/nalyx-private
        #
        # The secrets inside stay sops-encrypted. The age key that opens them is
        # deliberately NOT on the image: it would sit world-readable in the store
        # and on the USB stick, and the first-boot password hash in the private
        # repo already covers logging in without it.
        (pkgs.lib.optionalAttrs (privateSrc != null) {
          isoImage.contents = [
            {
              source = privateSrc;
              target = "/nalyx-private";
            }
          ];
        })
      ]
      ++ extraModules;
    };
in
{
  desktop = fnMountISO { hostname = "desktop"; };
  laptop = fnMountISO { hostname = "laptop"; };
  homelab = fnMountISO {
    hostname = "homelab";
    isServer = true;
    hostVars = vars // {
      desktop = null;
    };
    extraModules = [
      {
        # Allow temporary password auth in the live ISO for remote installation
        services.openssh.settings.PasswordAuthentication = pkgs.lib.mkForce true;
        # Set a known password for the live environment
        users.users.${vars.user.name}.initialPassword = pkgs.lib.mkForce "install";

        # Homelab installer script available as `homelab-install`
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "homelab-install" (builtins.readFile ../scripts/homelab-install.sh))
        ];
      }
    ];
  };
}
