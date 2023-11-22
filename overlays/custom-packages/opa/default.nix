# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {

  # OPA Server
  open-policy-agent =
    let
      # OPA flag configuration
      defaultFlags = " -trimpath -buildmode=pie -mod=readonly -tags=netgo";
      linkerFlags = "-w -s -linkmode=external -extldflags=-fPIE -extldflags=-pie ";
      makeFlags = "-fstack-protector-all -fcf-protection=full -fstack-clash-protection -DFORTIFY_SOURCE=3";
    in
      prev.open-policy-agent.overrideAttrs (prevAttrs: {
        configureFlags = [ defaultFlags ];
        ldflags = linkerFlags;
        NIX_CFLAGS_COMPILE = makeFlags;
      });

  # Create OPA IPTable client package
  opa-iptable-client = prev.buildGoModule rec {
    pname = "opa-iptables";
    version = "0.1";

    #define variable for github repository information
    src = prev.fetchFromGitHub {
      owner = "open-policy-agent";
      repo = "contrib";
      rev = "efb4466b7d23ae6356ea8337c3a1e2632e93d7b3";
      sha256 = "sha256-qwhuNfufX163lcRIe1DhJVFZ/UBud1NniSwM45gm2aw=";
    };

    patches =[
      ./opa-iptables.patch
    ];

    vendorSha256 = "sha256-+1MPxuUleAtv3NdifAMQGKB9dKgajfqkjDe/HEId7as=";
    sourceRoot = "source/opa-iptables";
  };
})
