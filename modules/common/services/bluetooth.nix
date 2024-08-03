# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.services.bluetooth;
  inherit (lib) mkIf mkEnableOption;
in {
  options.ghaf.services.bluetooth = {
    enable = mkEnableOption "Bluetooth configurations";
  };
  config = mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      # package = pkgs.pulseaudioFull;
      settings.General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };

    hardware.pulseaudio.extraConfig = ''
      load-module module-switch-on-connect
      load-module module-bluetooth-policy
      load-module module-bluetooth-discover
    '';

    # UI applications
    # services.blueman.enable = true;

    # systemd.tmpfiles.rules = [
    #   "f /var/lib/systemd/linger/${config.ghaf.users.accounts.user}"
    # ];
    # Media button support
    # systemd.user.services.mpris-proxy = {
    #   description = "Mpris proxy";
    #   after = [ "network.target" "sound.target" ];
    #   wantedBy = [ "default.target" ];
    #   serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
    # };
  };
}



