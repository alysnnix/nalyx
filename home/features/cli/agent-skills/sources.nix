{ pkgs, lib }:

# Third-party agent skills, pinned by revision.
#
# Upstream ships a monorepo whose skill directories live under `skills/<name>`,
# so each entry carries the subdirectory holding its SKILL.md rather than
# pointing at the repo root.
#
# Pinning here freezes the skill *instructions* only. Superdesign drives
# `npx --yes @superdesign/cli@latest`, an unpinned remote fetch, so the code
# that actually runs is not reproducible from this repo.
#
# agent-browser's skill is a discovery stub: it only tells the agent to run
# `agent-browser skills get core`, so the workflow text the agent finally reads
# is served by the installed CLI and tracks its version, not this pin. That CLI
# is pinned by this repo too, in `packages/agent-browser.nix`.
#
# Bumping a pin is `nix-prefetch-url --unpack <tarball>` piped through
# `nix hash convert`. The Orca entries below are the exception: they pin single
# files, so bumping one is `nix store prefetch-file <url>`, which prints the SRI
# hash directly.
let
  # Orca's skills are pinned file by file rather than with fetchFromGitHub, and
  # this is a deliberate break from the shape above. Each of them is a single
  # SKILL.md of a few kilobytes, while stablyai/orca is a ~730 MB repo (it is a
  # whole Electron IDE), so a tarball fetch would trade 6 KB of instructions for
  # a download of that size on every host that switches. The raw endpoint at a
  # pinned commit serves the same immutable bytes the tarball would carry.
  #
  # One rev for both, since they are read together and drift between two halves
  # of the same registry is not worth the second knob.
  orcaRev = "12f2c6b991dc80973827464bee3f629ebc0fc753";

  orcaSkill = name: hash: {
    src = pkgs.runCommandLocal "orca-skill-${name}" { } ''
      mkdir -p "$out/skills/${name}"
      cp ${
        pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/stablyai/orca/${orcaRev}/skills/${name}/SKILL.md";
          inherit hash;
        }
      } "$out/skills/${name}/SKILL.md"
    '';
    subdir = "skills/${name}";
  };

  skills = {
    agent-browser = {
      src = pkgs.fetchFromGitHub {
        owner = "vercel-labs";
        repo = "agent-browser";
        rev = "fbd046c23a2c1156891bda294aaaee715c23b3f1";
        hash = "sha256-uz60SvvQYdUCjLJAcuCtQyGd0yNc82m+GYruMnn5CD4=";
      };
      subdir = "skills/agent-browser";

      # Upstream's install line tells the agent to `npm i -g agent-browser &&
      # agent-browser install`. Here the CLI comes from Nix and is already on
      # PATH, and `agent-browser install` fetches a Chrome-for-Testing build
      # whose ELF will not run on NixOS, so the advice is actively harmful.
      #
      # `--replace-fail`, not `--replace`/`--replace-quiet`: if upstream ever
      # rewords that line the build must fail loudly so the pin gets
      # re-reviewed, rather than silently shipping stale advice.
      postProcess = ''
        substituteInPlace SKILL.md \
          --replace-fail 'Install: `npm i -g agent-browser && agent-browser install`' 'Install: already installed system-wide by Nix; `agent-browser` is on PATH with Chrome pre-wired via `AGENT_BROWSER_EXECUTABLE_PATH`. Never run `agent-browser install`, `npm i -g agent-browser`, or `agent-browser upgrade`: the Chrome build they download will not run on NixOS. To change versions, bump `packages/agent-browser.nix` in the nalyx repo.'
      '';
    };

    # Orca's two orchestration stubs. Both are discovery stubs: they only tell
    # the agent to resolve Orca's own executable and load the version matched
    # guide from it, so no `postProcess` is needed. Their resolution order is
    # already right on these machines, and notably warns the agent off bare
    # `orca`, which on Linux is the GNOME screen reader.
    #
    # Nothing installs an Orca CLI here on purpose. On a host reached over SSH,
    # Orca exports ORCA_CLI_COMMAND into the terminals it opens itself, which is
    # the only path in that resolution order that exists on a machine where the
    # GUI lives elsewhere.
    #
    # computer-use, the third skill in that registry, is deliberately absent: it
    # drives a desktop, and on the WSL host the desktop is Windows'. Orca's own
    # browser skill is absent too, because agent-browser above already owns that
    # job and its instructions say to prefer it over other browser tooling.
    orca-cli = orcaSkill "orca-cli" "sha256-shubgEdcNZlrnARjebnJ+niPLTV8npF779irGzffLnc=";
    orchestration = orcaSkill "orchestration" "sha256-99oN1A2GgeKwMD+g+i9+5ONvLspklaSvV7krmFff9zI=";

    superdesign = {
      src = pkgs.fetchFromGitHub {
        owner = "superdesigndev";
        repo = "superdesign-skill";
        rev = "f9f05cd988c247dce6c072eaf9ac6b162f2ffc4b";
        hash = "sha256-fHenfYIsKCIkSKkyjW0t5mXjrZ4HE1NZiVmReHUsTjs=";
      };
      subdir = "skills/superdesign";
    };
  };

  # Collect every pinned skill into one directory tree. Each top-level skill
  # directory also gets a `.nix-managed` marker, the same contract the Claude
  # skills use, so the activation script can tell managed skills apart from
  # ones installed by hand without restating their names anywhere.
  #
  # An entry may carry an optional `postProcess` shell snippet, run inside its
  # own copied directory, for patching instructions that do not hold here.
  agentSkillsSrc = pkgs.runCommandLocal "agent-skills" { } (
    "mkdir -p $out\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: skill:
        ''
          cp -r --no-preserve=mode '${skill.src}/${skill.subdir}' "$out/${name}"
          touch "$out/${name}/.nix-managed"
        ''
        + lib.optionalString (skill ? postProcess) ''
          (
            cd "$out/${name}"
            ${skill.postProcess}
          )
        ''
      ) skills
    )
  );
in
{
  inherit agentSkillsSrc;
}
