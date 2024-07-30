# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.services.firmware;
  inherit (lib) mkIf mkEnableOption;
in {
  options.ghaf.services.firmware = {
    enable = mkEnableOption "PLaceholder for firmware handling";
    graphics = mkEnableOption "Enable graphics firmware";
  };
  config = mkIf cfg.enable {
    hardware = {
      enableRedistributableFirmware = true;
      enableAllFirmware = true;
    };
    hardware.graphics = mkIf cfg.graphics {
      enable = true;
      extraPackages = [
        pkgs.intel-media-sdk
        pkgs.intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
      ];
    };
    environment.sessionVariables = mkIf cfg.graphics {LIBVA_DRIVER_NAME = "iHD";};
  };
}
