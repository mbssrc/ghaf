# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which configures sd-image to generate images to be used with NVIDIA
# Jetson Thor AGX devices. Supposed to be imported from format-module.nix.
#
# Generates ESP partition contents mimicking systemd-boot installation. Can be
# used to generate both images to be used in flashing script, and image to be
# flashed to external disk. NVIDIA's edk2 does not seem to care to much about
# the partition types, as long as there is a FAT partition, which contains
# EFI-directory and proper kind of structure, it finds the EFI-applications and
# boots them successfully.
#
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}:
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];

  boot.loader.grub.enable = false;
  hardware.enableAllHardware = lib.mkForce false;

  sdImage =
    let
      # Reuse the mk-esp-contents.py script from Orin
      mkESPContentSource = pkgs.replaceVars ../nvidia-jetson-orin/mk-esp-contents.py {
        inherit (pkgs.buildPackages) python3;
      };
      mkESPContent =
        pkgs.runCommand "mk-esp-contents"
          {
            nativeBuildInputs = with pkgs; [
              mypy
              python3
            ];
          }
          ''
            install -m755 ${mkESPContentSource} $out
            mypy \
              --no-implicit-optional \
              --disallow-untyped-calls \
              --disallow-untyped-defs \
              $out
          '';
      # fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
    in
    {
      firmwareSize = 256;
      populateFirmwareCommands = ''
        mkdir -pv firmware
        ${mkESPContent} \
          --toplevel ${config.system.build.toplevel} \
          --output firmware/ \
          # --device-tree $#{fdtPath}
      '';
      populateRootCommands = "";
      postBuildCommands = ''
        # Add padding at end for GPT secondary partition table (34 sectors = 17 KiB)
        ${pkgs.buildPackages.coreutils}/bin/truncate -s +1M "$img"

        # Convert MBR to GPT (required for Thor UEFI boot)
        ${pkgs.buildPackages.gptfdisk}/bin/sgdisk -g "$img"

        # Set ESP partition type to EFI System Partition
        ${pkgs.buildPackages.gptfdisk}/bin/sgdisk -t 1:EF00 "$img"
      '';
    };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
    fsType = "vfat";
  };
}
