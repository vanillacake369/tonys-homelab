# Auto-discovers *.overlay.nix files from a module directory (recursive).
# Convention: place foo.overlay.nix next to foo.nix to declare overlays
# that foo.nix's packages need.
# Usage: collectOverlays ./atoms → [ overlay1 overlay2 ... ]
{lib}: dir: let
  # Recursively find all *.overlay.nix files
  findOverlays = path: let
    entries = builtins.readDir path;
    files = lib.pipe entries [
      (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".overlay.nix" n))
      builtins.attrNames
      (map (n: import (path + "/${n}")))
    ];
    dirs = lib.pipe entries [
      (lib.filterAttrs (_: t: t == "directory"))
      builtins.attrNames
      (map (n: findOverlays (path + "/${n}")))
      lib.flatten
    ];
  in
    files ++ dirs;
in
  findOverlays dir
