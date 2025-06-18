# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.host.networking;
  inherit (lib)
    mkEnableOption
    mkIf
    optionals
    mapAttrsToList
    concatStringsSep
    ;
  sshKeysHelper = pkgs.callPackage ../common/ssh-keys-helper.nix { inherit config; };
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
in
{
  options.ghaf.host.networking = {
    enable = mkEnableOption "networking";
    hostNetworking = mkEnableOption "host networking";
    # TODO add options to configure the network, e.g. ip addr etc
  };

  config = mkMerge [

    # Common networking configuration
    # Sets up a bridge network for VMs
    (mkIf cfg.enable {
      networking = {
        enableIPv6 = false;
        useNetworkd = true;
        interfaces.virbr0.useDHCP = false;
      };

      systemd.network = {
        netdevs."10-virbr0".netdevConfig = {
          Kind = "bridge";
          Name = "virbr0";
        };
        networks."10-virbr0" = {
          matchConfig.Name = "virbr0";
          linkConfig = {
            ARP = false;
          };
          networkConfig = {
            DHCP = false;
            DHCPServer = false;
          };
        };
        # Connect VM tun/tap device to the bridge
        # TODO configure this based on IF the netvm is enabled
        networks."11-netvm" = {
          matchConfig.Name = "tap-*";
          networkConfig.Bridge = "virbr0";
        };
      };

      # Enforce static ARP with ebtables
      ghaf.networking.static-arp.enable = true;
    })

    # Additional network configuration for host networking
    # Sets up a veth pair and connects it to the host bridge
    (mkIf cfg.hostNetworking {

      networking = {
        firewall.allowedTCPPorts = [ 22 ];
        firewall.allowedUDPPorts = [ 67 ];
        nat = {
          enable = true;
          internalInterfaces = [ "ethint0" ];
        };
        interfaces."ethint0".useDHCP = false;
      };

      systemd.network = {
        netdevs."20-host-veth" = {
          netdevConfig = {
            Name = "ethint0";
            Kind = "veth";
            MACAddress = hosts.${hostName}.mac;
          };
          # Not technically a tap device, but part of veth pair
          peerConfig.Name = "tap-${hostName}";
        };
        networks."20-ethint0" = {
          matchConfig.Name = "ethint0";
          addresses = [ { Address = "${hosts.${hostName}.ipv4}/24"; } ];
          gateway = optionals (builtins.hasAttr "net-vm" config.microvm.vms) [ "${hosts."net-vm".ipv4}" ];
          linkConfig = {
            RequiredForOnline = "routable";
            ActivationPolicy = "always-up";
          };
          extraConfig = concatStringsSep "\n" (
            mapAttrsToList (_: entry: ''
              [Neighbor]
              Address=${entry.ipv4}
              LinkLayerAddress=${entry.mac}
            '') hosts
          );
        };
      };

      environment.etc = {
        ${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
      };

      services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;
      services.resolved.dnssec = "false";
    })
  ];
}
