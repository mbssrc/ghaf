# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Thor AGX
#
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (inputs) nixos-generators jetpack-nixos;

  thor-configuration = import ./thor-configuration-builder.nix {
    inherit
      lib
      self
      inputs
      jetpack-nixos
      ;
  };

  # setup some commonality between the configurations
  commonModules = [
    (nixos-generators + "/format-module.nix")
    ../../modules/reference/hardware/jetpack/nvidia-jetson-thor/format-module.nix
    jetpack-nixos.nixosModules.default
    self.nixosModules.reference-profiles-thor
    self.nixosModules.profiles
    self.nixosModules.givc
  ];

  # concatenate modules that are specific to a target
  withCommonModules = specificModules: specificModules ++ commonModules;

  target-configs = [
    # Thor Debug configuration
    (thor-configuration "nvidia-jetson-thor" "agx" "debug" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-thor-agx
      {
        ghaf.reference.profiles.mvp-thoruser-trial.enable = true;
      }
    ]))

    # Thor Release configuration
    (thor-configuration "nvidia-jetson-thor" "agx" "release" (withCommonModules [
      self.nixosModules.hardware-nvidia-jetson-thor-agx
      {
        ghaf = {
          reference.profiles.mvp-thoruser-trial.enable = true;
        };
      }
    ]))
  ];

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ self.nixosModules.cross-compilation-from-x86_64 ];
      };
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };

  targets = target-configs;
  crossTargets = map generate-cross-from-x86_64 targets;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );

    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
        # Raw jetpack flash scripts (QSPI only)
        // builtins.listToAttrs (
          map (
            t: lib.nameValuePair "${t.name}-flash-qspi" t.hostConfiguration.pkgs.nvidia-jetpack.flashScript
          ) crossTargets
        )
        # Wrapped flash scripts with NVMe support
        // builtins.listToAttrs (
          map (
            t:
            let
              cfg = t.hostConfiguration.config;
              inherit (t.hostConfiguration) pkgs;
              x86Pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            in
            lib.nameValuePair "${t.name}-flash-ghaf" (
              x86Pkgs.callPackage ../../packages/flash-thor/package.nix {
                jetpackFlashScript = pkgs.nvidia-jetpack.flashScript;
                sdImage = cfg.system.build.${cfg.formatAttr};
                imageName = cfg.image.fileName;
              }
            )
          ) crossTargets
        );
    };
  };
}
