{ pkgs, lib }:

# Third-party agent skills, pinned by revision.
#
# Upstream ships a monorepo whose skill directories live under `skills/<name>`,
# so each entry carries the subdirectory holding its SKILL.md rather than
# pointing at the repo root.
#
# Pinning here freezes the skill *instructions* only. Superdesign drives
# `npx --yes @superdesign/cli@latest`, an unpinned remote fetch, so the code
# that actually runs is not reproducible from this repo. Bumping a pin is
# `nix-prefetch-url --unpack <tarball>` piped through `nix hash convert`.
let
  skills = {
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
  agentSkillsSrc = pkgs.runCommandLocal "agent-skills" { } (
    "mkdir -p $out\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: skill: ''
        cp -r --no-preserve=mode '${skill.src}/${skill.subdir}' "$out/${name}"
        touch "$out/${name}/.nix-managed"
      '') skills
    )
  );
in
{
  inherit agentSkillsSrc;
}
