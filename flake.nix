{
  description = "Aly - nix setup with home-manager and flakes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
    };

    caelestia = {
      url = "github:caelestia-dots/shell/v1.5.2";
      inputs.nixpkgs.follows = "nixpkgs";
      # Supply chain hardening: use GitHub mirror instead of self-hosted Forgejo
      inputs.quickshell.url = "github:quickshell-mirror/quickshell";
    };

    # Private repository (optional)
    # Default: empty placeholder (works for everyone)
    # To use your private configs: nix flake lock --override-input private git+ssh://git@github.com/alysnnix/nalyx-private
    private = {
      url = "path:./private";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      lanzaboote,
      nixos-wsl,
      git-hooks,
      sops-nix,
      claude-code,
      caelestia,
      private ? null,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ claude-code.overlays.default ];
      };

      # Check if private repository is available
      hasPrivate = private != null && builtins.pathExists "${private}/vars-override.nix";

      vars =
        let
          base = import ./vars.nix;
          override = if hasPrivate then import "${private}/vars-override.nix" else { };
        in
        nixpkgs.lib.recursiveUpdate base override;

      # Helper function to generate system configurations
      # Added 'isWsl' parameter with a default value of false
      fnMountSystem =
        {
          hostname,
          extraModules ? [ ],
          isWsl ? false,
          isServer ? false,
          hostVars ? vars,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
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
            ./hosts/${hostname}/default.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            { nixpkgs.overlays = [ claude-code.overlays.default ]; }
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [
                  caelestia.homeManagerModules.default
                ];
                extraSpecialArgs = {
                  inherit
                    inputs
                    isWsl
                    isServer
                    hasPrivate
                    private
                    ;
                  vars = hostVars;
                  enableClaude = true;
                  enableGemini = true;
                  enableOpencode = true;
                };
              };
            }
          ]
          ++ extraModules;
        };

      isos = import ./generators {
        inherit
          inputs
          vars
          system
          pkgs
          lanzaboote
          sops-nix
          hasPrivate
          private
          caelestia
          claude-code
          ;
      };

    in
    {
      nixosConfigurations = {
        # Standard desktop/laptop configurations (isWsl defaults to false)
        desktop = fnMountSystem { hostname = "desktop"; };
        laptop = fnMountSystem { hostname = "laptop"; };
        vm = fnMountSystem { hostname = "vm"; };

        # WSL configuration with explicit flag
        wsl = fnMountSystem {
          hostname = "wsl";
          extraModules = [ nixos-wsl.nixosModules.default ];
          isWsl = true;
        };

        # Homelab server (headless, no desktop)
        homelab = fnMountSystem {
          hostname = "homelab";
          isServer = true;
          hostVars = vars // {
            desktop = null;
          };
        };
      };

      homeConfigurations = {
        wsl-ubuntu =
          let
            wslVars = vars // {
              desktop = null;
            };
          in
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
            extraSpecialArgs = {
              inherit inputs;
              vars = wslVars;
              isWsl = true;
              enableClaude = false;
              enableGemini = false;
              enableOpencode = false;
              inherit hasPrivate private;
            };
            modules = [
              ./home
            ];
          };
      };

      packages.${system} = {
        desktop-iso = isos.desktop;
        laptop-iso = isos.laptop;
        homelab-iso = isos.homelab;

        # Minimal Docker image with Claude Code — build with: nix build .#claude-container
        claude-container = import ./packages/claude-container.nix { inherit pkgs; };
      };

      # Eval-only checks: validates all configurations without building
      # Run with: nix flake check --no-build
      checks.${system} = {
        desktop = self.nixosConfigurations.desktop.config.system.build.toplevel;
        laptop = self.nixosConfigurations.laptop.config.system.build.toplevel;
        vm = self.nixosConfigurations.vm.config.system.build.toplevel;
        wsl = self.nixosConfigurations.wsl.config.system.build.toplevel;
        homelab = self.nixosConfigurations.homelab.config.system.build.toplevel;
        wsl-ubuntu = self.homeConfigurations.wsl-ubuntu.activationPackage;

        # Pre-commit hooks check (also used to install hooks via devShell)
        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt.enable = true;
            statix = {
              enable = true;
              excludes = [ "hardware-configuration\\.nix" ];
              settings.ignore = [
                "hosts/desktop/hardware-configuration.nix"
                "hosts/laptop/hardware-configuration.nix"
                "hosts/vm/hardware-configuration.nix"
                "hosts/homelab/hardware-configuration.nix"
              ];
            };
            deadnix = {
              enable = true;
              excludes = [ "hardware-configuration\\.nix" ];
              settings.noLambdaPatternNames = true;
            };
          };
        };
      };

      # Enter with `nix develop` to auto-install the pre-commit hooks
      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit) shellHook;
        packages = [ pkgs.sops ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
