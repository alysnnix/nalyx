{ lib, ... }:
# Declared apart from default.nix because a module that carries an `options`
# section has to move every config attribute under `config`, and restructuring
# the whole git feature to add one option is a worse trade than one small file.
{
  options.modules.cli.git.extraSigners = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          principal = lib.mkOption {
            type = lib.types.str;
            example = "*@employer.example";
            description = "Signer identity, matched as a pattern by ssh-keygen.";
          };
          key = lib.mkOption {
            type = lib.types.str;
            example = "ssh-ed25519 AAAAC3Nz...";
            description = "The public key. A trailing comment is tolerated by ssh-keygen.";
          };
        };
      }
    );
    default = [ ];
    description = ''
      Identities appended to ~/.ssh/allowed_signers beyond the user's own.

      Exists so a private per-project module can register an employer identity
      for verification without that address or key ever appearing in this
      public repo. Principals are patterns, so naming a domain is enough.
    '';
  };
}
