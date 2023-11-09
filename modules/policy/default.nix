# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.policy;
in
  with lib; {

    options.ghaf.policy = {

      enable = lib.mkOption {
        description = "Enable OPA policy network.";
        type = lib.types.bool;
        default = true;
      };

    };

    config = lib.mkIf cfg.enable {

      systemd.services.opa-server = {
        description = "Ghaf OPA server.";
        wantedBy = [ "default.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.opa-server}/bin/opa run -s";
          PrivateUsers = true;
          DynamicUser = true;
        };
      };

      systemd.services.opa-iptable-client = {
        description = "Ghaf OPA IP table client.";
        wantedBy = [ "default.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.opa-iptable-client}/bin/opa-iptables -opa-endpoint http://192.168.101.5:8181";
          Environment  = "PATH=$PATH:/run/current-system/sw/bin/";
        };
      };

      environment.systemPackages = with pkgs; [ checksec ];

    };

}
