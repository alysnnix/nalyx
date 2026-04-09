{ vars, ... }:
{
  programs.caelestia = {
    enable = true;

    cli = {
      enable = true;
    };

    settings = {
      # --- Enabled modules ---
      bar = {
        # Use defaults for workspaces, clock, volume, network, CPU/RAM, tray
      };

      launcher = {
        # App search with autocomplete
        enableDangerousActions = false;
      };

      notifs = {
        # Default notification behavior
      };

      osd = {
        enabled = true;
        enableBrightness = true;
        enableMicrophone = true;
      };

      lock = {
        # Lock screen with default config
      };

      # --- Disabled modules (minimalism) ---
      dashboard.enabled = false;
      sidebar.enabled = false;
      session.enabled = false;
      utilities.enabled = false;

      # Disable audio visualizer
      background.visualiser.enabled = false;

      # --- Security hardening ---
      services = {
        # S-W2: No IP geolocation -- use explicit coordinates
        weather.location = vars.weather.location;

        # S-W1/S-W3: No lyrics (external network calls)
        showLyrics = false;
      };
    };
  };
}
