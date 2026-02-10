# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Device-side NVMe USB gadget configuration for Thor flashing.
#
# This module configures the flashInitrd to expose Thor's NVMe as USB mass
# storage after QSPI flash completes, allowing the host to write the rootfs.
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.thor;

  # Device-side NVMe USB mass storage script (runs in flashInitrd on Thor)
  nvmeGadgetScript = ''
    echo "============================================================"
    echo "Thor NVMe Flash via USB Mass Storage"
    echo ""

    # Load required modules (after QSPI flash to avoid interference)
    echo "Loading PCIe, NVMe and USB modules..."
    modprobe phy_tegra194_p2u || echo "WARN: phy_tegra194_p2u module load failed"
    modprobe pcie-tegra264 || echo "WARN: pcie-tegra264 module load failed"

    sleep 2  # Give PCIe time to enumerate

    modprobe nvme_core || echo "WARN: nvme_core module load failed"
    modprobe nvme || echo "WARN: nvme module load failed"
    modprobe usb_f_mass_storage || echo "WARN: usb_f_mass_storage module load failed"
    modprobe vfat || echo "WARN: vfat module load failed"

    echo "Loaded modules:"
    lsmod | grep -E "pcie|tegra|nvme|usb_f|vfat" || echo "  (none matching)"

    echo "Block devices:"
    ls -la /dev/nvme* /dev/sd* /dev/mmcblk* 2>/dev/null || echo "  (no block devices found)"

    # Wait for Thor's NVMe device
    SECONDS=0
    TIMEOUT=30
    echo "Waiting for NVMe device (timeout: $TIMEOUT seconds)..."
    while [ ! -b /dev/nvme0n1 ] && [ $SECONDS -lt $TIMEOUT ]; do
      sleep 1
      [ $((SECONDS % 10)) -eq 0 ] && echo "  ...''${SECONDS}s"
    done

    if [ ! -b /dev/nvme0n1 ]; then
      echo "ERROR: NVMe device /dev/nvme0n1 not found after ''${SECONDS}s"
      echo "Final block devices:"
      ls -la /dev/nvme* /dev/sd* /dev/mmcblk* 2>/dev/null || echo "  (none)"
      exit 1
    fi

    nvme_size=$(( $(cat /sys/block/nvme0n1/size) * 512 ))
    echo "NVMe device found: /dev/nvme0n1 ($nvme_size bytes)"

    # Configuring USB gadget
    gadget=/sys/kernel/config/usb_gadget/g.1
    if [ ! -d "$gadget" ]; then
      echo "ERROR: USB gadget not configured"
      exit 1
    fi

    echo "Exposing NVMe as USB mass storage..."
    udc=$(cat "$gadget/UDC" 2>/dev/null || true)
    [ -n "$udc" ] && echo "" > "$gadget/UDC"

    # Set identifiable gadget strings for auto-detection
    echo "GHAF-THOR-NVME" > "$gadget/strings/0x409/serialnumber"

    mkdir -p "$gadget/functions/mass_storage.0"
    echo 1 > "$gadget/functions/mass_storage.0/stall"
    echo 0 > "$gadget/functions/mass_storage.0/lun.0/cdrom"
    echo 0 > "$gadget/functions/mass_storage.0/lun.0/ro"
    echo 1 > "$gadget/functions/mass_storage.0/lun.0/removable"
    echo 0 > "$gadget/functions/mass_storage.0/lun.0/nofua"
    echo "/dev/nvme0n1" > "$gadget/functions/mass_storage.0/lun.0/file"

    ln -sf "$gadget/functions/mass_storage.0" "$gadget/configs/c.1/"
    if [ -n "$udc" ]; then
      echo "$udc" > "$gadget/UDC"
    else
      echo "$(ls /sys/class/udc | head -n 1)" > "$gadget/UDC"
    fi

    sleep 2

    echo ""
    echo "NVMe exposed. Waiting for host to write images..."
    echo ""

    # Wait for completion marker on ESP
    SECONDS=0
    TIMEOUT=600
    echo "Waiting for host to complete flash (timeout: $TIMEOUT seconds)..."
    while [ $SECONDS -lt $TIMEOUT ]; do
      sleep 5

      # Check if ESP partition exists
      if [ -b /dev/nvme0n1p1 ]; then
        # Try to mount and check for marker
        mkdir -p /mnt/esp
        if mount -t vfat /dev/nvme0n1p1 /mnt/esp 2>/dev/null; then
          while [ $SECONDS -lt $TIMEOUT ]; do
            if [ -f /mnt/esp/.flash_complete ]; then
              echo "Host completed NVMe flash!"
              rm -f /mnt/esp/.flash_complete
              umount /mnt/esp
              break 2
            fi
            sleep 5
          done
          umount /mnt/esp
        fi
      else
        printf "."
      fi
    done

    # Timeout info
    [ $SECONDS -ge $TIMEOUT ] && echo "WARNING: Timeout waiting for host"

    # Cleanup (not strictly necessary)
    echo "" > "$gadget/UDC"
    rm -f "$gadget/configs/c.1/mass_storage.0"
    rmdir "$gadget/functions/mass_storage.0" 2>/dev/null || true
    echo "$(ls /sys/class/udc | head -n 1)" > "$gadget/UDC"

    sync
    echo "NVMe flash completed"
    echo "============================================================"
  '';
in
{
  config = lib.mkIf cfg.enable {

    # Add NVMe/USB modules to flash initrd
    hardware.nvidia-jetpack.flashScriptOverrides.additionalInitrdFlashModules = [
      # PCIe controller
      "pcie-tegra264"
      "phy_tegra194_p2u"
      # NVMe driver
      "nvme_core"
      "nvme"
      # USB mass storage gadget
      "usb_f_mass_storage"
      # FAT filesystem for ESP marker
      "vfat"
    ];

    # Append post QSPI flash commands
    hardware.nvidia-jetpack.flashScriptOverrides.postFlashDeviceCommands = nvmeGadgetScript;
  };
}
