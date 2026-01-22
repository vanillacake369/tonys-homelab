{lib}: let
  supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  forAllSystems = f: lib.genAttrs supportedSystems f;
  mainSystem = "x86_64-linux";
in {
  inherit mainSystem supportedSystems forAllSystems;
}
