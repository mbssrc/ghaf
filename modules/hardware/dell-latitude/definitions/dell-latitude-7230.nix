# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  name = "Dell Latitude 7230 Rugged";

  mouse = [
    "EETI8082:00 0EEF:C004 Mouse"
    "EETI8082:00 0EEF:C004"
    "SYNAPTICS Synaptics HIDUSB TouchPad V1.05 Mouse"
    "EETI8082:00 0EEF:C004 Stylus"
  ];
  touchpad = [
    "EETI8082:00 0EEF:C004 Touchpad"
    "SYNAPTICS Synaptics HIDUSB TouchPad V1.05 Touchpad"
  ];

  disks = {
    disk1.device = "/dev/nvme0n1";
  };

  network.pciDevices = [
    {
      # Passthrough Intel WiFi card
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "51f0";
      name = "wlp0s5f0";
    }
  ];

  gpu.pciDevices = [
    {
      # Passthrough Intel Iris GPU
      path = "0000:00:02.0";
      vendorId = "8086";
      productId = "46aa";
    }
  ];
}
