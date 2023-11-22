# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.policy.tetragon;
in
  with lib; {

    options.ghaf.policy.tetragon = {

      enable = lib.mkOption {
        description = "Enable tetragon policy client.";
        type = lib.types.bool;
        default = false;
      };

    };

    config = lib.mkIf cfg.enable {

      systemd.services.tetragon = {
        description = "Tetragon eBPF-based Security Observability and Runtime Enforcement";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "local-fs.target" ];
        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";
          Environment="PATH=${pkgs.tetragon}/lib/tetragon/:${pkgs.tetragon}/lib:${pkgs.tetragon}/bin";
          ExecStart = "${pkgs.tetragon}/bin/tetragon";
          StartLimitBurst = 10;
          StartLimitIntervalSec = 120;
        };
      };

      environment.etc = {
        tetragon.source = "${pkgs.tetragon}/lib/tetragon/";
      };

      # networking = {
      #   firewall.allowedTCPPorts = [ 123 ];
      # };

    };

}
