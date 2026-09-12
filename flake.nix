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

    # AI coding tools (claude-code, etc.), auto-updated daily.
    # Not following nixpkgs: consume the prebuilt package to keep their cache.
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    # herdr: terminal multiplexer for AI coding agents.
    # Not following nixpkgs: consume its pinned rust toolchain to avoid a rebuild.
    herdr = {
      url = "github:herdrdev/herdr";
    };

    # paseo: self-hosted daemon for AI coding agents.
    # Not following nixpkgs: consume its pinned npm-deps hash to avoid a rebuild.
    paseo = {
      url = "github:getpaseo/paseo";
    };

    # paseo-github: o plugin de integracao com o GitHub para o Paseo, repo
    # proprio (`alysnnix/paseo-github-integration`). Nasceu como fork do
    # `gpambrozio/paseo-plugins`, mas o fork carregava mais dois plugins que
    # nao sao nossos e um deles so roda em macOS; o repo novo e so o plugin,
    # com o historico e a licenca preservados.
    #
    # `git+ssh` e nao `github:` porque o repo ainda e privado: o `github:`
    # fetcher sem token falha, e o ssh usa a chave que a maquina ja tem. Trocar
    # para `github:alysnnix/paseo-github-integration` quando virar publico.
    #
    # Ate la a CI nao alcanca este input e o troca pelo mesmo placeholder vazio
    # que ja usa para o `private` (`--override-input`). O placeholder nao expoe
    # `packages`, entao o overlay e o host precisam tolerar a ausencia: e
    # `hasPaseoGithub` quem decide, e sem ele o wsl sobe sem plugin nenhum em
    # vez de falhar a avaliacao.
    #
    # Segue nixpkgs porque o pacote e uma copia de fontes: nao compila nada e
    # nao tem hash de dependencia para preservar.
    paseo-github = {
      url = "git+ssh://git@github.com/alysnnix/paseo-github-integration.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # hermes-agent: self-hosted AI agent gateway (Discord, Slack, WhatsApp).
    # Not following nixpkgs: it builds its venv with uv2nix against its own
    # pinned nixpkgs, and repinning that breaks dependency resolution.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.8.13";
    };

    # microvm.nix: runs the hermes agent in a KVM guest with its own kernel.
    # Follows nixpkgs because the guest is a NixOS system built from it.
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # fastpotify: native Spotify client (librespot + egui), no browser engine.
    # Not following nixpkgs: it pins its rust toolchain through rust-overlay,
    # and repinning that nixpkgs rebuilds the toolchain before the app.
    fastpotify = {
      url = "github:crmne/fastpotify";
    };

    caelestia = {
      url = "github:caelestia-dots/shell/v1.5.2";
      inputs.nixpkgs.follows = "nixpkgs";
      # Supply chain hardening: use GitHub mirror instead of self-hosted Forgejo
      inputs.quickshell.url = "github:quickshell-mirror/quickshell";
    };

    # Private repository (optional)
    # Contains SOPS secrets, private scripts, and MCP configs
    # Without it: safe defaults, no secrets, public-only configs
    private = {
      url = "git+ssh://git@github.com/alysnnix/nalyx-private";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Per-project private layer (optional, one at a time)
    #
    # Everything belonging to one employer or client: their committer identity,
    # their secrets, their skills, the tools only that job needs. Kept out of
    # this repo entirely, because a public config that names who you work for
    # is a liability you cannot take back once it is pushed.
    #
    # The default is the local placeholder, never a URL, and that is the whole
    # trick: a flake input is static and lives in this file, so any real URL
    # here would publish the name it exists to hide. `switch` overrides it with
    # .private/wrk when that checkout is present, so the name only ever lives
    # on the machine that needs it. Point .private/wrk at a different project's
    # repo and the same profile serves the next job.
    wrk = {
      url = "path:./ci/empty-private";
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
      llm-agents,
      caelestia,
      private ? null,
      wrk ? null,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # O placeholder que a CI injeta no lugar do repo privado nao tem saida
      # nenhuma, entao a presenca do pacote e a pergunta certa: um `? null` no
      # argumento nao ajudaria porque o input existe nos dois casos, com
      # conteudo diferente.
      hasPaseoGithub =
        inputs.paseo-github ? packages
        && inputs.paseo-github.packages ? ${system}
        && inputs.paseo-github.packages.${system} ? github-integration;

      # O build Nix do Paseo compila o addon nativo do node-pty e depois o
      # perde. `scripts/trace-daemon.mjs` monta o closure por tracing estatico
      # e precisa listar a mao o que e carregado por path computado; a linha
      # que cobre o node-pty aponta para
      # `node_modules/node-pty/prebuilds/<plat>-<arch>/**`, e erra em dois
      # eixos: o npm aninha o pacote em `packages/server/node_modules/node-pty`
      # (nao existe copia na raiz do output) e o `npm rebuild node-pty` do
      # buildPhase escreve em `build/Release`, nao em `prebuilds`. Nenhum
      # `pty.node` chega ao $out.
      #
      # O daemon sobe assim mesmo, porque o terminal roda em processo separado:
      # o worker morre no import, o supervisor sobrevive, e o sintoma so
      # aparece no primeiro uso, como
      # `TERMINAL_CREATE_FAILED: Terminal worker is not running`. Sem terminal
      # nao ha agente, entao isso derruba o produto inteiro, nao um extra.
      #
      # Copiado em postInstall e nao em installPhase porque o autoPatchelfHook
      # roda depois, em postFixup, e ainda patcheia o addon contra o libuv que
      # ja esta em buildInputs. Percorre os dois pacotes pelo mesmo caminho: o
      # desktop instala em share/paseo-desktop e sofre do mesmo furo.
      fixPtyNode =
        pkg:
        pkg.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            ptySrc=$(find . -name pty.node -path '*node-pty*' -print -quit)
            if [ -z "$ptySrc" ]; then
              echo "fixPtyNode: nenhum pty.node na arvore de build" >&2
              exit 1
            fi
            ptyDests=$(find $out -type d -name node-pty)
            if [ -z "$ptyDests" ]; then
              echo "fixPtyNode: nenhum node-pty no output" >&2
              exit 1
            fi
            for d in $ptyDests; do
              mkdir -p "$d/build/Release"
              cp "$ptySrc" "$d/build/Release/pty.node"
              helper=$(dirname "$ptySrc")/spawn-helper
              if [ -e "$helper" ]; then
                cp "$helper" "$d/build/Release/spawn-helper"
              fi
              echo "fixPtyNode: pty.node -> $d/build/Release"
            done
          '';
        });

      claudeOverlay =
        _: _:
        {
          claude-code = llm-agents.packages.${system}.claude-code;
          omp = llm-agents.packages.${system}.omp;
          pi = llm-agents.packages.${system}.pi;
          herdr = inputs.herdr.packages.${system}.default;
          paseo = fixPtyNode inputs.paseo.packages.${system}.default;
          paseo-desktop = fixPtyNode inputs.paseo.packages.${system}.desktop;
        }
        // nixpkgs.lib.optionalAttrs hasPaseoGithub {
          paseo-github-integration = inputs.paseo-github.packages.${system}.github-integration;
        };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ claudeOverlay ];
      };

      vars = import ./vars.nix;

      # Private flake module helpers — empty lists when private repo is absent
      privateNixosModules =
        if private != null && (private ? nixosModules) then [ private.nixosModules.default ] else [ ];

      privateHmModules =
        if private != null && (private ? homeManagerModules) then
          [ private.homeManagerModules.default ]
        else
          [ ];

      # Same shape as the personal one, so a project repo is plugged in by
      # exporting homeManagerModules.default and nothing else.
      wrkHmModules =
        if wrk != null && (wrk ? homeManagerModules) then [ wrk.homeManagerModules.default ] else [ ];

      # And the system half, which exists for one reason: secrets. A project's
      # sops secrets have to be declared somewhere, and on a NixOS host that is
      # a NixOS module. Optional, so a layer that only carries user-level
      # config exports nothing here and still works.
      wrkNixosModules = if wrk != null && (wrk ? nixosModules) then [ wrk.nixosModules.default ] else [ ];

      privateNixosModule =
        name:
        if private != null && (private ? nixosModules) && (private.nixosModules ? ${name}) then
          [ private.nixosModules.${name} ]
        else
          [ ];

      # Helper function to generate system configurations
      fnMountSystem =
        {
          hostname,
          extraModules ? [ ],
          isWsl ? false,
          isServer ? false,
          hostVars ? vars,
          # On by default because every interactive host wants the agents. A
          # host opts out, rather than in, so adding a machine never silently
          # loses its tooling.
          enableClaude ? true,
          enableGemini ? true,
          enableOpencode ? true,
          enablePi ? true,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inputs
              lanzaboote
              sops-nix
              ;
            vars = hostVars;
          };
          modules = [
            ./hosts/${hostname}/default.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            { nixpkgs.overlays = [ claudeOverlay ]; }
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [
                  caelestia.homeManagerModules.default
                ]
                ++ privateHmModules
                # A NixOS host is not exempt from having a job: the WSL box and
                # the desktop do employer work too, and the layer that carries
                # it has to reach them or a `switch` there silently drops every
                # project skill, agent and script. Empty unless the machine has
                # a .private/wrk checkout, so this costs nothing on the others.
                #
                # A server is exempt, though, and `enableClaude = false` alone
                # was not enough to make that true: the project layer installs
                # its own agent tooling (a claude switcher, an MCP sync, a user
                # timer) through this list, so the homelab kept getting it after
                # the public agent features were switched off. Employer tooling
                # on a personal server is backwards on its own terms, and it is
                # worse on this host in particular, which now stores an opaque
                # copy of ~/wrk and has no interactive session to justify any of
                # it. Gated here rather than inside each layer, so a future
                # project repo cannot forget.
                ++ nixpkgs.lib.optionals (!isServer) wrkHmModules;
                extraSpecialArgs = {
                  inherit
                    inputs
                    isWsl
                    isServer
                    ;
                  vars = hostVars;
                  # Every NixOS host owns its own graphical layer, so nothing
                  # here is terminal-only. Provided rather than left to the
                  # module default because a specialArg that is not passed at
                  # all resolves through `_module.args` and fails.
                  terminalOnly = false;
                  inherit
                    enableClaude
                    enableGemini
                    enableOpencode
                    enablePi
                    ;
                };
              };
            }
          ]
          ++ privateNixosModules
          # Same exemption as the home-manager list above, and it matters more
          # here: this layer DECLARES sops secrets, and a declared secret that
          # cannot be decrypted fails activation outright. Once the homelab
          # holds only its own age key, every employer secret declared on it
          # would be undecryptable and the host would stop rebuilding. Keeping
          # employer secrets off a personal storage server is the right call on
          # its own terms anyway.
          ++ nixpkgs.lib.optionals (!isServer) wrkNixosModules
          ++ extraModules;
        };

      # Source tree of the private flake, or null without it. The ISO carries
      # this so `nixos-install` can resolve the private input from disk.
      privateSrc = if private != null then private.outPath else null;

      isos = import ./generators {
        inherit
          inputs
          vars
          system
          pkgs
          lanzaboote
          sops-nix
          caelestia
          claudeOverlay
          privateHmModules
          privateSrc
          ;
      };

    in
    {
      nixosConfigurations = {
        # Standard desktop/laptop configurations (isWsl defaults to false)
        #
        # `backup` carries the Syncthing folder password for `wrk`, so it goes
        # to the three hosts that hold that folder in plaintext and to nothing
        # else. The homelab's absence from this list is the mechanism that
        # keeps it an untrusted device, and `vm` is left out because it does
        # not import the syncthing module that declares the option.
        desktop = fnMountSystem {
          hostname = "desktop";
          extraModules = privateNixosModule "backup";
        };
        laptop = fnMountSystem {
          hostname = "laptop";
          extraModules = privateNixosModule "backup";
          hostVars = vars // {
            desktop = "gnome";
          };
        };
        vm = fnMountSystem { hostname = "vm"; };

        # WSL configuration with explicit flag
        wsl = fnMountSystem {
          hostname = "wsl";
          extraModules = [
            nixos-wsl.nixosModules.default
          ]
          ++ privateNixosModule "sops-wsl"
          ++ privateNixosModule "backup";
          isWsl = true;
        };

        # Homelab server (headless, no desktop)
        homelab = fnMountSystem {
          hostname = "homelab";
          # No `privateNixosModule "hermes"` here on purpose: the host now
          # stores an opaque copy of ~/wrk, so it must not run an agent that
          # could be talked into reading it. The hermes module stays in the
          # repo, evaluated by no host, so rewiring it is a one-line revert.
          extraModules = privateNixosModule "homelab";
          isServer = true;
          # A storage host has no interactive session to run an agent in, and
          # the whole point of the encrypted setup is that whatever lands here
          # cannot read the data.
          enableClaude = false;
          enableGemini = false;
          enableOpencode = false;
          enablePi = false;
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
              overlays = [ claudeOverlay ];
            };
            extraSpecialArgs = {
              inherit inputs;
              vars = wslVars;
              isWsl = true;
              isServer = false;
              # `isWsl` already drops the graphical tree in home/default.nix;
              # this only has to be defined, not true.
              terminalOnly = false;
              enableClaude = false;
              enableGemini = false;
              enableOpencode = false;
              enablePi = false;
            };
            modules = [
              ./home
            ]
            ++ privateHmModules;
          };

        # Work laptop: standalone home-manager over an employer's own image,
        # which carries their device management agent. Their system layer stays
        # theirs and nix owns the userland only. See home/profiles/wrk.
        #
        # `private` is deliberately absent, unlike every other output: that
        # module is the personal fleet (personal secrets, personal repos, the
        # syncthing peers) and none of it belongs on a machine someone else
        # administers. The employer layer arrives through `wrk` instead, which
        # is empty until `switch` points it at a project checkout.
        wrk =
          let
            wrkVars = vars // {
              desktop = null;
            };
          in
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ claudeOverlay ];
            };
            extraSpecialArgs = {
              inherit inputs;
              vars = wrkVars;
              isWsl = false;
              isServer = false;
              terminalOnly = true;
              enableClaude = true;
              enableGemini = true;
              enableOpencode = true;
              enablePi = true;
            };
            modules = [
              ./home/profiles/wrk
            ]
            ++ wrkHmModules;
          };
      };

      packages.${system} = {
        desktop-iso = isos.desktop;
        laptop-iso = isos.laptop;
        homelab-iso = isos.homelab;
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
        wrk = self.homeConfigurations.wrk.activationPackage;

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
        # The upstream git-hooks.nix shellHook ends by pinning a LOCAL
        # core.hooksPath at this repo's own .git/hooks, and a local value
        # shadows the global one set in home/features/cli/git. Left as it is,
        # a single `nix develop` would quietly disable the commit format hooks
        # in this repo, of all places.
        #
        # Dropping the local override is safe precisely because the global
        # dispatchers delegate to .git/hooks first, which is exactly where
        # git-hooks.nix installs its own hook. Both sets keep running.
        shellHook = self.checks.${system}.pre-commit.shellHook + ''
          git config --local --unset core.hooksPath 2>/dev/null || true
        '';
        packages = [ pkgs.sops ];
      };

      # nixfmt-tree (treefmt wrapper), not bare nixfmt: `nix fmt` with no
      # arguments passes none through, and bare nixfmt then reads empty stdin
      # and dies with "unexpected end of input". The wrapper walks the tree.
      #
      # Do nixpkgs cru, e nao do `pkgs` com overlay: formatar .nix nao precisa
      # de nenhum pacote do overlay, e sair pelo overlay forcaria a busca dos
      # inputs privados so para rodar o formatador. A CI nao tem as chaves,
      # entao o `nix fmt` dela morria em fetch antes de olhar um arquivo.
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
