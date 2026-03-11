attrs@{ lib, homeManagerConfig, pkgs, ... }: {
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
      };
      
      auth = {
        "pam:enabled" = true;
        "pam:module" = "hyprlock";
        "fingerprint:enabled" = true;
        "fingerprint:ready_message" = "🔐 Touch fingerprint sensor or type password";
        "fingerprint:present_message" = "👆 Scanning fingerprint...";
      };
      
      background = [
        {
          color = "rgb(0, 43, 54)"; # Solarized dark base03
        }
      ];
      
      input-field = [
        {
          monitor = "";
          size = "200, 50";
          position = "0, -80";
          halign = "center";
          valign = "center";
          
          outline_thickness = 3;
          dots_size = 0.33;
          dots_spacing = 0.15;
          dots_center = true;
          dots_rounding = -1;
          
          outer_color = "rgb(88, 110, 117)"; # Solarized base01
          inner_color = "rgb(7, 54, 66)"; # Solarized base02
          font_color = "rgb(147, 161, 161)"; # Solarized base1
          
          fade_on_empty = true;
          fade_timeout = 1000;
          placeholder_text = "<i>Input Password...</i>";
          hide_input = false;
          
          rounding = -1;
          check_color = "rgb(181, 137, 0)"; # Solarized yellow
          fail_color = "rgb(220, 50, 47)"; # Solarized red
          fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
          capslock_color = "";
          numlock_color = "";
          bothlock_color = "";
          invert_numlock = false;
          swap_font_color = false;
        }
      ];
      
      label = [
        {
          monitor = "";
          text = "Hi there, $USER";
          color = "rgb(131, 148, 150)"; # Solarized base0 (main content)
          font_size = 25;
          font_family = "Noto Sans";
          
          position = "0, 160";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$TIME";
          color = "rgb(147, 161, 161)"; # Solarized base1 (comments/secondary)
          font_size = 55;
          font_family = "Noto Sans";
          
          position = "0, -200";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$FPRINTPROMPT";
          color = "rgb(42, 161, 152)"; # Solarized cyan for fingerprint status
          font_size = 16;
          font_family = "Noto Sans";
          
          position = "0, -40";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$FPRINTFAIL";
          color = "rgb(220, 50, 47)"; # Solarized red for fingerprint failures
          font_size = 14;
          font_family = "Noto Sans";
          
          position = "0, -10";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$FAIL";
          color = "rgb(220, 50, 47)"; # Solarized red for password failures
          font_size = 14;
          font_family = "Noto Sans";
          
          position = "0, -120";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$ATTEMPTS";
          color = "rgb(181, 137, 0)"; # Solarized yellow for attempt counter
          font_size = 12;
          font_family = "Noto Sans";
          
          position = "0, -140";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
