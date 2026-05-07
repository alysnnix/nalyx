{ pkgs, ... }:
let
  # 45C thermal ceiling for quiet battery operation. Thermald reads
  # x86_pkg_temp and throttles via RAPL whenever the package crosses
  # the trip point.
  thermalQuietConfig = pkgs.writeText "thermal-conf-quiet.xml" ''
    <?xml version="1.0"?>
    <ThermalConfiguration>
      <Platform>
        <Name>nalyx-quiet-battery</Name>
        <ProductName>*</ProductName>
        <Preference>QUIET</Preference>
        <ThermalZones>
          <ThermalZone>
            <Type>x86_pkg_temp</Type>
            <TripPoints>
              <TripPoint>
                <SensorType>x86_pkg_temp</SensorType>
                <Temperature>45000</Temperature>
                <type>passive</type>
                <ControlType>SEQUENTIAL</ControlType>
                <CoolingDevice>
                  <index>1</index>
                  <type>rapl_controller</type>
                  <influence>100</influence>
                  <SamplingPeriod>4</SamplingPeriod>
                </CoolingDevice>
              </TripPoint>
            </TripPoints>
          </ThermalZone>
        </ThermalZones>
      </Platform>
    </ThermalConfiguration>
  '';

  thermalQuietCli = pkgs.writeShellScriptBin "thermal-quiet" ''
    case "''${1:-status}" in
      on)
        sudo systemctl unmask thermal-quiet.service
        sudo systemctl start thermal-quiet.service
        echo "thermal-quiet enabled (auto-engages on battery)"
        ;;
      off)
        sudo systemctl mask thermal-quiet.service
        sudo systemctl stop thermal-quiet.service 2>/dev/null || true
        echo "thermal-quiet disabled"
        ;;
      status)
        if systemctl is-masked --quiet thermal-quiet.service; then
          echo "disabled (masked)"
        elif systemctl is-active --quiet thermal-quiet.service; then
          echo "active (45C ceiling)"
        else
          echo "inactive (waiting for battery)"
        fi
        ;;
      *)
        echo "usage: thermal-quiet on|off|status" >&2
        exit 1
        ;;
    esac
  '';
in
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  environment.sessionVariables = {
    # Force Intel Iris Xe to use the correct Mesa driver
    MESA_LOADER_DRIVER_OVERRIDE = "iris";
    # Persistent shader cache for Mesa and Qt (reduces first-render stutter)
    MESA_SHADER_CACHE_DIR = "$HOME/.cache/mesa_shader_cache";
    MESA_SHADER_CACHE_MAX_SIZE = "1G";
    QSG_SHADER_CACHE_DIR = "$HOME/.cache/qt_shader_cache";
  };

  # Default thermald acts as a high-temp safety net (~90C trip)
  services.thermald.enable = true;

  # Aggressive 45C ceiling, battery-only, toggleable via `thermal-quiet on|off`
  systemd.services.thermal-quiet = {
    description = "Aggressive 45C thermal ceiling for battery use";
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      ConditionACPower = false;
      Conflicts = "thermald.service";
    };

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.thermald}/bin/thermald --no-daemon --config-file ${thermalQuietConfig} --ignore-cpuid-check";
      ExecStopPost = "-${pkgs.systemd}/bin/systemctl start thermald.service";
      Restart = "on-failure";
    };
  };

  # React to AC plug/unplug at runtime so the service flips automatically.
  # ConditionACPower is only evaluated at unit start, so udev triggers the swap.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="${pkgs.systemd}/bin/systemctl --no-block start thermal-quiet.service"
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block stop thermal-quiet.service"
  '';

  environment.systemPackages = [ thermalQuietCli ];
}
