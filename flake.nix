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
      # v1.1 supports the current Bootspec API in nixos-unstable.
      url = "github:nix-community/lanzaboote/v1.1.0";
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
    # Pinned to a release tag, not the default branch: the local patches in
    # packages/paseo/ are regenerated against one exact tree, so a bump is a
    # deliberate edit here, never a side effect of `nix flake update`.
    paseo = {
      url = "github:getpaseo/paseo/v0.9.1";
    };

    # paseo-github: o plugin de integracao com o GitHub para o Paseo, repo
    # proprio e publico (`alysnnix/paseo-github-integration`). Nasceu como fork
    # do `gpambrozio/paseo-plugins`, mas o fork carregava mais dois plugins que
    # nao sao nossos e um deles so roda em macOS; o repo novo e so o plugin,
    # com a licenca e o credito preservados no README.
    #
    # `github:` agora que e publico: o fetcher tarball dispensa chave e e mais
    # rapido que clonar, e a CI passa a alcancar o input de verdade em vez de
    # receber o placeholder vazio. O guard `hasPaseoGithub` fica de pe assim
    # mesmo, porque e ele quem sustenta um clone sem acesso a rede.
    #
    # Segue nixpkgs porque o pacote e uma copia de fontes: nao compila nada e
    # nao tem hash de dependencia para preservar.
    paseo-github = {
      url = "github:alysnnix/paseo-github-integration/v1.0.0";
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

    # teamclaude: local rotating reverse proxy that pools several Claude
    # subscriptions behind one ANTHROPIC_BASE_URL (home/features/cli/claude/
    # account-pool.nix). Follows nixpkgs: the package is a copy of plain JS
    # sources run by nodejs_24, so there is no build or dependency hash to keep.
    # Pinned to the exact audited rev, not the default branch: the proxy holds
    # every account's OAuth tokens, so a bump has to be a deliberate edit here
    # with the src/ diff reviewed, never a side effect of `nix flake update`.
    teamclaude = {
      url = "github:KarpelesLab/teamclaude/3d5bb6f12148cdcfb7a97b6b9c2737ff89a80bed";
      inputs.nixpkgs.follows = "nixpkgs";
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
      url = "git+ssh://git@github.com/alysnnix/nix-priv-personal";
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
    # the .private/nix-priv-<project> checkout when one is present, so the name
    # only ever lives on the machine that needs it. Clone a different project's
    # layer there and the same profile serves the next job.
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
      # Como o node nomeia esta plataforma, o sufixo dos `prebuilds/` do node-pty.
      nodePlatform =
        {
          x86_64-linux = "linux-x64";
          aarch64-linux = "linux-arm64";
        }
        .${system};

      # O placeholder que a CI injeta no lugar do repo privado nao tem saida
      # nenhuma, entao a presenca do pacote e a pergunta certa: um `? null` no
      # argumento nao ajudaria porque o input existe nos dois casos, com
      # conteudo diferente.
      hasPaseoGithub =
        inputs.paseo-github ? packages
        && inputs.paseo-github.packages ? ${system}
        && inputs.paseo-github.packages.${system} ? github-integration;

      # O build Nix do Paseo perde o addon nativo do node-pty.
      # `scripts/trace-daemon.mjs` monta o closure por tracing estatico e
      # precisa listar a mao o que e carregado por path computado; a linha que
      # cobre o node-pty (em 0.9.1, um glob por
      # `node_modules/node-pty/prebuilds/<plat>-<arch>/**`) aponta para a raiz,
      # mas o npm aninha o pacote em `packages/server/node_modules/node-pty` e
      # nao existe copia na raiz. O glob casa zero arquivos sem erro nenhum, e
      # nenhum `pty.node` chega ao $out.
      #
      # O daemon sobe assim mesmo, porque o terminal roda em processo separado:
      # o worker morre no import, o supervisor sobrevive, e o sintoma so
      # aparece no primeiro uso, como
      # `TERMINAL_CREATE_FAILED: Terminal worker is not running`. Sem terminal
      # nao ha agente, entao isso derruba o produto inteiro, nao um extra.
      #
      # De onde vem o addon: o node-pty 1.2 traz `prebuilds/<plat>-<arch>/` para
      # linux, darwin e win32, e o `npm rebuild node-pty` do buildPhase acha o
      # prebuild da plataforma e nem chama o node-gyp, entao `build/Release`
      # nunca existe na arvore de build. So um deles serve, e o caminho
      # completo e o que o escolhe. A versao anterior fazia
      # `find -name pty.node -print -quit`, e o primeiro na ordem do filesystem
      # muda de maquina para maquina: no WSL veio o linux-x64, no laptop veio um
      # Mach-O de darwin e o worker morreu com "invalid ELF header". Mesmo
      # store path, conteudo diferente, ou seja um build nao reprodutivel. A
      # checagem do magic number fecha a porta caso o layout mude de novo.
      #
      # Copiado para build/Release, que e o primeiro lugar onde o loader do
      # node-pty procura, e em postInstall e nao em installPhase porque o
      # autoPatchelfHook roda depois, em postFixup, e ainda patcheia o addon
      # contra o libuv que ja esta em buildInputs. Percorre os dois pacotes
      # pelo mesmo caminho: o desktop instala em share/paseo-desktop e sofre do
      # mesmo furo.
      fixPtyNode =
        pkg:
        pkg.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            ptySrc=$(find . -path '*/node-pty/prebuilds/${nodePlatform}/pty.node' -print -quit)
            if [ -z "$ptySrc" ]; then
              echo "fixPtyNode: nenhum pty.node em node-pty/prebuilds/${nodePlatform}" >&2
              exit 1
            fi
            if ! head -c 4 "$ptySrc" | grep -q 'ELF'; then
              echo "fixPtyNode: $ptySrc nao e um ELF" >&2
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

      # Patches locais sobre o input do Paseo, aplicadas nesta ordem. Nenhuma
      # delas vira PR upstream: sao ajustes pro uso daqui, e um fork so traria
      # um segundo lock pra manter. Como patch, o dia em que o upstream mexer
      # nesses arquivos o build quebra alto, na hora do bump, em vez de um
      # rebase silencioso ficar pendurado num fork.
      #
      # Os dois pacotes saem do mesmo `src`, entao os dois levam as patches: o
      # daemon serve a web UI e o desktop empacota a sua. O `npmDeps` e um FOD
      # separado, montado do package-lock.json, que patch nenhuma toca: o hash
      # continua valendo.
      #
      # 1. sidebar-group-by-label: `SidebarGroupMode` do upstream so tem
      #    `project` e `status`, entao workspace de trabalho e workspace pessoal
      #    dividem a mesma lista e a unica separacao possivel e o filtro, que
      #    esconde em vez de agrupar.
      #
      # 2. project-default-labels: a label so existia por workspace, e cada chat
      #    e um workspace novo, entao marcar o que e trabalho custava uma visita
      #    a cada chat. O projeto passa a carregar labels padrao (`defaultLabels`
      #    em projects.json) e todo workspace criado nele ja nasce com elas;
      #    renomear ou apagar uma label no catalogo acompanha os padroes.
      #
      # 3. label-manager-entry: o gerenciador de labels (renomear, recolorir,
      #    apagar) ja existe no upstream, mas so se chega nele por dentro da
      #    pagina de filtro, que por sua vez some quando o catalogo esta vazio.
      #    A patch poe a entrada na raiz do menu de exibicao da sidebar.
      #
      # Os testes vao em arquivos `*.tests.patch` que o Nix nao aplica: o filtro
      # de `src` do proprio Paseo descarta todo `*.test.ts` antes do build, entao
      # um hunk sobre eles nao acha o arquivo e derruba o patchPhase inteiro.
      # Eles existem pra rodar `npm test` num checkout de verdade, que e onde
      # teste serve.
      paseoLocalPatches =
        pkg:
        pkg.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./packages/paseo/sidebar-group-by-label.patch
            ./packages/paseo/project-default-labels.patch
            ./packages/paseo/label-manager-entry.patch
          ];
        });

      # O `nix/npm-deps.hash` da tag v0.9.1 ficou para tras: o commit de
      # release mexeu no package-lock.json (bump de versao) e o hash nao foi
      # regenerado, entao o FOD do upstream falha com hash mismatch mesmo com
      # o nixpkgs dele. O `.override { npmDepsHash }` e a porta que o proprio
      # nix/package.nix abre para isso. O desktop reusa o `npmDeps` do daemon
      # (`inherit (paseo) npmDeps`), entao recebe o daemon corrigido em vez de
      # um hash seu. Num bump, apague o override primeiro: se o hash do
      # upstream bater, ele nao faz mais falta.
      paseoUpstream = inputs.paseo.packages.${system}.default.override {
        npmDepsHash = "sha256-9UWtpZrCdyYyGq3HGNgSpU1+2Imu3oYqtSumq2DtANc=";
      };
      paseoDesktopUpstream = inputs.paseo.packages.${system}.desktop.override {
        paseo = paseoUpstream;
      };

      # teamclaude with one local fix, same reasoning as the Paseo patches: a
      # fork would be one more lock to keep, and a patch breaks loudly on the
      # bump that touches the file. hold-retry-refused-accounts: with
      # `holdSeconds` set, a request that was itself refused by every account
      # is held but never retried, because the accounts that refused it stay in
      # its per-request `tried` set, so it waits out the whole budget even when
      # a window resets a minute later. That request is the running agent's
      # current turn, so the bug turns a reset into a stall of `holdSeconds`.
      # Reproduced against a mock upstream (one 429, reset 12s later, the proxy
      # never asked again in 150s); upstream's own suite passes with it. Only
      # quota and transient refusals are let back, never a 401/403, so a dead
      # credential is not asked again on every poll of a hold.
      teamclaude = inputs.teamclaude.packages.${system}.teamclaude.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./packages/teamclaude/hold-retry-refused-accounts.patch ];
      });

      claudeOverlay =
        _: _:
        {
          claude-code = llm-agents.packages.${system}.claude-code;
          omp = llm-agents.packages.${system}.omp;
          pi = llm-agents.packages.${system}.pi;
          herdr = inputs.herdr.packages.${system}.default;
          paseo = fixPtyNode (paseoLocalPatches paseoUpstream);
          paseo-desktop = fixPtyNode (paseoLocalPatches paseoDesktopUpstream);
          inherit teamclaude;
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
                # a project layer cloned, so this costs nothing on the others.
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
        # Standard desktop configurations (isWsl defaults to false)
        #
        # `backup` carries the Syncthing folder password for `wrk`, so it goes
        # to the two hosts that hold that folder in plaintext and to nothing
        # else. The homelab's absence from this list is the mechanism that
        # keeps it an untrusted device, and `vm` is left out because it does
        # not import the syncthing module that declares the option.
        desktop = fnMountSystem {
          hostname = "desktop";
          # `paseo-desktop` traz o que a publicacao do Paseo na tailnet nao
          # pode declarar em publico: o nome MagicDNS deste no (que nomeia a
          # tailnet) e a chave da OpenAI para a voz. Sem a camada privada o
          # host ainda avalia, e a assertion do modulo e que reclama do fqdn
          # vazio.
          extraModules = privateNixosModule "backup" ++ privateNixosModule "paseo-desktop";
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
        homelab-iso = isos.homelab;
      };

      # Eval-only checks: validates all configurations without building
      # Run with: nix flake check --no-build
      checks.${system} = {
        desktop = self.nixosConfigurations.desktop.config.system.build.toplevel;
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
