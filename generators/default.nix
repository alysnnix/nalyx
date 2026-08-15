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
}:

let
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
              enableClaude = true;
              enableGemini = true;
              enableOpencode = true;
            };
          };
        }

        {
          services.getty.autologinUser = pkgs.lib.mkForce hostVars.user.name;
        }
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
