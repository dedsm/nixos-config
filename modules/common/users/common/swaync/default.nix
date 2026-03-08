{ lib, homeManagerConfig, ... }:
with lib;
mkIf (homeManagerConfig.swaync.enable or false) {
  services.swaync = {
    enable = true;
    
    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      notification-window-width = 350;
      control-center-width = 380;
      control-center-height = 500;
      timeout = 10;
      timeout-low = 5;
      timeout-critical = 0;
      keyboard-shortcuts = true;
      notification-grouping = true;
      image-visibility = "when-available";
      notification-2fa-action = true;
      notification-inline-replies = true;
      hide-on-clear = false;
      hide-on-action = true;
      widgets = [
        "inhibitors"
        "title"
        "dnd"
        "mpris"
        "buttons-grid"
        "volume"
        "notifications"
      ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear";
        };
        dnd = {
          text = "Do Not Disturb";
        };
        mpris = {
          show-album-art = "always";
          autohide = false;
        };
        buttons-grid = {
          buttons-per-row = 3;
          actions = [
            {
              label = "WiFi";
              type = "toggle";
              active = true;
              command = "sh -c '[[ $SWAYNC_TOGGLE_STATE == true ]] && nmcli radio wifi on || nmcli radio wifi off'";
              update-command = "sh -c '[[ $(nmcli radio wifi) == \"enabled\" ]] && echo true || echo false'";
            }
            {
              label = "Bluetooth";
              command = "blueman-manager";
            }
          ];
        };
        volume = {
          label = "Volume";
          show-per-app = true;
          show-per-app-icon = true;
          show-per-app-label = false;
          expand-button-label = "⇧";
          collapse-button-label = "⇩";
        };
      };
    };

    style = ''
      /* Global sizing */
      * {
        font-size: 14px;
      }

      /* Base notification styling */
      .notification {
        background: rgba(30, 30, 46, 0.95);
        border: 2px solid rgba(137, 180, 250, 0.5);
        border-radius: 12px;
        margin: 8px;
        padding: 0;
      }

      .notification-default-action:hover {
        background: rgba(137, 180, 250, 0.1);
      }

      /* Urgent notifications */
      .critical {
        border: 2px solid rgba(243, 139, 168, 1);
        background: rgba(243, 139, 168, 0.2);
      }

      /* Control center styling */
      .control-center {
        background: rgba(30, 30, 46, 0.98);
        border: 2px solid rgba(137, 180, 250, 0.3);
        border-radius: 10px;
        margin: 8px;
        padding: 8px;
      }

      .control-center-list {
        background: transparent;
      }

      /* Widget styling */
      .widget-dnd {
        padding: 8px;
        margin: 4px;
        border-radius: 8px;
      }

      .widget-dnd > switch {
        background: rgba(137, 180, 250, 0.2);
        border-radius: 16px;
      }

      .widget-dnd > switch:checked {
        background: rgba(137, 180, 250, 1);
      }

      /* MPRIS widget */
      .widget-mpris {
        background: rgba(49, 50, 68, 0.8);
        border-radius: 8px;
        padding: 8px;
        margin: 4px;
      }

      .widget-mpris-album-art {
        border-radius: 8px;
      }

      /* Button grid */
      .widget-buttons-grid {
        padding: 8px;
      }

      .widget-buttons-grid > button {
        background: rgba(49, 50, 68, 0.6);
        border: 1px solid rgba(137, 180, 250, 0.3);
        border-radius: 8px;
        margin: 4px;
        padding: 8px 16px;
      }

      .widget-buttons-grid > button:hover {
        background: rgba(137, 180, 250, 0.2);
      }

      .widget-buttons-grid > button.toggle:checked {
        background: rgba(137, 180, 250, 0.4);
        border-color: rgba(137, 180, 250, 1);
      }

      /* Notification grouping */
      .notification-group {
        margin: 4px 0;
      }

      .notification-group-headers {
        background: rgba(49, 50, 68, 0.5);
        border-radius: 8px 8px 0 0;
        padding: 8px;
      }

      /* Volume widget */
      .widget-volume {
        padding: 8px;
      }

      .widget-volume scale {
        min-height: 4px;
      }

      /* Empty state */
      .blank-window {
        background: transparent;
      }
    '';
  };
}
