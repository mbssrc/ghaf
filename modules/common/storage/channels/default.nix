# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Storage channels - high-level inter-VM file-sharing API
#
# This module provides the user-facing configuration for data channels between VMs.
# It provides builtin channels (XDG, identity, public keys, desktop shares) that can
# be enabled via feature flags. These are translated into channel definitions, and,
# together with additional channel definitions, implemented by the shared-directories
# module.
#
# Architecture:
#   channels/ (this)     -> Defines WHAT data flows (participants, mount points)
#   shared-directories/  -> Implements HOW it flows (virtiofs, scanning, mounts)
#
{
  config,
  lib,
  ...
}@args:
let
  inherit (lib) mkDefault;

  # Use specialArgs globalConfig if available (VMs), otherwise config path (host)
  effectiveGlobalConfig = args.globalConfig or (config.ghaf.global-config or { });
  globalChannelsCfg = effectiveGlobalConfig.storage.channels or { };

  # App user for mount path default
  appUser = config.ghaf.users.appUser.name or "appuser";
in
{
  _file = ./default.nix;

  imports = [
    ./options.nix
    ./host.nix
    ./vm.nix
  ];

  # Set defaults from global-config
  config.ghaf.storage.channels = {
    enable = mkDefault (globalChannelsCfg.enable or false);
    debug = mkDefault (globalChannelsCfg.debug or false);
    xdg.enable = mkDefault (globalChannelsCfg.xdg.enable or false);
    ghafIdentity.enable = mkDefault (globalChannelsCfg.ghafIdentity.enable or false);
    ghafPublicKeys.enable = mkDefault (globalChannelsCfg.ghafPublicKeys.enable or false);
    desktopShares = {
      enable = mkDefault (globalChannelsCfg.desktopShares.enable or false);
      appvmMountPoint = mkDefault "/home/${appUser}";
    };
    extraChannels = mkDefault (globalChannelsCfg.extraChannels or { });
  };
}
