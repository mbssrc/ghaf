# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) hasAttr optionals;
  xdgPdfPort = 1200;

  # Intel SR-IOV module
  i915 = pkgs.callPackage ../../../packages/sr-iov/default.nix {
    inherit (pkgs) lib stdenv fetchFromGitHub writeShellScriptBin;
    inherit (config.boot.kernelPackages) kernel;
  };
  i915-sriov-guest-params = [
    "intel_iommu=on"
    "i915.enable_guc=3"
    "i915.max_vfs=7"
  ];
in {
  name = "chromium";
  packages = let
    # PDF XDG handler is executed when the user opens a PDF file in the browser
    # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
    xdgPdfItem = pkgs.makeDesktopItem {
      name = "ghaf-pdf";
      desktopName = "Ghaf PDF handler";
      exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
      mimeTypes = ["application/pdf"];
    };
    xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
      filepath=$(realpath "$1")
      echo "Opening $filepath" | systemd-cat -p info
      echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm ${toString xdgPdfPort}
    '';
  in [
    pkgs.chromium
    pkgs.pulseaudio
    pkgs.xdg-utils
    xdgPdfItem
    xdgOpenPdf
    pkgs.intel-gpu-tools
  ];
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:05:01";
  ramMb = 3072;
  cores = 4;
  extraModules = [
    {
      imports = [../programs/chromium.nix];
      # Enable pulseaudio for Chromium VM
      security.rtkit.enable = true;
      sound.enable = true;
      users.extraUsers.ghaf.extraGroups = ["audio" "video"];

      hardware.pulseaudio = {
        enable = true;
        extraConfig = ''
          load-module module-tunnel-sink sink_name=chromium-speaker server=audio-vm:4713 format=s16le channels=2 rate=48000
          load-module module-tunnel-source source_name=chromium-mic server=audio-vm:4713 format=s16le channels=1 rate=48000

          # Set sink and source default max volume to about 90% (0-65536)
          set-sink-volume chromium-speaker 60000
          set-source-volume chromium-mic 60000
        '';
      };

      time.timeZone = config.time.timeZone;

      microvm.qemu.extraArgs =
        optionals (config.ghaf.hardware.usb.internal.enable
          && (hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs))
        config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;

      ghaf.reference.programs.chromium.enable = true;

      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";

      boot = {
        initrd = {
          availableKernelModules = ["i915"];
          kernelModules = ["i915"];
        };
        extraModulePackages = [i915];
        kernelParams = ["earlykms"] ++ i915-sriov-guest-params;
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
      hardware.graphics = {
        enable = true;
        extraPackages = [
          pkgs.intel-media-sdk
          pkgs.intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
        ];
      };
      environment.sessionVariables = {LIBVA_DRIVER_NAME = "iHD";};
      microvm.devices = builtins.map (d: {
          bus = "pci";
          inherit (d) path;
        })
        [
          {
            # Passthrough Intel Iris GPU
            path = "0000:00:02.2";
            vendorId = "8086";
            productId = "a7a1";
          }
        ];
    }
  ];
  borderColor = "#630505";
  vtpm.enable = true;
}
