# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Plymouth theme: top-to-bottom fade-in reveal of the Reem logo.
# Uses Plymouth's "script" module with 36 pre-baked animation frames.
#
{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "plymouth-reem-boot";
  version = "1.0.0";
  src = ./.;

  dontBuild = true;

  installPhase = ''
    d=$out/share/plymouth/themes/reem-boot
    mkdir -p "$d"
    cp reem-boot.script "$d/"
    cp title.png "$d/"
    cp -r animation "$d/"

    # Rewrite hard-coded paths to the nix store
    substitute reem-boot.plymouth "$d/reem-boot.plymouth" \
      --replace-fail "/usr/share/plymouth/themes/reem-boot" "$d"
  '';

  meta = {
    description = "Reem boot splash — animated logo reveal for Plymouth";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
