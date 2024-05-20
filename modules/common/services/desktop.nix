# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (builtins) filter map hasAttr;
  inherit (lib) mkIf mkEnableOption head any optionals optionalAttrs;
  cfg = config.ghaf.services.desktop;

  winConfig =
    if (hasAttr "reference" config.ghaf)
    then
      if (hasAttr "programs" config.ghaf.reference)
      then config.ghaf.reference.programs.windows-launcher
      else {}
    else {};
  isIdsvmEnabled = any (vm: vm == "ids-vm") config.ghaf.namespaces.vms;
  # TODO: The desktop configuration needs to be re-worked.
in {
  options.ghaf.services.desktop = {
    enable = mkEnableOption "Enable the desktop configuration";
  };

  config = mkIf cfg.enable {
    ghaf = optionalAttrs (hasAttr "graphics" config.ghaf) {
      profiles.graphics.compositor = "labwc";
      graphics = {
        launchers = let
          appStarterArgs = builtins.replaceStrings ["\n"] [" "] ''
            -host ${config.ghaf.givc.adminConfig.name}
            -ip ${config.ghaf.givc.adminConfig.addr}
            -port ${config.ghaf.givc.adminConfig.port}
            -ca /run/givc/ca-cert.pem
            -cert /run/givc/gui-vm-cert.pem
            -key /run/givc/gui-vm-key.pem
            ${lib.optionalString (!config.ghaf.givc.enableTls) "-notls"}
          '';
        in
          [
            {
              # The SPKI fingerprint is calculated like this:
              # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
              # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
              name = "Chromium";
              path =
                if isIdsvmEnabled
                then "${pkgs.givc-app}/bin/givc-app -name chromium-ids ${appStarterArgs}"
                else "${pkgs.givc-app}/bin/givc-app -name chromium ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/chromium.svg";
            }

            {
              name = "GALA";
              path = "${pkgs.givc-app}/bin/givc-app -name gala ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/distributor-logo-android.svg";
            }

            {
              name = "PDF Viewer";
              path = "${pkgs.givc-app}/bin/givc-app -name zathura ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/document-viewer.svg";
            }

            {
              name = "Element";
              path = "${pkgs.givc-app}/bin/givc-app -name element ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/element-desktop.svg";
            }

            {
              name = "AppFlowy";
              path = "${pkgs.givc-app}/bin/givc-app -name appflowy ${appStarterArgs}";
              icon = "${pkgs.appflowy}/opt/data/flutter_assets/assets/images/flowy_logo.svg";
            }

            {
              name = "Network Settings";
              path = "${pkgs.nm-launcher}/bin/nm-launcher";
              icon = "${pkgs.icon-pack}/preferences-system-network.svg";
            }

            {
              name = "Shutdown";
              path = "${pkgs.givc-app}/bin/givc-app -name poweroff ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/system-shutdown.svg";
            }

            {
              name = "Reboot";
              path = "${pkgs.givc-app}/bin/givc-app -name reboot ${appStarterArgs}";
              icon = "${pkgs.icon-pack}/system-reboot.svg";
            }
          ]
          ++ optionals (hasAttr "spice-host" winConfig) [
            {
              name = "Windows";
              path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
              icon = "${pkgs.icon-pack}/distributor-logo-windows.svg";
            }
          ];
      };
    };
  };
}
