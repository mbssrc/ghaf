# Copyright 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.clamav;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionals
    replaceString
    types
    ;

  # Helpers
  isHost = config.ghaf.virtualization.microvm-host.enable or false;

  # Wait for internet connectivity by checking NTP server reachability
  waitForInternet = pkgs.writeShellApplication {
    name = "wait-for-internet";
    runtimeInputs = [ pkgs.netcat ];
    text = ''
      servers=(${
        lib.concatMapStringsSep " " lib.escapeShellArg config.networking.timeServers
      } "time.cloudflare.com")
      while true; do
        for server in "''${servers[@]}"; do
          if nc -z -u -w 1 "$server" 123 2>/dev/null; then
            exit 0
          fi
        done
        sleep 30
      done
    '';
  };

  clamavScanner = pkgs.writeShellApplication {
    name = "clamav-scanner";
    runtimeInputs = [
      config.services.clamav.package
      pkgs.ghaf-virtiofs-tools
      pkgs.socat
    ];
    text = ''
      case "$1" in
        # on-access is configured via daemon config
        on-modify)
          DIRS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-modify.directories)})
          EXCLUDES=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-modify.excludeDirectories)})
          ;;
        on-schedule)
          DIRS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-schedule.directories)})
          EXCLUDE_DIRS=${lib.escapeShellArg (lib.concatStringsSep "|" cfg.scan.on-schedule.excludeDirectories)}
          ;;
        *)          echo "Usage: $0 <on-access|on-modify|on-schedule>" >&2; exit 1 ;;
      esac

      case "$1" in
        on-access)
          echo "Initial scan: ''${DIRS[*]}"
          clamdscan --fdpass --multiscan --infected --allmatch --move="${cfg.quarantineDirectory}" "''${DIRS[@]}" || true

          echo "Starting on-access monitoring..."
          clamonacc --wait --fdpass --allmatch --foreground --move="${cfg.quarantineDirectory}"
          ;;
        on-modify)
          [[ ''${#DIRS[@]} -eq 0 ]] && { echo "No directories to monitor for $1"; exit 0; }
          echo "Starting on-modify monitoring for: ''${DIRS[*]}"

          clamd-vclient \
            ${
              if cfg.daemon.enable then
                "--socket"
              else
                "--cid ${toString cfg.scan.on-modify.clientConfig.cid} --port ${toString cfg.scan.on-modify.clientConfig.port}"
            } \
            --action quarantine \
            --quarantine-dir "${cfg.quarantineDirectory}" \
            ''${EXCLUDES[@]:+--exclude "''${EXCLUDES[@]}"} \
            --watch "''${DIRS[@]}"
          ;;
        on-schedule)
          [[ ''${#DIRS[@]} -eq 0 ]] && { echo "No directories to monitor for $1"; exit 0; }
          echo "Scheduled scan: ''${DIRS[*]}"

          set +e
          scan_output=$(clamscan \
            ''${EXCLUDE_DIRS:+--exclude-dir="$EXCLUDE_DIRS"} \
            --multiscan --infected --allmatch --no-summary \
            --move="${cfg.quarantineDirectory}" "''${DIRS[@]}" 2>&1)
          scan_exit_code=$?
          set -e

          echo "$scan_output"
          case $scan_exit_code in
            0) echo "Scan completed - no threats found" ;;
            1)
              # Parse and notify for each infected file
              while IFS= read -r line; do
                [[ "$line" =~ ^(.+):[[:space:]]+(.+)[[:space:]]+FOUND$ ]] || continue
                alert="Malware ''${BASH_REMATCH[2]} was detected in file: ''${BASH_REMATCH[1]}"
                echo "$alert" | socat - UNIX-CONNECT:/run/clamav/notify.sock 2>/dev/null || echo "$alert" >&2
              done <<< "$scan_output"
              ;;
            *) echo "Scan error occurred" >&2; exit 2 ;;
          esac
      esac
    '';
  };

  clamavEventHandler = pkgs.writeShellApplication {
    name = "clamav-event-handler";
    runtimeInputs = [ pkgs.socat ];
    text = ''
      # Custom ClamAV virus event handler script
      [[ $# -ne 2 ]] && { echo "Usage: $0 <filename> <virusname>" >&2; exit 1; }
      [[ -z "$1" || -z "$2" ]] && { echo "Both filepath and virusname must be provided." >&2; exit 1; }
      CLAM_VIRUSEVENT_FILENAME="$1"
      CLAM_VIRUSEVENT_VIRUSNAME="$2"
      alert="Malware $CLAM_VIRUSEVENT_VIRUSNAME was detected in file: $CLAM_VIRUSEVENT_FILENAME"
      echo "$alert" >&2

      # Send notification via socket
      if [[ -S /run/clamav/notify.sock ]]; then
        echo "$alert" | socat - UNIX-CONNECT:/run/clamav/notify.sock || {
          echo "Failed to send notification via socket" >&2
        }
      else
        echo "Notification socket not available" >&2
      fi
    '';
  };

  # User notification script; this runs as a separate service that
  # has no restrictions on network communication
  givcNotify = pkgs.writeShellApplication {
    name = "givc-notify";
    runtimeInputs = [
      pkgs.givc-cli
      pkgs.socat
    ];
    text = ''
      # Read message (5s timeout, 4KB max)
      MESSAGE=$(socat -T5 -u STDIN STDOUT,readbytes=4096 2>/dev/null) || MESSAGE=""
      if [[ -z "$MESSAGE" ]]; then
        echo "Invalid or oversized message received" >&2
        exit 1
      fi

      # Send notification via givc-cli with retries
      MESSAGE_SENT=false
      SECONDS=0
      while [[ "$MESSAGE_SENT" != "true" && $SECONDS -lt 10 ]]; do
        if givc-cli ${replaceString "/run" "/etc" config.ghaf.givc.cliArgs} notify-user gui-vm \
        --event "ClamAV Alert" \
        --title "Malware Found" \
        --urgency "critical" \
        --message "$MESSAGE"; then
          MESSAGE_SENT=true
        else
          echo "Retrying notification via givc-cli..." >&2
          sleep 1
        fi
      done

      if [[ "$MESSAGE_SENT" == "true" ]]; then
        echo "Notification sent via givc-cli"
      else
        echo "Failed to send notification via givc-cli: $MESSAGE" >&2
        exit 1
      fi
    '';
  };

in
{
  options.ghaf.security.clamav = {
    enable = mkEnableOption "ClamAV antivirus service";

    daemon = {
      enable = mkEnableOption "ClamAV daemon (clamd) for real-time scanning";
      alertOnLimitsExceeded = mkEnableOption ''
        flag files exceeding size/recursion limits as 'Heuristics.Limits.Exceeded'.
        When disabled (default), files exceeding MaxFileSize (2GB), MaxScanSize (4GB),
        or other limits are silently allowed through without scanning
      '';
    };

    proxy = {
      enable = mkEnableOption "clamd-vproxy on host to provide scanning proxy via vsock";
      cid = mkOption {
        type = types.int;
        default = 2;
        description = "Vsock CID of the proxy (defaults to host: 2).";
      };
      port = mkOption {
        type = types.port;
        default = 3400;
        description = "Vsock port where clamd-vproxy listens for guest connections.";
      };
    };

    quarantineDirectory = mkOption {
      type = types.str;
      default = "/var/lib/clamav/quarantine";
      description = "Directory to move infected files detected by scanning.";
    };

    scan = {
      on-access = {
        enable = mkEnableOption "on-access scanning via clamonacc (fanotify-based, blocks file access until scanned)";
        directories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Directories to monitor and scan with clamdscan on change. This enables real-time (on-access) scanning of files.
            This feature may have a noticable performance impact, especially when monitoring directories with
            high I/O activity. Consult the ClamAV documentation for details.
          '';
          example = [
            "/home"
            "/var"
          ];
        };
        excludeDirectories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Directories to exclude from on-access scans.";
          example = [ "/var/cache" ];
        };
      };
      on-modify = {
        enable = mkEnableOption "on-modify scanning via inotify trigger";
        directories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Directories to monitor and scan with clamd on modification, using inotifywait monitoring 'close_write' and 'moved_to' events.
          '';
          example = [
            "/home"
            "/var"
          ];
        };
        excludeDirectories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Directories to exclude from on-modify monitoring.";
          example = [ "/var/cache" ];
        };
        clientConfig = {
          cid = mkOption {
            type = types.int;
            default = 2;
            description = "Vsock CID of the remote scanner when daemon is not local. Default is 2 (host).";
          };
          port = mkOption {
            type = types.port;
            default = 3400;
            description = "Vsock port for connecting to clamd-vproxy when daemon is not local.";
          };
        };
      };
      on-schedule = {
        enable = mkEnableOption "scheduled periodic scanning";
        interval = mkOption {
          type = types.str;
          default = "hourly";
          description = ''
            Interval for regular ClamAV scans. See systemd.timer documentation for valid values.
            Uses clamdscan (fast) when daemon is enabled, clamscan (standalone) otherwise.
          '';
          example = "daily";
        };
        directories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Directories to scan in the defined interval.";
          example = [
            "/home"
            "/var"
            "/tmp"
            "/etc"
          ];
        };
        excludeDirectories = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Directories to exclude from scheduled scanning. Only used in standalone mode (without daemon).";
          example = [ "/var/cache" ];
        };
      };
    };

    database = {
      updater = {
        enable = mkEnableOption "automatic ClamAV database updates";
        interval = mkOption {
          type = types.str;
          default = "hourly";
          description = "Interval for ClamAV database updates. See systemd.timer documentation for valid values.";
          example = "daily";
        };
      };
      fangfrisch = {
        enable = mkEnableOption "automatic updates of third-party ClamAV databases via fangfrisch";
        interval = mkOption {
          type = types.str;
          default = "daily";
          description = "Interval for fangfrisch database updates. See systemd.timer documentation for valid values.";
          example = "weekly";
        };
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      # on-access: requires directories and local daemon (clamonacc uses fanotify)
      {
        assertion = cfg.scan.on-access.enable -> cfg.scan.on-access.directories != [ ];
        message = "ghaf-clamav: scan.on-access.enable requires scan.on-access.directories to be set";
      }
      {
        assertion = cfg.scan.on-access.enable -> cfg.daemon.enable;
        message = "ghaf-clamav: scan.on-access.enable requires daemon.enable (clamonacc needs clamd)";
      }
      # on-modify: requires directories (can use local daemon or remote via vsock)
      {
        assertion = cfg.scan.on-modify.enable -> cfg.scan.on-modify.directories != [ ];
        message = "ghaf-clamav: scan.on-modify.enable requires scan.on-modify.directories to be set";
      }
      # on-schedule: requires directories; standalone mode (no daemon) needs database updater
      {
        assertion = cfg.scan.on-schedule.enable -> cfg.scan.on-schedule.directories != [ ];
        message = "ghaf-clamav: scan.on-schedule.enable requires scan.on-schedule.directories to be set";
      }
      {
        assertion = cfg.scan.on-schedule.enable && !cfg.daemon.enable -> cfg.database.updater.enable;
        message = "ghaf-clamav: scan.on-schedule without daemon requires database.updater.enable (standalone clamscan needs database)";
      }
      # proxy: requires local daemon to forward requests to
      {
        assertion = cfg.proxy.enable -> cfg.daemon.enable;
        message = "ghaf-clamav: proxy.enable requires daemon.enable (clamd-vproxy needs clamd)";
      }
    ];

    # Create clamav user/group when daemon is not enabled
    users =
      mkIf
        (
          !cfg.daemon.enable
          && (cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable)
        )
        {
          users.clamav = {
            isSystemUser = true;
            group = "clamav";
            description = "ClamAV user";
          };
          groups.clamav = { };
        };

    # ClamAV module configuration
    services.clamav = {

      # Regular scanning service
      scanner = mkIf cfg.daemon.enable {
        inherit (cfg.scan.on-schedule) enable interval;
        scanDirectories = cfg.scan.on-schedule.directories;
      };

      # Database updater
      updater = {
        inherit (cfg.database.updater) enable interval;
      };

      # Third-party updates
      fangfrisch = {
        inherit (cfg.database.fangfrisch) enable interval;
      };

      # ClamAV Daemon
      daemon = {
        inherit (cfg.daemon) enable;
        settings = mkIf cfg.daemon.enable (
          {
            AlertExceedsMax = cfg.daemon.alertOnLimitsExceeded;
            LogFile = "/var/log/clamav/clamd.log";
            LogTime = true;
            LogClean = false;
            LogSyslog = true;
            LogVerbose = false;
            LogFileMaxSize = "20M";
            ExtendedDetectionInfo = true;
            ExcludePath = [ cfg.quarantineDirectory ];
            StreamMaxLength = "2G"; # Max data via INSTREAM
            MaxFileSize = "2G"; # Max individual file size
            MaxScanSize = "4G"; # Max cumulative size for archives
          }
          # VirusEvent is needed for on-access (clamonacc) and on-schedule with daemon (clamdscan)
          # Note: may cause duplicate notifications if on-modify is also enabled (clamd-vclient notifies directly)
          // lib.optionalAttrs (cfg.scan.on-access.enable || cfg.scan.on-schedule.enable) {
            VirusEvent = ''
              ${getExe clamavEventHandler} "$CLAM_VIRUSEVENT_FILENAME" %v
            '';
          }
          // lib.optionalAttrs cfg.scan.on-access.enable {
            OnAccessPrevention = true;
            OnAccessExcludeUname = "clamav";
            OnAccessRetryAttempts = 3;
            OnAccessIncludePath = cfg.scan.on-access.directories;
            OnAccessExcludePath = [
              cfg.quarantineDirectory
            ]
            ++ cfg.scan.on-access.excludeDirectories;
          }
        );
      };
    };

    # Guest storage
    ghaf.storagevm.directories = mkIf (!isHost) (
      optionals cfg.daemon.enable [
        {
          directory = "/var/lib/clamav";
          user = "clamav";
          group = "clamav";
          mode = "0700";
        }
        {
          directory = "/var/log/clamav";
          user = "clamav";
          group = "clamav";
          mode = "0700";
        }
      ]
      ++
        optionals (cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable)
          [
            {
              directory = cfg.quarantineDirectory;
              user = "root";
              group = "root";
              mode = "0700";
            }
          ]
    );

    # Systemd services and configurations
    systemd = mkMerge [

      # Updater - Freshclam: run on boot and persist timer for subsequent runs
      (mkIf cfg.database.updater.enable {
        services.clamav-freshclam = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStartPre = [ (getExe waitForInternet) ];
        };
        timers.clamav-freshclam.timerConfig.Persistent = true;
      })

      # Updater - Fangfrisch: run on boot and persist timer for subsequent runs
      (mkIf cfg.database.fangfrisch.enable {
        services.clamav-fangfrisch = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStartPre = [ (getExe waitForInternet) ];
        };
        timers.clamav-fangfrisch.timerConfig.Persistent = true;
      })

      # Clamav-daemon configuration
      (mkIf cfg.daemon.enable {
        # Custom activation chain: db exists -> socket & daemon
        paths.clamav-daemon = {
          description = "Watch for ClamAV database availability";
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathExists = "/var/lib/clamav/main.cvd";
        };
        sockets.clamav-daemon = {
          wantedBy = lib.mkForce [ ];
          after = [ "systemd-tmpfiles-setup.service" ];
          requires = [ "systemd-tmpfiles-setup.service" ];
        };
        services.clamav-daemon = {
          wantedBy = lib.mkForce [ ];
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      })

      # On-modify monitor service - tracks file modifications via inotify
      (mkIf cfg.scan.on-modify.enable {
        paths.clamav-on-modify-monitor = mkIf (!cfg.daemon.enable) {
          description = "ClamAV on-modify monitor activator";
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathExists = "/dev/vsock";
        };
        services.clamav-on-modify-monitor = {
          description = "ClamAV on-modify monitor service";
          wantedBy = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          after = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          bindsTo = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${getExe clamavScanner} on-modify";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # On-access monitor service
      (mkIf (cfg.daemon.enable && cfg.scan.on-access.enable) {
        services.clamav-on-access-monitor = {
          description = "ClamAV on-access monitor service";
          documentation = [ "man:clamonacc(8)" ];
          wantedBy = [ "clamav-daemon.service" ];
          bindsTo = [ "clamav-daemon.service" ];
          after = [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${getExe clamavScanner} on-access";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # Standalone on-schedule service (when daemon is not enabled)
      (mkIf (cfg.scan.on-schedule.enable && !cfg.daemon.enable) {
        timers.clamav-on-schedule = {
          description = "ClamAV scheduled scanner timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.scan.on-schedule.interval;
            Persistent = true;
            # RandomizedDelaySec = "5m";
          };
        };
        services.clamav-on-schedule = {
          description = "ClamAV scheduled scanner service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${getExe clamavScanner} on-schedule";
            Slice = "system-clamav.slice";
          };
        };
      })

      # ClamAV vsock proxy service (bridge to clients via vsock)
      (mkIf cfg.proxy.enable {
        services.clamd-vproxy = {
          description = "ClamAV vsock proxy for file scanning";
          wantedBy = [ "clamav-daemon.service" ];
          bindsTo = [ "clamav-daemon.service" ];
          after = [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe' pkgs.ghaf-virtiofs-tools "clamd-vproxy"} --cid ${toString cfg.proxy.cid} --port ${toString cfg.proxy.port}";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # User notification service
      (mkIf
        (
          cfg.scan.on-access.enable
          || cfg.scan.on-schedule.enable
          || cfg.scan.on-modify.enable
          || cfg.daemon.enable
        )
        {
          sockets.clamav-notify = {
            description = "ClamAV notification socket";
            after = [ "systemd-tmpfiles-setup.service" ];
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = "/run/clamav/notify.sock";
              SocketUser = "clamav";
              SocketGroup = "clamav";
              SocketMode = "0600";
              Accept = "yes";
            };
          };
          services."clamav-notify@" = {
            description = "ClamAV user notification service";
            serviceConfig = {
              ExecStart = "${getExe givcNotify}";
              Slice = "system-clamav.slice";
              StandardInput = "socket";
            };
          };
          tmpfiles.rules = [ "d /run/clamav 0755 clamav clamav -" ];
        }
      )

      # Host storage
      (mkIf isHost {
        tmpfiles.rules = [
          "d /var/lib/clamav 0700 clamav clamav -"
          "d /var/log/clamav 0700 clamav clamav -"
          "f /var/log/clamav/clamd.log 0600 clamav clamav -"
        ]
        ++ lib.optional (
          cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable
        ) "d ${cfg.quarantineDirectory} 0700 clamav clamav -";
      })
    ];

  };
}
