{
  inputs,
  vars,
  system,
  pkgs,
  lanzaboote,
  sops-nix,
  hasPrivate,
  private,
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
          hasPrivate
          private
          ;
        vars = hostVars;
      };

      modules = [
        ../hosts/${hostname}/default.nix
        sops-nix.nixosModules.sops

        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit
                inputs
                isServer
                hasPrivate
                private
                ;
              vars = hostVars;
              isWsl = false;
              enableClaude = true;
              enableGemini = true;
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
