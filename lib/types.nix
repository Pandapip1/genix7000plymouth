# Extensions to nixpkgs lib.types
# These are planned to be upstreamed
{
  lib,
}:

let
  mkTypeBetween =
    type: start: end:
    lib.recursiveUpdate (lib.types.addCheck type (x: x >= start && x <= end)) {
      description = "${type.description} between ${toString start} and ${toString end}";
    };
in
{
  # Add'l types
  color =
    lib.types.addCheck lib.types.str (
      str:
      (lib.hasPrefix "#" str)
      && (lib.stringLength str == 7)
      && (lib.match "^[0-9a-fA-F]+$" (lib.substring 1 (lib.stringLength str - 1) str) != null)
    )
    // {
      description = "hexadecimal color code";
    };
  
  # Type functions
  intBetween = mkTypeBetween lib.types.int;
  floatBetween = mkTypeBetween lib.types.float;
}
