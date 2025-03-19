# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules to be exported from Flake
#
{
  imports = [
    ./partitioning/flake-module.nix
    ./givc/flake-module.nix
    ./hardware/flake-module.nix
    ./microvm/flake-module.nix
    ./reference/hardware/flake-module.nix
    ./profiles/flake-module.nix
    ./common/flake-module.nix
    ./development/flake-module.nix
    ./graphics/flake-module.nix
  ];

  flake.nixosModules = {
    #TODO: Add the rest of the modules in their own directories with flake-module.nix
    reference-appvms.imports = [ ./reference/appvms ];
    reference-host-demo-apps.imports = [ ./reference/host-demo-apps ];
    reference-personalize.imports = [ ./reference/personalize ];
    reference-profiles.imports = [ ./reference/profiles ];
    reference-programs.imports = [ ./reference/programs ];
    reference-services.imports = [ ./reference/services ];
  };
}
