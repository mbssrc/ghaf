# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Host-side channel configuration
#
# Builds channel definitions from enabled VMs and feature flags, then passes
# them to shared-directories for implementation. Also configures ClamAV when
# untrusted channels are present.
#
# Key responsibilities:
#   - Enumerate enabled VMs (sysvms + appvms)
#   - Build participant lists for each channel type
#   - Pass channel definitions to ghaf.storage.shared-directories
#
{
  config,
  options,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mapAttrs'
    optionalAttrs
    attrNames
    filterAttrs
    nameValuePair
    ;

  cfg = config.ghaf.storage.channels;
  globalConfig = config.ghaf.global-config;
  clamavEnabled = globalConfig.security.clamav.enable or false;

  # Environment detection
  isHost = options.ghaf.virtualization ? microvm-host;
  inherit (config.networking) hostName;

  # Import builders
  builders = import ./builders.nix { inherit lib; };

  # Enabled VM sets for building participant lists
  enabledSysvmSet = filterAttrs (_: v: v) {
    admin-vm = config.ghaf.virtualization.microvm.adminvm.enable or false;
    gui-vm = config.ghaf.virtualization.microvm.guivm.enable or false;
    net-vm = config.ghaf.virtualization.microvm.netvm.enable or false;
    audio-vm = config.ghaf.virtualization.microvm.audiovm.enable or false;
  };
  enabledAppvms = config.ghaf.virtualization.microvm.appvm.enabledVms or { };
  enabledAppvmSet = mapAttrs' (name: _: nameValuePair "${name}-vm" true) enabledAppvms;

  # Graphics target - where the desktop runs
  desktopOnHost = config.ghaf.profiles.graphics.enable or false;
  graphicsTarget =
    if desktopOnHost then
      hostName
    else if enabledSysvmSet ? gui-vm then
      "gui-vm"
    else
      null;
  hasGraphicsTarget = graphicsTarget != null;

  # Filter appvms by feature flags
  xdgAppvms = builders.filterXdgAppvms enabledAppvms;
  desktopShareAppvms = builders.filterDesktopShareAppvms enabledAppvms;

  # All enabled VMs (sysvms + appvms)
  allEnabledVms = enabledSysvmSet // enabledAppvmSet;

  # Channel definitions
  xdgChannel = builders.mkXdgChannel {
    writers = xdgAppvms;
    inherit graphicsTarget;
    inherit (cfg.xdg) mountPoint;
  };

  identityChannel = builders.mkIdentityChannel {
    writer = hostName;
    readers = attrNames allEnabledVms;
    inherit (cfg.ghafIdentity) mountPoint;
  };

  publicKeysChannel = builders.mkPublicKeysChannel {
    rwParticipant = "admin-vm";
    woParticipants = {
      ${hostName} = true;
    }
    // lib.removeAttrs enabledSysvmSet [ "admin-vm" ]
    // enabledAppvmSet;
    inherit (cfg.ghafPublicKeys) mountPoint;
  };

  desktopShareChannels = mapAttrs' (name: _: {
    name = "gui-${name}-share";
    value = builders.mkDesktopShareChannel {
      appvmName = name;
      inherit graphicsTarget;
      inherit (cfg.desktopShares) guiMountPoint appvmMountPoint;
    };
  }) desktopShareAppvms;

  # Combined channels
  channels =
    optionalAttrs (cfg.xdg.enable && (xdgAppvms != { } || hasGraphicsTarget)) { xdg = xdgChannel; }
    // optionalAttrs cfg.ghafIdentity.enable { ghaf-identity = identityChannel; }
    // optionalAttrs cfg.ghafPublicKeys.enable { ghaf-keys = publicKeysChannel; }
    // optionalAttrs (
      cfg.desktopShares.enable && hasGraphicsTarget && desktopShareAppvms != { }
    ) desktopShareChannels
    // optionalAttrs (cfg.extraChannels != { }) cfg.extraChannels;

  hasAnyUntrustedChannels = lib.any (ch: ch.mode == "untrusted") (lib.attrValues channels);
in
{
  config = mkIf (cfg.enable && isHost) {
    assertions = [
      {
        assertion = hasAnyUntrustedChannels -> clamavEnabled;
        message = "Untrusted channels require ClamAV. Set ghaf.global-config.security.clamav.enable = true or remove untrusted channels.";
      }
    ];

    ghaf.storage.shared-directories = {
      inherit (cfg) enable debug;
      inherit channels;
      scanner.enable = hasAnyUntrustedChannels;
    };

    ghaf.security.clamav = mkIf (clamavEnabled && hasAnyUntrustedChannels) {
      enable = true;
      daemon.enable = true;
      proxy.enable = true;
      database.updater.enable = true;
      database.fangfrisch.enable = true;
    };
  };
}
