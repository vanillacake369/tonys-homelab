# NixOS Adapter
# Transforms domain data into NixOS module options
# Usage: import this with { inherit domains pkgs; profile = "server"; }
{
  domains,
  pkgs,
  lib ? pkgs.lib,
  profile ? "server",
}: let
  shellDomain = domains.shell;
  packagesDomain = domains.packages;
  editorDomain = domains.editor;

  # Resolve packages for the given profile
  profileGroups = packagesDomain.profiles.${profile} or packagesDomain.profiles.server;
  resolvedPackages = builtins.concatLists (
    map (groupName:
      let group = packagesDomain.groups.${groupName} or (_: []);
      in group pkgs
    ) profileGroups
  );

  # Combine all shell functions
  allFunctions = builtins.concatStringsSep "\n" (builtins.attrValues shellDomain.functions);
  linuxFunctions = builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsLinux or {}));
in {
  # Shell configuration for NixOS
  shell = {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = shellDomain.aliases;
      interactiveShellInit = ''
        ${allFunctions}
        ${lib.optionalString pkgs.stdenv.isLinux linuxFunctions}
      '';
    };
  };

  # Packages configuration for NixOS
  packages = {
    environment.systemPackages = resolvedPackages;
  };

  # Editor configuration for NixOS
  editor = {
    programs.neovim = {
      enable = editorDomain.neovim.enable;
      defaultEditor = editorDomain.neovim.defaultEditor;
    };
  };

  # Combined: all configurations merged
  all = lib.mkMerge [
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestions.enable = true;
        syntaxHighlighting.enable = true;
        shellAliases = shellDomain.aliases;
        interactiveShellInit = ''
          ${allFunctions}
          ${lib.optionalString pkgs.stdenv.isLinux linuxFunctions}
        '';
      };

      programs.neovim = {
        enable = editorDomain.neovim.enable;
        defaultEditor = editorDomain.neovim.defaultEditor;
      };

      environment.systemPackages = resolvedPackages;
    }
  ];
}
