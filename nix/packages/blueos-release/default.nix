# The BlueOS containers a guest image ships.
#
# Both archives are fixed-output derivations, so the tag, the digest and the
# hash together name one published image even when the tag itself moves. Moving
# to another image means bumping all three; running the build with a stale hash
# reports the new one.
#
#   nix build --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs =
#     f.inputs.nixpkgs.legacyPackages.aarch64-linux; in pkgs.dockerTools.pullImage
#     { imageName = "bluerobotics/blueos-core"; finalImageTag = "master";
#       imageDigest = "sha256:..."; arch = "arm64"; os = "linux";
#       outputHash = pkgs.lib.fakeHash; outputHashAlgo = "sha256"; }'
#
# The digest is the one the tag resolves to in the multi-arch manifest; the
# per-architecture digests listed inside it name different objects. Only arm64
# is fetched, since the guest images are for Pis.
#
# The tag is a single attribute because the two images of a release have to
# agree: bootstrap starts `blueos-core:<tag>` and the version chooser switches
# both together.
#
# `master` rather than a release: no published tag carries
# 5bcc07cba (navigator: accept NixOS serials on RPi4), and without it a Pi 4
# Navigator reports the Bullseye ttyAMA1-3, which do not exist on the NixOS
# host, so every firmware install fails validation. Move this to a tag once one
# contains it.
{
  dockerTools,
  lib,
}:
let
  tag = "master";

  pull =
    imageName: imageDigest: outputHash:
    {
      image = "${imageName}:${tag}";
      archive = dockerTools.pullImage {
        inherit imageName imageDigest outputHash;
        finalImageTag = tag;
        outputHashAlgo = "sha256";
        os = "linux";
        arch = "arm64";
      };
    };

  core = pull "bluerobotics/blueos-core"
    "sha256:a6989c6363356f67a5ba073dece71382b0a3c43d581ed40891e8a69f2426f64e"
    "sha256-gK7QG3+rtBmm8jNgYa1KaT4xjSx3YGaH+3MOTtfTqOU=";

  bootstrap = pull "bluerobotics/blueos-bootstrap"
    "sha256:2f5a8c8feac2ea165bb3dc97b0f0f4dd8bc3e9341d79de5b7b8c5bc6b22051f0"
    "sha256-q6Q4o5qUWaKJCYeCK9XA1do0BEbIDcqB9WFqjvpMmfM=";
in
{
  # A single attribute, because the two images of a release have to agree:
  # bootstrap starts `blueos-core:<tag>` and the version chooser switches both
  # together.
  inherit
    tag
    core
    bootstrap
    ;

  # What an offline guest ships: the core, and the bootstrap that starts it
  images = [
    core
    bootstrap
  ];

  meta = {
    description = "BlueOS ${tag} core and bootstrap images, for offline installation";
    homepage = "https://github.com/BlueRobotics/BlueOS";
    license = lib.licenses.agpl3Plus;
    platforms = [ "aarch64-linux" ];
  };
}
