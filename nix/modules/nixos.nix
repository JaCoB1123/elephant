flake: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.elephant;
  settingsFormat = pkgs.formats.toml {};
  startScript = pkgs.writeShellScript "elephant-start" ''
    session_path="$(${pkgs.systemd}/bin/systemctl --user show-environment | while IFS= read -r line; do
      case "$line" in
        PATH=*) printf '%s' "''${line#PATH=}"; break ;;
      esac
    done)"

    if [ -n "$session_path" ]; then
      export PATH="$session_path''${PATH:+:$PATH}"
    fi

    exec ${cfg.package}/bin/elephant ${optionalString cfg.debug "--debug"}
  '';
  defaultProviders = [
    "bluetooth"
    "bookmarks"
    "calc"
    "clipboard"
    "desktopapplications"
    "files"
    "menus"
    "playerctl"
    "providerlist"
    "runner"
    "snippets"
    "symbols"
    "todo"
    "unicode"
    "websearch"
    "windows"
    "bitwarden"
    "1password"
    "nirisessions"
    "niriactions"
  ];
in {
  imports = [
    # Deprecated: delete with v3.0.0 release
    (lib.mkRenamedOptionModule ["services" "elephant" "config"] ["services" "elephant" "settings"])
  ];

  options.services.elephant = {
    enable = mkEnableOption "Elephant launcher backend system service";

    package = mkOption {
      type = types.package;
      default = flake.packages.${pkgs.stdenv.system}.elephant-with-providers;
      defaultText = literalExpression "flake.packages.\${pkgs.stdenv.system}.elephant-with-providers";
      description = "The elephant package to use.";
    };

    providers = mkOption {
      type = types.listOf (types.str);
      default = defaultProviders;
      example = defaultProviders;
      description = ''
        List of built-in providers to enable.
      '';
    };

    installService = mkOption {
      type = types.bool;
      default = true;
      description = "Create a systemd service for elephant.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug logging for elephant service.";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = settingsFormat.type;
      };
      default = {};
      example = literalExpression ''
        {
          auto_detect_launch_prefix = false;
        }
      '';
      description = ''
        elephant/elephant.toml run `elephant generatedoc` to view available options.
      '';
    };

    provider = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          # Generic Options
          settings = mkOption {
            type = types.submodule {
              freeformType = settingsFormat.type;
            };
            default = {};
            description = ''
              Provider specific toml configuration as Nix attributes. Run `elephant generatedoc` to view available options.
            '';
          };

          # Menus Provider Settings
          # provider.menus.toml
          toml = mkOption {
            type = types.attrsOf (types.submodule {
              freeformType = settingsFormat.type;
            });
            example =
              literalExpression
              ''
                {
                  "bookmarks" = {
                    name = "bookmarks";
                    name_pretty = "Bookmarks";
                    icon = "bookmark";
                    action = "xdg-open %VALUE%";

                    entries = [
                      {
                        text = "Walker";
                        value = "https://github.com/abenz1267/walker";
                      }
                      {
                        text = "Elephant";
                        value = "https://github.com/abenz1267/elephant";
                      }
                      {
                        text = "Drive";
                        value = "https://drive.google.com";
                      }
                      {
                        text = "Prime";
                        value = "https://www.amazon.de/gp/video/storefront/";
                      }
                    ];
                  };
                }
              '';
            default = {};
            description = "Declaratively define menus using TOML.";
          };

          # provider.menus.lua
          lua = mkOption {
            type = types.attrsOf types.lines;
            default = {};
            example = literalExpression ''
              {
                "luatest" = \'\'
                  Name = "luatest"
                  NamePretty = "Lua Test"
                  Icon = "applications-other"
                  Cache = true
                  Action = "notify-send %VALUE%"
                  HideFromProviderlist = false
                  Description = "lua test menu"
                  SearchName = true

                  function GetEntries()
                      local entries = {}
                      local wallpaper_dir = "/home/andrej/Documents/ArchInstall/wallpapers"

                      local handle = io.popen("find '" ..
                          wallpaper_dir ..
                          "' -maxdepth 1 -type f -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' -o -name '*.bmp' -o -name '*.webp' 2>/dev/null")
                      if handle then
                          for line in handle:lines() do
                              local filename = line:match("([^/]+)$")
                              if filename then
                                  table.insert(entries, {
                                      Text = filename,
                                      Subtext = "wallpaper",
                                      Value = line,
                                      Actions = {
                                          up = "notify-send up",
                                          down = "notify-send down",
                                      },
                                      -- Preview = line,
                                      -- PreviewType = "file",
                                      -- Icon = line
                                  })
                              end
                          end
                          handle:close()
                      end

                      return entries
                  end
                \'\';
            '';
            description = "Declaratively define menus using Lua.";
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
          websearch.settings = {
            entries = [
              {
                name = "NixOS Options";
                url = "https://search.nixos.org/options?query=%TERM%";
              }
            ];
          };
        }
      '';
      description = "Provider specific settings";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    environment.etc =
      mkMerge
      [
        # Generate elephant config
        {
          "xdg/elephant/elephant.toml" = mkIf (cfg.settings != {}) {
            source = settingsFormat.generate "elephant.toml" cfg.settings;
          };
        }

        # Generate provider configs
        (mapAttrs'
          (
            name: {settings, ...}:
              lib.nameValuePair
              "xdg/elephant/${name}.toml"
              {
                source = settingsFormat.generate "${name}.toml" settings;
              }
          )
          (lib.filterAttrs (n: v: v.settings != {}) cfg.provider))

        (lib.mkIf (cfg.provider ? "menus")
          # Generate TOML menu files
          (mapAttrs'
            (
              name: value:
                lib.nameValuePair
                "xdg/elephant/menus/${name}.toml"
                {
                  source = settingsFormat.generate "${name}.toml" value;
                }
            )
            cfg.provider.menus.toml))

        # Generate Lua menu files
        (lib.mkIf (cfg.provider ? "menus")
          (mapAttrs'
            (
              name: value:
                lib.nameValuePair
                "xdg/elephant/menus/${name}.lua"
                {
                  text = value;
                }
            )
            cfg.provider.menus.lua))
      ];

    systemd.user.services.elephant = mkIf cfg.installService {
      description = "Elephant launcher backend";
      after = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      wantedBy = ["graphical-session.target"];

      unitConfig = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 1;
        Environment = "ELEPHANT_PROVIDER_DIR=${cfg.package}/lib/elephant/providers";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -f /tmp/elephant.sock";
      };

      restartTriggers = [
        (builtins.hashString "sha256" (builtins.toJSON {
          inherit (cfg) settings providers provider debug;
        }))
      ];
    };
  };
}
