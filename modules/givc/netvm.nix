# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  givc,
  ...
}: let
  cfg = config.ghaf.givc.netvm;
in
with lib; {

    options.ghaf.givc.netvm = {
      enable = mkOption {
        description = "Enable netvm givc module.";
        type = types.bool;
        default = true;
      };
    };

    config = lib.mkIf cfg.enable {
      givc.sysvm = {
        enable = true;
        name = "net-vm";
        addr = "192.168.101.1";
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