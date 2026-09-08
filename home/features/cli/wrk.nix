{ lib, ... }:
# Option surface a per-project private layer is allowed to set.
#
# Declared here, in something every profile imports, rather than inside
# home/profiles/wrk where the options are acted on. The layer reaches NixOS
# hosts too (the WSL box does employer work), and those hosts do not import
# that profile, so an option declared only there would make a project module
# that sets it fail the whole host with "option does not exist".
#
# So: declared everywhere, honoured only by the work profile. Setting one of
# these on a host without that profile is a no-op rather than an error, which
# is the right trade for a layer that has to be portable across machines.
{
  options.modules.wrk = {
    pritunl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the Pritunl VPN client and the helper that registers its daemon.
        Honoured by home/profiles/wrk only.

        Default true because that profile exists for an employer-managed
        machine and a corporate VPN is the norm there. A project that uses
        something else turns it off from its own module.
      '';
    };
  };
}
