attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }: {
  programs = {
    waybar = {
      package = unstablePkgs.waybar;
      enable = true;
      systemd = {
        enable = true;
      };
      style = ''
        * {
            font-size: 16px;
            font-family: InconsolataGo Nerd Font Mono;
        }

        window#waybar {
            background: #292b2e;
            color: #fdf6e3;
        }

        #custom-right-arrow-dark,
        #custom-left-arrow-dark {
            color: #1a1a1a;
        }
        #custom-right-arrow-light,
        #custom-left-arrow-light {
            color: #292b2e;
            background: #1a1a1a;
        }

        #workspaces,
        #clock.1,
        #clock.2,
        #clock.3,
        #clock.toronto,
        #pulseaudio,
        #memory,
        #cpu,
        #custom-cpu-temp,
        #custom-gpu-info,
        #battery,
        #disk,
        #idle_inhibitor,
        #tray {
            background: #1a1a1a;
        }

        #workspaces button {
            padding: 0 2px;
            color: #fdf6e3;
        }
        #workspaces button.visible {
            color: #ff0000;
        }
        #workspaces button.focused {
            color: #268bd2;
        }
        #workspaces button:hover {
            box-shadow: inherit;
            text-shadow: inherit;
        }
        #workspaces button:hover {
            background: #1a1a1a;
            border: #1a1a1a;
            padding: 0 3px;
        }

        #pulseaudio {
            color: #268bd2;
        }
        #memory {
            color: #2aa198;
        }
        #cpu {
            color: #6c71c4;
        }
        #custom-cpu-temp {
            color: #cb4b16; /* Orange */
        }
        #custom-gpu-info {
            color: #2aa198; /* Cyan */
        }
        #battery {
            color: #859900;
        }
        #disk {
            color: #b58900;
        }

        #clock,
        #pulseaudio,
        #memory,
        #cpu,
        #custom-cpu-temp,
        #custom-gpu-info,
        #battery,
        #idle_inhibitor,
        #disk {
            padding: 0 10px;
        }
      '';
      settings = let
        # Determine which WM is enabled for this user
        useSway = homeManagerConfig.sway.enable or false;
        useHyprland = homeManagerConfig.hyprland.enable or false;
        # Define the workspace module name based on the enabled WM
        # Note: The assertion in lib/host.nix guarantees only one will be true
        workspacesModule = if useSway then "sway/workspaces" else "hyprland/workspaces";
      in {
        mainBar = {
          layer = "bottom";
          position = "top";
          height = 10;
          # Conditionally include the correct workspace module
          modules-left = [ workspacesModule "custom/right-arrow-dark" ];
          modules-center = [
            "custom/left-arrow-dark"
            "clock#1"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "clock#2"
            "clock#toronto"
            "custom/right-arrow-dark"
            "custom/right-arrow-light"
            "clock#3"
            "custom/right-arrow-dark"
          ];
          modules-right = [
            "custom/left-arrow-dark"
            "idle_inhibitor"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "pulseaudio"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "memory"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "cpu"
            "custom/cpu-temp"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "custom/gpu-info"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "battery"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "disk"
            "custom/left-arrow-light"
            "custom/left-arrow-dark"
            "tray"
          ];

          "custom/left-arrow-dark" = {
            format = "";
            tooltip = false;
          };
          "custom/left-arrow-light" = {
            format = "";
            tooltip = false;
          };
          "custom/right-arrow-dark" = {
            format = "";
            tooltip = false;
          };
          "custom/right-arrow-light" = {
            format = "";
            tooltip = false;
          };

          # Conditionally define sway/workspaces config
          "sway/workspaces" = lib.mkIf useSway {
            disable-scroll = true;
            format = "{name}";
          };

          # Conditionally define hyprland/workspaces config
          "hyprland/workspaces" = lib.mkIf useHyprland {
            disable-scroll = true;
            format = "{name}";
          };

          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
          };

          "clock#1" = {
            format = "{:%a}";
            tooltip = false;
          };
          "clock#2" = {
            format = "{:%H:%M:%S}";
            tooltip = false;
            interval = 1;
          };
          "clock#toronto" = {
            format = "CA: {:%H:%M}";
            tooltip = false;
            timezone = "America/Toronto";
          };
          "clock#3" = {
            format = "{:%m-%d}";
            tooltip = false;
          };

          pulseaudio = {
            format = "{icon} {volume:2}%";
            format-bluetooth = "{icon}  {volume}%";
            format-muted = "MUTE";
            format-icons = {
              headphones = "";
              default = [ "" "" ];
            };
            scroll-step = 5;
            on-click = "${pkgs.pamixer}/bin/pamixer -t";
            on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
          };
          memory = {
            interval = 5;
            format = "Mem {}%";
          };
          cpu = {
            interval = 5;
            format = "CPU {usage:2}%";
          };
          "custom/cpu-temp" = {
            exec = let
              cpuTempScript = pkgs.writeShellScriptBin "waybar-cpu-temp" ''
                #!${pkgs.bash}/bin/bash
                temp=$(${pkgs.lm_sensors}/bin/sensors acpitz-acpi-0 | ${pkgs.gnugrep}/bin/grep '^temp1:' | ${pkgs.gawk}/bin/awk '{print $2}' | ${pkgs.gnused}/bin/sed 's/+//;s/°C//')
                printf "%.0f" "$temp"
              '';
            in "${cpuTempScript}/bin/waybar-cpu-temp";
            critical-threshold = 80;
            format = "{} 🌡️";
            format-critical = "{} <span color=\"red\">🔥</span>";
            interval = 5;
          };
          "custom/gpu-info" = {
            exec = let
              gpuInfoScript = pkgs.writeShellScriptBin "waybar-gpu-info" ''
                #!${pkgs.bash}/bin/bash
                # Get Temperature
                temp=$(${pkgs.lm_sensors}/bin/sensors cros_ec-isa-0000 | ${pkgs.gnugrep}/bin/grep F75397_VCCGT | ${pkgs.gawk}/bin/awk '{print $2}' | ${pkgs.gnused}/bin/sed 's/+//;s/°C//')
                temp_rounded=$(printf "%.0f" "$temp")

                # Get Frequency
                freq=$(cat /sys/class/drm/card1/gt_act_freq_mhz 2>/dev/null || echo N/A)

                # Output space-separated values
                echo "GPU $temp_rounded ''${freq}MHz"
              '';
            in "${gpuInfoScript}/bin/waybar-gpu-info";
            format = "{}";
            interval = 5;
            tooltip = false;
          };
          battery = {
            states = {
              good = 95;
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-icons = [ "" "" "" "" "" ];
          };
          disk = {
            interval = 5;
            format = "Disk {percentage_used:2}%";
            path = "/";
          };
          tray = { icon-size = 16; };
        };
      };
    };
  };
}
