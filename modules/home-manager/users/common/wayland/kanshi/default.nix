attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }: {
  services.kanshi = {
    enable = true;
    profiles = {
      default = {
        outputs = [{
          criteria = "eDP-1";
          status = "enable";
          scale = 1.5;
          position = "0,0";
          mode = "2256x1504@59.999Hz";
        }];
      };
      docked = {
        outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "LG Electronics LG ULTRAFINE 110NTZN4L965";
            status = "enable";
            scale = 2.0;
            position = "0,0";
            mode = "3840x2160@59.996Hz";
          }
          {
            criteria = "LG Electronics LG ULTRAFINE 110NTMX4M035";
            status = "enable";
            scale = 2.0;
            position = "1920,0";
            mode = "3840x2160@59.996Hz";
          }
        ];
      };
      docked-downstairs = {
        outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
            scale = 1.5;
            position = "1920,0";
            mode = "2256x1504@59.999Hz";
          }
          {
            criteria = "LG Electronics LG Ultra HD 0x0000E0D7";
            status = "enable";
            scale = 2.0;
            position = "0,0";
            mode = "3840x2160@60Hz";
          }
        ];
      };
      avr = {
        outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
            scale = 1.5;
            position = "1920,0";
            mode = "2256x1504@59.999Hz";
          }
          {
            criteria = "Sony LG TV SSCR2 0x00000101";
            status = "enable";
            scale = 1.0;
            position = "0,0";
            mode = "1920x1080@60Hz";
          }
        ];
      };
    };
  };
}
