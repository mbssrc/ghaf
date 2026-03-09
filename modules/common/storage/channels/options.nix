# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Channel options definitions
#
{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.ghaf.storage.channels = {
    enable = mkEnableOption "shared directory channels";

    debug = mkEnableOption "debug logging for shared directory channels";

    ghafIdentity = {
      enable = mkEnableOption "host identity data shared to VMs (/persist/identity -> /etc/identity)";
      mountPoint = mkOption {
        type = types.path;
        default = "/etc/identity";
        description = "Mount point for identity shares.";
        readOnly = true;
      };
    };

    ghafPublicKeys = {
      enable = mkEnableOption "public key publish channel with rw access for admin-vm (wo for others)";
      mountPoint = mkOption {
        type = types.path;
        default = "/etc/ghaf-keys";
        description = "Mount point for ghaf public keys.";
        readOnly = true;
      };
    };

    desktopShares = {
      enable = mkEnableOption "GUI-VM <-> App-VM shares (auto-generated from appvm desktopShare config)";
      guiMountPoint = mkOption {
        type = types.path;
        default = "/Shares";
        description = "Mount point for desktop shares on GUI-VM side.";
      };
      appvmMountPoint = mkOption {
        type = types.path;
        defaultText = lib.literalExpression ''"/home/''${config.ghaf.users.appUser.name}/Desktop Share"'';
        description = "Mount point for desktop shares on AppVM side. Defaults to user home for file manager visibility.";
      };
    };

    xdg = {
      enable = mkEnableOption "XDG shares (auto-generated from appvm xdgitems/xdghandlers config)";
      mountPoint = mkOption {
        type = types.path;
        default = "/run/xdg";
        description = "Mount point for XDG shares.";
        readOnly = true;
      };
    };

    extraChannels = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional custom channel definitions";
    };
  };
}
