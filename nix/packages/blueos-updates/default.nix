{
  blueos-source,
  lib,
  rustPlatform,
  cacert,
  makeWrapper,
  nix,
  pkg-config,
  aws-lc,
  systemd,
  zstd,
}:
let
  src = builtins.path {
    path = "${blueos-source.src}/core/services/blueos-updates";
    name = "blueos-updates-src";
  };
in
rustPlatform.buildRustPackage {
  pname = "blueos-updates";
  version = "0.1.0";

  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    aws-lc
    zstd
  ];

  postInstall = ''
    wrapProgram $out/bin/blueos-updates \
      --suffix PATH : ${
        lib.makeBinPath [
          nix
          systemd
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt
  '';

  meta = {
    description = "BlueOS update daemon, backed by NixOS generations";
    homepage = "https://github.com/BlueRobotics/BlueOS";
    license = lib.licenses.agpl3Plus;
    mainProgram = "blueos-updates";
    platforms = lib.platforms.linux;
  };
}
