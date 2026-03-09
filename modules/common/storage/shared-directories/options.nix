# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared directories options definitions
#
{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.ghaf.storage.shared-directories = {

    enable = mkEnableOption "shared directories module for cross-VM file sharing";
    debug = mkEnableOption "debug logging for shared directories daemon";

    scanner = {
      enable = mkEnableOption ''
        malware scanning. This option is a global scanning override, so no malware scanning will
        be performed, irrespective of whether the individual channel scanning option is enabled or not.

        Note: when this option is enabled, you need to make sure that the scanning daemon is
        running at the time when shares are used - otherwise, any content will be treated as malware.
        You can bypass this behaviour per-channel by enabling the `permissive` option, which will
        gracefully ignore scanning daemon errors and only trigger on infected files
      '';
    };

    baseDirectory = mkOption {
      type = types.path;
      default = "/persist/shared";
      description = "Base directory where shared directory channels will be created";
    };

    channels = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            mode = mkOption {
              type = types.enum [
                "fallback"
                "untrusted"
                "trusted"
              ];
              description = ''
                Channel operation mode:
                - `fallback`: Plain virtiofs share - all VMs access the same directory directly (no isolation, not recommended)
                - `untrusted`: Per-writer isolation with scanning enabled by default
                - `trusted`: Per-writer isolation with scanning disabled by default
              '';
            };

            readWrite = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    mountPoint = mkOption {
                      type = types.path;
                      description = "Mount path inside VM";
                    };
                    user = mkOption {
                      type = types.str;
                      default = "root";
                      description = "Owner user for the mount point directory";
                    };
                    group = mkOption {
                      type = types.str;
                      default = "root";
                      description = "Owner group for the mount point directory";
                    };
                    mode = mkOption {
                      type = types.str;
                      default = "0755";
                      description = "Permissions mode for the mount point directory";
                    };
                    notify = mkEnableOption "vsock notifications when files change in this channel";
                  };
                }
              );
              default = { };
              description = "Read-write participants. Content is synced bi-directionally between all readWrite participants.";
            };

            readOnly = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    mountPoint = mkOption {
                      type = types.path;
                      description = "Mount path inside VM or host bind mount target";
                    };
                    notify = mkEnableOption "vsock notifications when files change in this channel";
                  };
                }
              );
              default = { };
              description = "Read-only participants. Can only read the aggregated export from all writers.";
            };

            writeOnly = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    mountPoint = mkOption {
                      type = types.path;
                      description = "Mount path inside VM";
                    };
                    user = mkOption {
                      type = types.str;
                      default = "root";
                      description = "Owner user for the mount point directory";
                    };
                    group = mkOption {
                      type = types.str;
                      default = "root";
                      description = "Owner group for the mount point directory";
                    };
                    mode = mkOption {
                      type = types.str;
                      default = "0755";
                      description = "Permissions mode for the mount point directory";
                    };
                  };
                }
              );
              default = { };
              description = ''
                Write-only participants (diode mode). Can write files but content from other
                participants is not propagated back to them. Cannot modify existing files.

                Use cases:
                - Public keys shared during secure initialization that should not be changed
                - Less trusted VMs that need write access but should not see other content
              '';
            };

            scanning = {
              enable = mkEnableOption "scanning for this channel" // {
                default = true;
              };
              permissive = mkEnableOption "permissive mode - this will treat scanning errors as clean files";
              infectedAction = mkOption {
                type = types.enum [
                  "log"
                  "quarantine"
                  "delete"
                ];
                default = "quarantine";
                description = ''
                  Action to take when an infected file is detected:
                  - `log`: Log the infection but leave the file in place
                  - `quarantine`: Move the file to quarantine directory
                  - `delete`: Delete the infected file
                '';
              };
              ignoreFilePatterns = mkOption {
                type = types.listOf types.str;
                default = [
                  ".crdownload"
                  ".part"
                  ".tmp"
                  "~$"
                ];
                description = "File name suffix patterns to ignore. Matching files are not scanned or copied, and remain only in the original location.";
              };
              ignorePathPatterns = mkOption {
                type = types.listOf types.str;
                default = [
                  ".Trash-"
                ];
                description = "Path substring patterns to ignore. Matching files are not scanned or copied, and remain only in the original location.";
              };
            };

            debounceMs = mkOption {
              type = types.int;
              default = 300;
              description = "Debounce time in milliseconds for file change events to avoid multiple scans for rapid changes.";
            };

            userNotify = {
              enable = mkEnableOption "desktop notifications for scan events" // {
                default = true;
              };
              socket = mkOption {
                type = types.str;
                default = "/run/clamav/notify.sock";
                description = "Unix socket path for sending user notifications";
              };
            };

            guestNotify = {
              port = mkOption {
                type = types.port;
                default = 3401;
                description = "Vsock port for notifications (must match virtiofs-notify service on guests)";
              };
            };
          };
        }
      );
      default = { };
      description = ''
        Shared directory channels for cross-VM file sharing.

        Each channel has a mode:
        - `untrusted`: Per-writer isolation with scanning enabled by default
        - `trusted`: Per-writer isolation with scanning disabled by default
        - `fallback`: Simple shared directory on host, participants access via their mountpoint (no isolation, no scanning)

        For untrusted/trusted modes, the daemon monitors changes and distributes files
        to all readWrite and readOnly participants. If scanning.enable = true, files
        are scanned before distribution.

        Participants:
        - readWrite: Can read and write; content is synced between all readWrite participants
        - readOnly: Can only read the aggregated content from all writers
        - writeOnly: Can write but cannot see content from other participants (diode mode)
      '';
    };
  };
}
