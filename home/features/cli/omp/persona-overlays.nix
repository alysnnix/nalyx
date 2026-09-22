# One OMP config overlay per persona, on top of ./config-overlay.nix.
#
# A persona skill (`persona = "<name>"` in ../agent-skills/sources.nix) ships
# hidden: discovered everywhere, advertised nowhere, so an ordinary session
# never pays for instructions it will not use. An overlay from this file is
# what turns one persona back on, by pointing `skills.customDirectories` at the
# unhidden copies of exactly that persona's skills. Custom-directory skills
# override same-named provider skills, so the hidden copy loses and the session
# gets the bundle in its prompt.
#
# Two consumers, one definition, same reason ./config-overlay.nix is a
# standalone file:
#
#   - ./default.nix links each overlay to ~/.config/omp/persona-<name>.yml, so
#     a terminal session can opt in:
#       PI_CONFIG_FILES="$PI_CONFIG_FILES:$HOME/.config/omp/persona-frontend.yml" omp
#   - modules/services/paseo.nix gives it to a derived provider
#     (`agents.providers.omp-frontend`), which is what makes a Paseo agent a
#     persona: the provider's env is merged into every session it launches, on
#     create, resume and refresh alike, and an `agentProfiles` entry pointing at
#     that provider is how the persona reaches the model picker.
#
# Note for whoever sets PI_CONFIG_FILES by hand: the variable is a colon
# separated list and it is read whole, so a persona overlay is appended to the
# base one, never substituted for it.
{ pkgs, lib }:
let
  inherit (import ../agent-skills/sources.nix { inherit pkgs lib; }) personaSkillsSrc;

  yamlFormat = pkgs.formats.yaml { };
in
lib.mapAttrs (
  persona: skillsDir:
  yamlFormat.generate "omp-persona-${persona}.yml" {
    skills.customDirectories = [ "${skillsDir}" ];
  }
) personaSkillsSrc
