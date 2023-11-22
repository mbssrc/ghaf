# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  fetchurl,
  ...
}:
  stdenv.mkDerivation rec {
    name = "tetragon";
    version = "v1.0.0";
    targetSystem = if stdenv.isAarch64 then "arm64" else "amd64";

    src =
      if stdenv.isAarch64
      then
        fetchurl {
          url = "https://github.com/cilium/tetragon/releases/download/${version}/tetragon-${version}-${targetSystem}.tar.gz";
          sha256 = "sha256-lpJJHsvhvhY02YOvJXood6Rvd3PdbK9Zl9hI9JNCLsg=";
        }
      else
        fetchurl {
          url = "https://github.com/cilium/tetragon/releases/download/${version}/tetragon-${version}-${targetSystem}.tar.gz";
          sha256 = "sha256-7rGWlxxhku7Q0V4gyIiaYf+uZNd+Md/RXxnwPJNxK/Y=";
        };

    srcPath = "tetragon-${version}-${targetSystem}";

    unpackPhase = ''
      tar -xvf $src
    '';

    installPhase = ''
      mkdir -p $out/lib
      mkdir -p $out/lib/tetragon
      sed -i "s+/usr/local/+$out/+g" ${srcPath}/usr/local/lib/tetragon/tetragon.conf.d/bpf-lib
      cp -n -r ${srcPath}/usr/local/lib/tetragon/tetragon.conf.d/ $out/lib/tetragon/
      cp -n -r ${srcPath}/usr/local/lib/tetragon/bpftool $out/lib/tetragon/ # install?
      cp -n -r ${srcPath}/usr/local/lib/tetragon/bpf $out/lib/tetragon/
      mkdir -p $out/lib/tetragon/tetragon.tp.d/
      install -m755 -D ${srcPath}/usr/local/bin/tetra $out/bin/tetra
      install -m755 -D ${srcPath}/usr/local/bin/tetragon $out/bin/tetragon
    '';

    meta = with lib; {
      description = "Tetragon policy client.";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  }
