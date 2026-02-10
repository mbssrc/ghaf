# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-thoruser-trial;
in
{
  options.ghaf.reference.profiles.mvp-thoruser-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for Thor";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      profiles = {
        thor = {
          enable = true;
        };
      };
    };
  };
}
