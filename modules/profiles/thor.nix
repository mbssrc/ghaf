# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.profiles.thor;
in
{
  options.ghaf.profiles.thor = {
    enable = lib.mkEnableOption "Enable the basic nvidia thor config";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      # Console-only host - no graphics
      profiles.graphics.enable = false;
    };
  };
}
