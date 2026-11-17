# BlueOS running in Docker on a NixOS host: the container layout install.sh
# produces on Raspbian, with NixOS owning the operating system underneath.
#
# Only the bootstrap container is NixOS's business, and only its creation. That
# container is the same one install.sh creates: it reads startup.json and runs
# blueos-core itself, so the version chooser and the factory reset keep working
# by rewriting that file and restarting the container, exactly as on Raspbian.
#
# That is also why this does not use virtualisation.oci-containers, which runs
# `docker rm -f` before `docker run` on every start. The version chooser switches
# bootstrap by renaming the container to bootstrap-backup and creating a new one
# under the old name, and remove-and-run on boot would silently undo that. This
# mirrors install.sh instead: `docker create` once, `docker start` every boot.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.blueos;
  inherit (lib)
    mkDefault
    mkIf
    ;

  docker = config.virtualisation.docker.package;

  container = "blueos-bootstrap";

  core = "${cfg.docker.coreImage}:${cfg.docker.tag}";
  bootstrap = "${cfg.docker.bootstrapImage}:${cfg.docker.tag}";
  factory = "${cfg.docker.coreImage}:factory";

  startupJson = pkgs.writeText "blueos-startup.json" (
    builtins.replaceStrings [ ''"factory"'' ] [ ''"${cfg.docker.tag}"'' ] (
      builtins.readFile "${cfg.source}/bootstrap/startup.json.default"
    )
  );

  installScript = ''
    set -e
    have() { docker image inspect "$1" > /dev/null 2>&1; }

    ${lib.concatMapStringsSep "\n" (image: ''
      if ! have ${image.image}; then
        docker load --input ${image.archive}
      fi
    '') cfg.docker.images}

    # bootstrap, and core when the card does not carry it
    for image in ${bootstrap} ${core}; do
      if ! have "$image"; then
        docker pull "$image"
      fi
    done

    docker tag ${core} ${factory}

    # Only create. A container the version chooser replaced is a different one
    # under the same name, and it has to survive the reboot.
    if ! docker inspect --type container ${container} > /dev/null 2>&1; then
      docker create -t \
        --restart unless-stopped \
        --name ${container} \
        --net=host \
        -v /root/.config/blueos/bootstrap:/root/.config/bootstrap \
        -v /run/docker.sock:/var/run/docker.sock \
        -v /var/logs/blueos:/var/logs/blueos \
        -e BLUEOS_CONFIG_PATH=/root/.config/blueos \
        ${bootstrap}
    fi

    docker start ${container}
  '';
in
{
  imports = [
    ./options.nix
    ./host.nix
  ];

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (image: image.image == core || image.image == bootstrap) cfg.docker.images;
        message = "Every image in services.blueos.docker.images has to be the one services.blueos.docker.coreImage/bootstrapImage and docker.tag name, since a loaded archive keeps its own tag rather than taking the one it is started from.";
      }
    ];

    sdImage.storePaths = map (image: image.archive) cfg.docker.images;

    virtualisation.docker = {
      enable = mkDefault true;
      daemon.settings.features.containerd-snapshotter = false;
    };

    services.journald.settings.Journal.Storage = "persistent";

    environment.etc."dhcpcd.conf".text = "";

    systemd.tmpfiles.rules = [
      "d /root/.config/blueos/bootstrap 0755 root root -"
      "d /root/.docker 0755 root root -"
      "d /root/.majortom 0755 root root -"
      "d /home/${cfg.user.name}/.docker 0755 ${cfg.user.name} users -"
      "d /run/wpa_supplicant 0755 root root -"
      "d /tmp/wpa_playground 0755 root root -"
      "L+ /etc/resolv.conf.host - - - - /etc/resolv.conf"
    ];

    systemd.services = {
      # Seeds only. The version chooser rewrites the file, so overwriting it on
      # every boot would undo the version the vehicle is on.
      blueos-startup-json = {
        description = "Seed the BlueOS bootstrap startup.json";
        wantedBy = [ "multi-user.target" ];
        before = [ "blueos-bootstrap.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [ ! -e /root/.config/blueos/bootstrap/startup.json ]; then
            install -m 0644 ${startupJson} /root/.config/blueos/bootstrap/startup.json
          fi
        '';
      };

      blueos-bootstrap = {
        description = "Create and start the BlueOS bootstrap container";
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
          "blueos-startup-json.service"
        ];
        requires = [ "docker.service" ];
        path = [ docker ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = 0;
          Restart = "on-failure";
          RestartSec = "30s";
        };
        unitConfig.StartLimitIntervalSec = 0;
        script = installScript;
      };
    };
  };
}
