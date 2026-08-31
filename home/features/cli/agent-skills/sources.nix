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
# `nix hash convert`.
let
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
