# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  runAppCenter = pkgs.writeShellApplication {
    name = "run-flatpak";
    runtimeInputs = [
      pkgs.systemd
      pkgs.gnome-software
    ];
    text = ''
      systemctl --user set-environment WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
      systemctl --user restart xdg-desktop-portal-gtk.service
      gnome-software
    '';
  };
  runXCommand = pkgs.writeShellApplication {
    name = "run-flatpak-app";
    runtimeInputs = [
      pkgs.flatpak
    ];
    text = ''
      flatpak run org.onlyoffice.desktopeditors
    '';
  };
in
{
  flatpak = {
    ramMb = 6144;
    cores = 4;
    bootPriority = "high";
    borderColor = "#027d7b";
    applications = [
      {
        name = "APPStore";
        description = "Appstore to install Flatpak applications";
        icon = "${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/rocs.svg";
        command = "sh -c '${lib.getExe runAppCenter}'";
      }
      {
        name = "OO";
        description = "OnlyOffice Flatpak application";
        icon = "${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/rocs.svg";
        command = "sh -c '${lib.getExe runXCommand}'";
        supportXWayland = true;
      }
    ];
    extraModules = [
      {
        services.flatpak.enable = true;
        ghaf.systemd.withPolkit = true;
        security.polkit = {
          enable = true;
          debug = true;
          extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id.startsWith("org.freedesktop.Flatpak.") &&
                    subject.user == "${config.ghaf.users.appUser.name}") {
                      return polkit.Result.YES;
                }
            });
          '';
        };
        programs.fuse.userAllowOther = true;
        security.rtkit.enable = true;

        ghaf.users.appUser.extraGroups = [
          "wheel"
          "fuse"
        ];

        ghaf.storagevm.directories = [
          {
            directory = "/var/lib/flatpak";
            user = config.ghaf.users.appUser.name;
            group = config.ghaf.users.appUser.name;
            mode = "0777";
          }
        ];

        xdg.portal = {
          enable = true;
          extraPortals = [
            pkgs.xdg-desktop-portal-gtk
          ];
          config = {
            common = {
              default = [
                "gtk"
              ];
            };
          };
        };
        programs.dconf.enable = true;
        systemd.services.flatpak-repo = {
          description = "Add Flathub default repository";
          wantedBy = [ "multi-user.target" ];
          after = [ "multi-user.target" ];
          path = [ pkgs.flatpak ];
          script = ''
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak update --appstream
          '';
        };

        imports = [
          ../services/wireguard-gui/wireguard-gui.nix
        ];
        # Enable WireGuard GUI
        ghaf.reference.services.wireguard-gui.enable = config.ghaf.reference.services.wireguard-gui;
      }
    ];
  };
}
