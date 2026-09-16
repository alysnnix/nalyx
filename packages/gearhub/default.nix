# Gearhub: a small local web dashboard that unifies peripheral control on the
# desktop host. It only fronts tools that already exist (ddcutil for the AOC
# monitors, solaar for the Logitech mouse, OpenLinkHub's REST API for the
# Corsair cooler), never the hardware itself.
#
# Stdlib-only Go with the UI embedded via `embed`, so there is nothing to
# vendor and vendorHash stays null.
{ buildGoModule }:

buildGoModule {
  pname = "gearhub";
  version = "0.1.0";
  src = ./src;
  vendorHash = null;
}
