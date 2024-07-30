# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Kernel Configuration Definitions
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types optionalAttrs;
  inherit (builtins) concatStringsSep filter map hasAttr;

  # Only x86 targets with hw definition supported at the moment
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization = isx86 && (hasAttr "hardware" config.ghaf);

  # Intel SR-IOV module
  i915 = pkgs.callPackage ../../../packages/sr-iov/default.nix {
    inherit (pkgs) lib stdenv fetchFromGitHub writeShellScriptBin;
    inherit (config.boot.kernelPackages) kernel;
  };

  i915-sriov-host-params = [
    "i915.enable_guc=3"
    "i915.max_vfs=7"
  ];
  i915-sriov-guest-params = [
    "intel_iommu=on"
    "i915.enable_guc=3"
    "i915.max_vfs=7"
  ];
in {
  options.ghaf.kernel = {
    host = mkOption {
      type = types.attrs;
      default = {};
      description = "Host kernel configuration";
    };
    guivm = mkOption {
      type = types.attrs;
      default = {};
      description = "GuiVM kernel configuration";
    };
    audiovm = mkOption {
      type = types.attrs;
      default = {};
      description = "AudioVM kernel configuration";
    };
  };

  config = {
    systemd.services."split-sriov" = {
      requiredBy = ["sysinit.target"];
      after = ["systemd-udevd.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "+${pkgs.writeShellScript "extend-sriov" ''
            echo 1 > /sys/bus/pci/devices/0000:00:02.0/sriov_drivers_autoprobe
            echo 2 > /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
          ''}"
        ];
      };
    };

    # Host kernel configuration
    boot = optionalAttrs fullVirtualization {
      initrd = {
        # availableKernelModules = [ "i915" ];
        # kernelModules = config.ghaf.hardware.definition.host.kernelConfig.stage1.kernelModules ++ [ "i915" ];
        inherit (config.ghaf.hardware.definition.host.kernelConfig.stage1) kernelModules;
      };
      extraModulePackages = [i915];
      # inherit (config.ghaf.hardware.definition.host.kernelConfig.stage2) kernelModules;
      kernelModules = config.ghaf.hardware.definition.host.kernelConfig.stage2.kernelModules ++ ["i915"];
      kernelPackages = pkgs.linuxPackages_latest;
      kernelPatches = lib.singleton {
        name = "i915-sriov";
        patch = null;
        extraStructuredConfig = {
          INTEL_MEI_PXP = lib.kernel.module;
          DRM_I915_PXP = lib.kernel.yes;
        };
      };
      kernelParams = let
        # PCI device passthroughs for vfio
        filterDevices = filter (d: d.vendorId != null && d.productId != null);
        mapPciIdsToString = map (d: "${d.vendorId}:${d.productId}");
        vfioPciIds = mapPciIdsToString (filterDevices (
          config.ghaf.hardware.definition.network.pciDevices
          ++ config.ghaf.hardware.definition.gpu.pciDevices
          ++ config.ghaf.hardware.definition.audio.pciDevices
        ));
      in
        config.ghaf.hardware.definition.host.kernelConfig.kernelParams
        ++ ["vfio-pci.ids=${concatStringsSep "," vfioPciIds}"]
        ++ i915-sriov-host-params;
    };

    # Guest kernel configurations
    ghaf.kernel = optionalAttrs fullVirtualization {
      guivm = {
        boot = {
          initrd = {
            availableKernelModules = ["i915"];
            kernelModules = config.ghaf.hardware.definition.gpu.kernelConfig.stage1.kernelModules ++ ["i915"];
            # inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage1) kernelModules;
          };
          extraModulePackages = [i915];
          inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage2) kernelModules;
          # inherit (config.ghaf.hardware.definition.gpu.kernelConfig) kernelParams;
          kernelParams = config.ghaf.hardware.definition.gpu.kernelConfig.kernelParams ++ i915-sriov-guest-params;
          kernelPackages = pkgs.linuxPackages_latest;
          kernelPatches = lib.singleton {
            name = "i915-sriov";
            patch = null;
            extraStructuredConfig = {
              INTEL_MEI_PXP = lib.kernel.module;
              DRM_I915_PXP = lib.kernel.yes;
            };
          };
        };
      };
      audiovm = {
        boot = {
          initrd = {
            inherit (config.ghaf.hardware.definition.audio.kernelConfig.stage1) kernelModules;
          };
          inherit (config.ghaf.hardware.definition.audio.kernelConfig.stage2) kernelModules;
          inherit (config.ghaf.hardware.definition.audio.kernelConfig) kernelParams;
        };
      };
    };
  };
}
