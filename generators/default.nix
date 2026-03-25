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
    hostname:
    inputs.nixos-generators.nixosGenerate {
      inherit system;
      format = "install-iso";
      specialArgs = {
        inherit
          inputs
          vars
          lanzaboote
          sops-nix
          hasPrivate
          private
          ;
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
                vars
                hasPrivate
                private
                ;
              isWsl = false;
              isServer = false;
              enableClaude = true;
              enableGemini = true;
            };
          };
        }

        {
          services.getty.autologinUser = pkgs.lib.mkForce vars.user.name;
        }
      ];
    };
in
{
  desktop = fnMountISO "desktop";
  laptop = fnMountISO "laptop";
}
