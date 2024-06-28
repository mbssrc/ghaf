# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  lib,
  inputs,
  name,
  system,
  ...
}: let
  lenovo-x1 = generation: variant: extraModules: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          inputs.microvm.nixosModules.host
          self.nixosModules.reference-appvms
          self.nixosModules.reference-programs
          self.nixosModules.reference-services
          self.nixosModules.profiles
          self.nixosModules.laptop

          (_: {
            time.timeZone = "Asia/Dubai";

            ghaf = {

              profiles = {
                laptop-x86.enable = true;
                # variant type, turn on debug or release
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };

              reference.appvms = {
                enable = true;
                chromium-vm = true;
                gala-vm = true;
                zathura-vm = true;
                element-vm = true;
                appflowy-vm = true;
              };

              reference.services = {
                enable = true;
                dendrite = true;
              };

              reference.programs = {
                windows-launcher = {
                  enable = true;
                  spice = true;
                };
              };
            };
          })
        ]
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${generation}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };
in [
  (lenovo-x1 "gen10" "debug" [
    self.nixosModules.disko-lenovo-x1-basic-v1
    ({ ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix"; })
  ])
  (lenovo-x1 "gen11" "debug" [
    self.nixosModules.disko-lenovo-x1-basic-v1
    ({ ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix"; })
  ])
  (lenovo-x1 "gen10" "release" [
    self.nixosModules.disko-lenovo-x1-basic-v1
    ({ ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen10.nix"; })
  ])
  (lenovo-x1 "gen11" "release" [
    self.nixosModules.disko-lenovo-x1-basic-v1
    ({ ghaf.hardware.definition.configFile = "/lenovo-x1/definitions/x1-gen11.nix"; })
  ])
]
