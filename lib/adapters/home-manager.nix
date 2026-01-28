# Home-Manager Adapter
# Transforms domain data into home-manager options
# Usage: import this with { inherit domains pkgs; profile = "dev"; }
{
  domains,
  pkgs,
  lib ? pkgs.lib,
  profile ? "dev",
}: let
  shellDomain = domains.shell;
  packagesDomain = domains.packages;
  editorDomain = domains.editor;
  usersDomain = domains.users;

  # Resolve packages for the given profile
  profileGroups = packagesDomain.profiles.${profile} or packagesDomain.profiles.dev;
  resolvedPackages = builtins.concatLists (
    map (groupName:
      let group = packagesDomain.groups.${groupName} or (_: []);
      in group pkgs
    ) profileGroups
  );

  # Combine all shell functions
  allFunctions = builtins.concatStringsSep "\n" (builtins.attrValues shellDomain.functions);

  # Platform-specific functions
  darwinFunctions = builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsDarwin or {}));
  linuxFunctions = builtins.concatStringsSep "\n" (builtins.attrValues (shellDomain.functionsLinux or {}));

  platformFunctions =
    if pkgs.stdenv.isDarwin then darwinFunctions
    else if pkgs.stdenv.isLinux then linuxFunctions
    else "";
in {
  # Shell configuration for home-manager
  shell = {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = shellDomain.aliases;
      initExtra = ''
        ${allFunctions}
        ${platformFunctions}
      '';
      oh-my-zsh = {
        enable = true;
        plugins = shellDomain.zsh.ohMyZsh.plugins;
      };
    };
  };

  # Packages configuration for home-manager
  packages = {
    home.packages = resolvedPackages;
  };

  # Editor configuration for home-manager
  editor = {
    programs.neovim = {
      enable = editorDomain.neovim.enable;
      defaultEditor = editorDomain.neovim.defaultEditor;
      viAlias = editorDomain.neovim.viAlias;
      vimAlias = editorDomain.neovim.vimAlias;
      vimdiffAlias = editorDomain.neovim.vimdiffAlias;
    };
  };

  # Git configuration for home-manager
  git = {
    programs.git = {
      enable = true;
      userName = usersDomain.git.name;
      userEmail = usersDomain.git.email;
    };
  };

  # Combined: all configurations merged
  all = lib.mkMerge [
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        shellAliases = shellDomain.aliases;
        initExtra = ''
          ${allFunctions}
          ${platformFunctions}
        '';
        oh-my-zsh = {
          enable = true;
          plugins = shellDomain.zsh.ohMyZsh.plugins;
        };
      };

      programs.neovim = {
        enable = editorDomain.neovim.enable;
        defaultEditor = editorDomain.neovim.defaultEditor;
        viAlias = editorDomain.neovim.viAlias;
        vimAlias = editorDomain.neovim.vimAlias;
        vimdiffAlias = editorDomain.neovim.vimdiffAlias;
      };

      programs.git = {
        enable = true;
        userName = usersDomain.git.name;
        userEmail = usersDomain.git.email;
      };

      home.packages = resolvedPackages;
    }
  ];
}
