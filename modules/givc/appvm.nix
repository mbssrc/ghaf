# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  givc,
  ...
}: let
  cfg = config.ghaf.givc.appvm;
in
  with lib; {

    options.ghaf.givc.appvm = {
      enable = mkEnableOption "Enable appvm givc module.";
      name = mkOption {
        type = types.str;
        default = "appvm";
        description = "Name of the appvm.";
      };
      applications = mkOption {
        type = types.str;
        default = "{}";
        description = "Applications to run in the appvm.";
      };
    };

    config = mkIf cfg.enable {
      givc.appvm = {
        enable = true;
        name = cfg.name;
        applications = cfg.applications;
        addr = "dynamic";
        port = "9000";
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
