# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.givc.guivm;
  inherit (lib) mkOption mkIf types;
  hostName = "gui-vm";
  guivmEntry = builtins.filter (x: x.name == hostName) config.ghaf.networking.hosts.entries;
  addr = lib.head (builtins.map (x: x.ip) guivmEntry);
in {
  options.ghaf.givc.guivm = {
    enable = mkOption {
      description = "Enable guivm givc module.";
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable {
    # Configure guivm service
    givc.sysvm = {
      enable = true;
      name = hostName;
      inherit addr;
      port = "9000";
      services = [
        "poweroff.target"
        "reboot.target"
      ];
      tls = {
        enable = config.ghaf.givc.enableTls;
        caCertPath = "/run/givc/ca-cert.pem";
        certPath = "/run/givc/${hostName}-cert.pem";
        keyPath = "/run/givc/${hostName}-key.pem";
      };
      admin = config.ghaf.givc.adminConfig;
    };

    # Copy TLS files and change permissions
    systemd.services."givc-prep-${config.ghaf.users.accounts.user}".enable = lib.mkForce config.ghaf.givc.enableTls;
  };
}
