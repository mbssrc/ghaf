{
  lib,
  stdenv,
  fetchFromGitHub,
  writeShellScriptBin,
  kernel,
}: let
  pname = "i915-sriov-dkms";
  version = "2024.07.24";
  fake-lsb-release = writeShellScriptBin "lsb_release" ''
    . /etc/os-release || true

    case "$1" in
      -is) echo "''${ID=:-ghaf}";;
      -rs) echo "''${VERSION_ID=:-24.05}";;
    esac
  '';
in
  stdenv.mkDerivation (finalAttrs: {
    inherit pname;
    name = "${pname}-${version}-${kernel.version}";
    inherit version;

    src = fetchFromGitHub {
      owner = "strongtz";
      repo = "i915-sriov-dkms";
      rev = "fb2431a25a8e41bce949c22bb9fdc1c56054f9d2";
      hash = "sha256-7KbDAnzP4c44D0Tq8hYtgpzVUwuEF26iDETemkFe52s=";
    };

    hardeningDisable = ["pic" "format"];
    enableParallelBuilding = true;
    nativeBuildInputs = kernel.moduleBuildDependencies;

    setSourceRoot = ''
      export sourceRoot=$(pwd)/${finalAttrs.src.name}
    '';

    postPatch = ''
      substituteInPlace Makefile \
        --replace-fail "lsb_release" "${fake-lsb-release}/bin/lsb_release"
    '';

    makeFlags =
      kernel.makeFlags
      ++ [
        "-C"
        "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
        "M=$(sourceRoot)"
        "modules"
      ];

    buildFlags = [
      "KERNELRELEASE=${kernel.modDirVersion}-ghaf"
      "KBUILD_EXTMOD=$(sourceRoot)"
    ];

    installPhase = ''
      mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/misc
      install -D -m 755 i915.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/misc/i915.ko
    '';

    meta = with lib; {
      maintainers = [""];
      platforms = ["x86_64-linux"];
      description = "SR-IOV i915 driver";
      homepage = "https://github.com/strongtz/i915-sriov-dkms";
      longDescription = ''
        This is a patched i915 driver to enable SR-IOV on Intel i915 GPUs.
      '';
      broken = !kernel.kernelAtLeast "6.1";
    };
  })
