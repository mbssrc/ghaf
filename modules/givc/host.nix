# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  givc,
  ...
}: let
  cfg = config.ghaf.givc.host;
in
  with lib; {
    options.ghaf.givc.host = {
      enable = mkEnableOption "Enable host givc module.";
    };

    config = mkIf cfg.enable {
      givc.host = {
        enable = true;
        addr = "192.168.101.2";
        port = "9000";
        services = [
          "microvm@chromium-vm.service"
          "microvm@gala-vm.service"
          "microvm@zathura-vm.service"
          "microvm@net-vm.service"
          "microvm@gui-vm.service"
          "poweroff.target"
          "reboot.target"
        ];
        tls.enable = false;
        # tls = {
        #   ca-cert-path = "my/ca/cert/path";
        #   cert-path = "my/cert/path";
        #   key-path = "my/key/path";
        # };
        admin = config.ghaf.givc.adminConfig;
      };

    };
  }



