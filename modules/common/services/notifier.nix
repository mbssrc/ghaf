# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.log-notifier;
  inherit (lib)
    concatStringsSep
    getExe
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  eventType = types.submodule {
    options = {
      unit = mkOption {
        type = types.str;
        description = "The systemd service unit to monitor (e.g., 'clamav-daemon.service').";
        example = "sshd.service";
      };
      filter = mkOption {
        type = types.str;
        description = "The string to filter for in the journal entries.";
        example = "Accepted publickey";
      };
      title = mkOption {
        type = types.str;
        default = "System Event";
        description = "The title of the desktop notification.";
      };
      criticality = mkOption {
        type = types.enum [
          "low"
          "normal"
          "critical"
        ];
        default = "normal";
        description = "The urgency level for the notification.";
      };
      icon = mkOption {
        type = types.str;
        default = "${pkgs.ghaf-artwork}/icons/security-red.svg";
        defaultText = "The default Ghaf security alert icon";
        description = "The icon to display in the notification.";
      };
      formatter = mkOption {
        type = types.str;
        default = "${pkgs.coreutils}/bin/cat";
        defaultText = "${pkgs.coreutils}/bin/cat (no formatting)";
        description = ''
          A command to extract information from the log to make it palatable for the user notification.
          Any executable needs to be specified with the nix store path (see example). Currently, the
          Cosmic UI does not support any fancy formatting or icons.

          Defaults to "cat" (no formatting).
        '';
        example = literalExpression ''
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

  eventWatcher = pkgs.writeShellApplication {
    name = "event-watcher";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
      pkgs.gnugrep
      pkgs.util-linux
    ];
    text = ''
      LOG_FILE="/run/log/journal-notifier/events.log"

      # Start a watcher process for each configured event
      ${concatStringsSep "\n" (
        mapAttrsToList (name: event: ''
          ( journalctl -u "${event.unit}" -f -n 0 | \
            grep --line-buffered "${event.filter}" | \
            while IFS= read -r line; do
              if ! formatted_message=$(echo "$line" | ${event.formatter}); then
                echo "Formatter failed for line: $line" >&2
                continue
              fi
              if [ -n "$formatted_message" ]; then
                # shellcheck disable=SC2016
                flock "$LOG_FILE" /bin/sh -c '
                  jq -n \
                    --arg name "${name}" \
                    --arg title "${event.title}" \
                    --arg criticality "${event.criticality}" \
                    --arg icon "${event.icon}" \
                    --arg message "$2" \
                    "{event: \$name, title: \$title, criticality: \$criticality, icon: \$icon, message: \$message}" \
                  >> "$1"
                ' sh "$LOG_FILE" "$formatted_message"
              fi
            done
          ) &
        '') cfg.events
      )}

      wait
    '';
  };

  eventNotifier = pkgs.writeShellApplication {
    name = "event-notifier";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      LOG_FILE="/run/log/journal-notifier/events.log"

      # Exit if user has no graphical session
      USER_ID=$(loginctl list-sessions --json=short | jq -e '.[] | select(.seat != null) | .uid')
      [[ "$USER_ID" != "$UID" ]] && exit 0

      # Parse the last object of the log file as JSON to extract notification parameters
      LAST_OBJECT=$(flock -s "$LOG_FILE" \
        -c "gawk '/^{/ {buffer=\"\"} /^{/,/}$/ {buffer=buffer \$0 ORS} END {printf \"%s\", buffer}' '$LOG_FILE'")
      [[ -z "$LAST_OBJECT" ]] && exit 0

      params=()
      mapfile -d ''' -t params < <( \
        echo "$LAST_OBJECT" | \
        jq -j '[.event, .title, .criticality, .icon, .message] | .[] | tostring + "\u0000"' \
      )

      # Call notify-send with the parsed arguments
      notify-send -t 10000 \
        -a "''${params[0]}" \
        -u "''${params[2]}" \
        -h "string:image-path:''${params[3]}" \
        "''${params[1]}" \
        "''${params[4]}"
    '';
  };

in
{
  options.ghaf.services.log-notifier = {
    enable = mkEnableOption ''
      user log notifier service. This service will monitor the system logs
      (systemd journal) and notify the user of registered events via desktop notifications
    '';
    events = mkOption {
      type = types.attrsOf eventType;
      default = { };
      description = "An attribute set of journal events to watch for.";
      example = literalExpression ''
        {
          "clamav-alert" = {
            unit = "clamav-daemon.service";
            filter = "FOUND";
            title = "Malware Detected!";
            criticality = "critical";
          };
        }
      '';
    };
  };
  config = mkIf cfg.enable {

    users.users.journal-reader = {
      isSystemUser = true;
      group = "journal-reader";
      extraGroups = [ "systemd-journal" ];
    };
    users.groups.journal-reader = { };

    # Create a world-readable directory for the logs at boot
    systemd.tmpfiles.rules = [
      "d /run/log/journal-notifier 0755 journal-reader journal-reader -"
      "f /run/log/journal-notifier/events.log 0644 journal-reader journal-reader -"
    ];

    systemd.services.journal-event-watcher = {
      description = "Journal watcher for user notifications";
      wantedBy = [ "multi-user.target" ];
      before = mapAttrsToList (_: event: event.unit) cfg.events;
      serviceConfig = {
        Type = "simple";
        User = "journal-reader";
        Group = "journal-reader";
        ExecStart = "${getExe eventWatcher}";
        Restart = "always";
        RestartSec = "5s";
      };
    };
    systemd.user = {
      paths.event-notifier = {
        description = "System notification watcher";
        wantedBy = [ "graphical-session.target" ];
        after = [ "journal-event-watcher.service" ];
        pathConfig.PathModified = "/run/log/journal-notifier/events.log";
      };
      services.event-notifier = {
        description = "Desktop user notification dispatcher";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe eventNotifier}";
        };
      };
    };
  };
}
