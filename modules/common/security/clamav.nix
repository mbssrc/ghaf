# Copyright 2025 TII (SSRC) and the Ghaf contributors
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
    concatStringsSep
    getExe
    mkEnableOption
    mkIf
    optionalAttrs
    optionalString
    types
    ;

  clamavMonitor = pkgs.writeShellApplication {
    name = "clamav-monitor";
    runtimeInputs = [
      config.services.clamav.package
      pkgs.inotify-tools
      pkgs.gawk
    ];
    text = ''
      # Script to do initial scan and monitor directories for changes
      # using inotifywait or clamonacc on 'watchDirectories'.

      # Note: The '--move' option using rename does not work for our shares, but it
      # appears a fallback option works for clamonacc. The feature file access is blocked
      # after so the virus event action does not work.
      # Generally, we rely on '--copy' and manually remove infected files with clamscand,
      # and use the clamav virus event handler as a fallback in case the file cannot be copied
      # or removed due to permission issues.

      scan_file() {
        local file="$1"
        local exit_code=0

        # Double check that the file still exists
        [[ -f "$file" ]] || return 1

        # Scan the file with clamdscan
        clamdscan --fdpass --quiet --infected "$file" || exit_code=$?

        # Check errors
        [[ $exit_code -eq 1 ]] &&  echo "Infected file found: $file"
        [[ $exit_code -gt 1 ]] &&  echo "Clamdscan error (code $exit_code) while scanning $file." >&2
      }
      export -f scan_file

      # Convert watchDirectories to an array
      IFS=' ' read -r -a watch_dirs <<< "${lib.concatStringsSep " " cfg.watchDirectories}"

      # Initial scan on startup
      echo "Starting initial scan of directories: ''${watch_dirs[*]}"
      for dir in "''${watch_dirs[@]}"; do
        [[ -d "$dir" ]] || { echo "Warning: Watch directory $dir does not exist or is not a directory." >&2; continue; }
        # shellcheck disable=SC2016
        find "$dir" -type f -exec /bin/sh -c 'scan_file "$0"' {} \;
      done

      # Continuous on-access monitoring
    ''
    + optionalString (cfg.monitoringType == "clamonacc") ''
      echo "Starting to monitor directories with clamonacc..."
      clamonacc \
        --wait \
        --fdpass \
        --allmatch \
        --move=${cfg.quarantineDirectory} \
        --foreground
    ''
    + optionalString (cfg.monitoringType == "inotify") ''
      echo "Starting to monitor directories with inotify/clamdscan..."

      # Separate local and remote directories for appropriate monitoring
      remote_dirs=()
      local_dirs=()
      for dir in "''${watch_dirs[@]}"; do
        fs_type=$(df -T "$dir" | awk 'NR==2 {print $2}')
        case $fs_type in
          "virtiofs"|"9p"|"nfs"|"nfs4"|"cifs"|"fuse.sshfs")
            remote_dirs+=("$dir")
            ;;
          *)
            local_dirs+=("$dir")
            ;;
        esac
      done

      # Start monitoring local and remote directories
      (inotifywait -m -r -e close_write,moved_to --format '%w%f' "''${local_dirs[@]}" | while IFS= read -r file; do
        scan_file "$file"
      done) &
      (inotifywait -m -r -e access --format '%w%f' "''${remote_dirs[@]}" | while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        scan_file "$file"
      done) &
      wait
    '';
  };

  clamavEventHandler = pkgs.writeShellApplication {
    name = "clamav-event-handler";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      # Custom ClamAV virus event handler script
      [[ $# -ne 2 ]] && { echo "Usage: $0 <filename> <virusname>" >&2; exit 1; }
      [[ -z "$1" || -z "$2" ]] && { echo "Both filepath and virusname must be provided." >&2; exit 1; }

      CLAM_VIRUSEVENT_FILENAME="$1"
      CLAM_VIRUSEVENT_VIRUSNAME="$2"
      alert="VIRUSALERT=Malware $CLAM_VIRUSEVENT_VIRUSNAME was detected in file $CLAM_VIRUSEVENT_FILENAME "

      # Force file quarantine as root in case the previous client options failed
      if [ -f "$CLAM_VIRUSEVENT_FILENAME" ]; then
        cp -f "$CLAM_VIRUSEVENT_FILENAME" "${cfg.quarantineDirectory}/$(basename "$CLAM_VIRUSEVENT_FILENAME")"
        rm -f "$CLAM_VIRUSEVENT_FILENAME"
        alert+="and quarantined."
      else
        alert+="but could not be quarantined (file not found)."
      fi

      echo "$alert"
    '';
  };

in
{
  options.ghaf.security.clamav = {
    enable = mkEnableOption "Enable ClamAV antivirus service.";
    scanDirectories = lib.mkOption {
      type = types.listOf types.str;
      default = [
        "/home"
        "/var"
        "/tmp"
        "/etc"
      ];
      description = ''
        Directories to scan with clamdscan in the defined interval.
        For real-time (on-access) monitoring, use the 'watchDirectories' option.
      '';
      example = [
        "/home"
        "/var"
        "/tmp"
        "/etc"
      ];
    };
    quarantineDirectory = lib.mkOption {
      type = types.str;
      default = "/var/lib/clamav/quarantine";
      description = "Directory to move infected files to. This directory is automatically excluded from scans.";
      example = "/var/lib/clamav/quarantine";
    };
    excludeDirectories = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Directories to exclude from regular scans. This is useful for sub-directories of scanDirectories or watchDirectories
        that contain large or frequently changing files, or are otherwise not suitable for scanning.
      '';
      example = [
        "/var/cache"
      ];
    };
    watchDirectories = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Directories to monitor and scan with clamdscan on change. This may have a considerable performance impact -
        do not use this option for large directories or directories with frequently changing files. See also the
        "monitoringType" option.
      '';
      example = [
        "/home"
        "/var"
      ];
    };
    monitoringType = lib.mkOption {
      type = types.enum [
        "clamonacc"
        "inotify"
      ];
      default = "inotify";
      description = ''
        Monitoring type for the monitor service.

        ClamAV's clamonacc is used in conjunction with the OnAccess* options of clamd. This provides kernel-based real-time
        protection against malware by scanning files when they are accessed. The "inotify" option uses inotifywait to monitor
        file system events and triggers scans with clamdscan when files are moved, modified or created.

        Note that live monitoring may have a noticable performance impact, especially when monitoring directories with
        high I/O activity. Be careful, and consult the ClamAV documentation for details.
      '';
    };
  };
  config = mkIf cfg.enable {

    ghaf = {
      # User notifier for clamav
      services.log-notifier = {
        enable = true;
        events = {
          "clamav-alert" = {
            unit = "clamav-daemon.service";
            filter = "VIRUSALERT";
            title = "Malware Detected";
            criticality = "critical";
            formatter = ''
              ${pkgs.gawk}/bin/awk '
                /VIRUSALERT=/ {
                  sub(/.*VIRUSALERT=/, "");
                  printf "%s\n", $0;
                }
              '
            '';
          };
        };
      };
    }
    // lib.optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      # Persistent storage
      storagevm.directories = [
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
        {
          directory = "${cfg.quarantineDirectory}";
          user = "clamav";
          group = "clamav";
          mode = "0700";
        }
      ];
    };

    # ClamAV configuration
    services.clamav = {

      # Regular scanning service
      scanner = {
        enable = true;
        interval = "hourly";
        inherit (cfg) scanDirectories;
      };

      # Database updater
      updater = {
        enable = true;
        interval = "daily";
        frequency = 24;
      };

      # Third-party updates
      fangfrisch = {
        enable = true;
        interval = "daily";
      };

      # ClamAV Daemon
      daemon = {
        enable = true;
        settings = {
          VirusEvent = ''
            /run/wrappers/bin/sudo ${getExe clamavEventHandler} "$CLAM_VIRUSEVENT_FILENAME" %v
          '';
          LogFile = "/var/log/clamav/clamd.log";
          LogTime = true;
          LogClean = false;
          LogSyslog = true;
          LogVerbose = false;
          LogFileMaxSize = "20M";
          ExtendedDetectionInfo = true;
          OnAccessPrevention = true;
          OnAccessExcludeUname = "clamav";
          OnAccessExcludeRootUID = true;
          OnAccessRetryAttempts = 3;
          OnAccessIncludePath = "${concatStringsSep " " cfg.watchDirectories}";
          OnAccessExcludePath = "${cfg.quarantineDirectory} ${concatStringsSep " " cfg.excludeDirectories}";
          ExcludePath = "${cfg.quarantineDirectory} ${concatStringsSep " " cfg.excludeDirectories}";
        };
      };
    };

    # Run clamav virus event handler as root
    security.sudo.extraConfig = ''
      clamav ALL=(root) NOPASSWD: ${getExe clamavEventHandler}
    '';

    # Clamav monitor service
    systemd = optionalAttrs (cfg.watchDirectories != [ ]) {
      paths.clamav-monitor = {
        description = "ClamAV Socket Monitor";
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathExists = "/run/clamav/clamd.ctl";
      };
      services.clamav-monitor = {
        description = "ClamAV monitor service";
        documentation = [ "man:clamonacc(8)" ];
        serviceConfig = {
          ExecStart = "${getExe clamavMonitor}";
          Restart = "always";
          RestartSec = "3s";
          Slice = "system-clamav.slice";
        };
      };
    };
  };
}
