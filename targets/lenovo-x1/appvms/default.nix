# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{lib, pkgs, ...}: let
  chromium = import ./chromium.nix {inherit lib pkgs;};
  gala = import ./gala.nix {inherit lib pkgs;};
  zathura = import ./zathura.nix {inherit lib pkgs;};
in [
  chromium
  gala
  zathura
]
