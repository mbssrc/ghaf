# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.givc.guivm;
in
  with lib; {

    options.ghaf.givc.guivm = {
      enable = mkOption {
        description = "Enable guivm givc module.";
        type = types.bool;
        default = true;
      };
    };

    config = mkIf cfg.enable {

      givc.admin = {
        enable = true;
        addr = config.ghaf.givc.adminConfig.addr;
        port = config.ghaf.givc.adminConfig.port;
        protocol = config.ghaf.givc.adminConfig.protocol;
        services = [
          "givc-host.service"
          "givc-net-vm.service"
          "givc-gui-vm.service"
        ];
        tls.enable = false;
        # tls = {
        #   ca-cert-path = "my/ca/cert/path";
        #   cert-path = "my/cert/path";
        #   key-path = "my/key/path";
        # };
      };
      givc.sysvm = {
        enable = true;
        name = "gui-vm";
        addr = "192.168.101.3";
        port = "9000";
        services = [
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


