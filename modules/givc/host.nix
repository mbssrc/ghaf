# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  pkgs,
  ...
}: let
  cfg = config.ghaf.givc.host;
  inherit (builtins) map filter concatStringsSep;
  inherit (lib) mkEnableOption mkIf forEach;
  hostName = "ghaf-host-debug";
  getIp = name: lib.head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.entries));
  addr = getIp hostName;
in {
  options.ghaf.givc.host = {
    enable = mkEnableOption "Enable host givc module.";
  };

  config = mkIf cfg.enable {
    # Configure host service
    givc.host = {
      enable = true;
      name = hostName;
      inherit addr;
      port = "9000";
      services = [
        "microvm@chromium-vm.service"
        "microvm@gala-vm.service"
        "microvm@zathura-vm.service"
        "microvm@gui-vm.service"
        "microvm@net-vm.service"
        "microvm@audio-vm.service"
        "microvm@admin-vm.service"
        "poweroff.target"
        "reboot.target"
      ];
      tls = {
        enable = config.ghaf.givc.enableTls;
        caCertPath = "/etc/givc/ca/ca-cert.pem";
        certPath = "/etc/givc/${hostName}/${hostName}-cert.pem";
        keyPath = "/etc/givc/${hostName}/${hostName}-key.pem";
      };
      admin = config.ghaf.givc.adminConfig;
    };

    environment.systemPackages = [pkgs.openssl];

    # Generate keys and certificates for givc, if they don't exist
    systemd.services = {
      "givc-setup" = let
        givcCertGen = pkgs.writeShellScriptBin "gen_certs" ''
          set -xeuo pipefail

          # Parameters
          VALIDITY=3650
          CONSTRAINTS="basicConstraints=critical,CA:true,pathlen:1"
          GIVC_DIRECTORY="/etc/givc"
          CA_DIRECTORY="''${GIVC_DIRECTORY}/ca"

          # Function to create key/cert based on IP and/or DNS
          gen_cert(){
              name="$1"
              path="''${GIVC_DIRECTORY}/''${name}"
              mkdir -p "$path"

              usage="extendedKeyUsage=serverAuth,clientAuth"
              if [ $# -eq 2 ]; then
                ip1="$2"
                alttext="subjectAltName=IP.1:''${ip1},DNS.1:''${name}"
              else
                alttext="subjectAltName=DNS.1:''${name}"
              fi
              ${pkgs.openssl}/bin/openssl genpkey -algorithm ED25519 -out "$path"/"$name"-key.pem
              ${pkgs.openssl}/bin/openssl req -new -key "$path"/"$name"-key.pem -out "$path"/"$name"-csr.pem -subj "/CN=''${name}" -addext "$alttext" -addext "$usage"
              ${pkgs.openssl}/bin/openssl x509 -req -in "$path"/"$name"-csr.pem -CA $CA_DIRECTORY/ca-cert.pem -CAkey $CA_DIRECTORY/ca-key.pem -CAcreateserial -out "$path"/"$name"-cert.pem -extfile <(printf "%s" "$alttext") -days $VALIDITY

              cp $CA_DIRECTORY/ca-cert.pem "$path"/ca-cert.pem
              if [ "$name" == "ghaf-host-debug" ]; then
                chown -R root:root "$path"
                chmod -R 400 "$path"
              else
                chown -R microvm:kvm "$path"
                chmod -R 770 "$path"
              fi
              rm "$path"/"$name"-csr.pem
          }

          # Create CA
          mkdir -p $CA_DIRECTORY
          ${pkgs.openssl}/bin/openssl genpkey -algorithm ED25519 -out $CA_DIRECTORY/ca-key.pem
          ${pkgs.openssl}/bin/openssl req -x509 -new -key $CA_DIRECTORY/ca-key.pem -out $CA_DIRECTORY/ca-cert.pem -subj "/CN=GivcCA" -addext $CONSTRAINTS -days $VALIDITY
          chmod -R 400 $CA_DIRECTORY

          # Generate keys/certificates
          ${concatStringsSep "\n" (forEach config.ghaf.networking.hosts.entries (
            entry: "gen_cert ${entry.name} ${entry.ip}"
          ))}

          /run/current-system/systemd/bin/systemd-notify --ready
        '';
      in {
        enable = config.ghaf.givc.enableTls;
        description = "Generate keys and certificates for givc";
        path = [givcCertGen];
        wantedBy = ["local-fs.target"];
        unitConfig.ConditionPathExists = "!/etc/givc";
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
          Restart = "no";
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${givcCertGen}/bin/gen_certs";
        };
      };
    };
  };
}
