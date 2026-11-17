# BlueOS running directly on systemd: one unit per service, no container.
#
# The options shared with the Docker deployment are in options.nix, and the
# settings both need from the OS in host.nix.
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
    mkOption
    types
    ;

  # blueos-core carries the venv, one wrapper per Python service, and the built
  # frontend. Its `src` is the patched BlueOS tree, which still owns the nginx,
  # zenoh and udev inputs that are not Python packages.
  blueos = cfg.package;
  src = blueos.passthru.src;

  nginxConf =
    builtins.replaceStrings
      [
        "user www-data;\n"
        "worker_processes auto;\n"
        "pid /run/nginx.pid;\n"
        "/etc/nginx/mime.types"
        "include cors.conf;"
        "/home/pi/frontend"
        "/home/pi/tools/nginx/extensions"
        # Version chooser is replaced with blueos-updates
        "location /version-chooser/ {"
      ]
      [
        ""
        ""
        ""
        "${pkgs.nginx}/conf/mime.types"
        "include ${src}/core/tools/nginx/cors.conf;"
        "${blueos}/share/blueos-frontend"
        "/var/lib/blueos/nginx-extensions"
        "location /updates/ {"
      ]
      (builtins.readFile "${src}/core/tools/nginx/nginx.conf");
in
{
  imports = [
    ./options.nix
    ./host.nix
    ./services.nix
    ./rollback.nix
    ./version.nix
  ];

  options.services.blueos = {
    package = mkOption {
      type = types.package;
      description = ''
        The `blueos-core` package to run. It has to come from this flake, since
        the Python environment is built with the flake's uv2nix inputs; the
        flake's `nixosModules.default` supplies it.
      '';
    };

    packages = {
      ardupilot-tools = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/ardupilot-tools { };
        defaultText = lib.literalMD "this flake's package";
        description = "ArduPilot firmware uploader, apj_tool and decoder.";
      };

      bridges = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/bridges { };
        defaultText = lib.literalMD "this flake's package";
        description = "Serial to UDP bridge, used by bridget and ping.";
      };

      mavlink-server = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/mavlink-server { };
        defaultText = lib.literalMD "this flake's package";
        description = "MAVLink router and its web interface, the one ardupilot_manager drives.";
      };

      mavlink2rest = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/mavlink2rest { };
        defaultText = lib.literalMD "this flake's package";
        description = "MAVLink over REST and websockets.";
      };

      linux2rest = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/linux2rest { };
        defaultText = lib.literalMD "this flake's package";
        description = "Exposes host information as JSON over HTTP.";
      };

      mavlink-camera-manager = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/mavlink-camera-manager { };
        defaultText = lib.literalMD "this flake's package";
        description = "Camera streaming service.";
      };

      machineid-cli = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/machineid-cli { };
        defaultText = lib.literalMD "this flake's package";
        description = "Generates the hardware uuid BlueOS reports.";
      };

      updates = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/blueos-updates { blueos-source = { inherit src; }; };
        defaultText = lib.literalMD "this flake's package";
        description = "Update daemon, which lists and activates NixOS generations.";
      };

      disktest = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/disktest { };
        defaultText = lib.literalMD "this flake's package";
        description = "Sequential disk read/write benchmark used by disk_usage.";
      };

      mcap = mkOption {
        type = types.package;
        default = pkgs.mcap-cli;
        defaultText = lib.literalMD "nixpkgs' mcap-cli";
        description = "MCAP CLI, which recorder_extractor runs doctor and recover with.";
      };

      mcap-foxglove-video-extract = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/mcap-foxglove-video-extract { };
        defaultText = lib.literalMD "this flake's package";
        description = "Extracts video tracks out of MCAP recordings.";
      };

      zenoh = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/zenoh { };
        defaultText = lib.literalMD "this flake's package";
        description = "Zenoh router, with the rest and storage plugins.";
      };

      zenoh-backend-filesystem = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/zenoh-backend-filesystem { };
        defaultText = lib.literalMD "this flake's package";
        description = "Zenoh filesystem storage backend.";
      };

      blueos-recorder = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/blueos-recorder { };
        defaultText = lib.literalMD "this flake's package";
        description = "Records Zenoh traffic to MCAP files.";
      };

      zenoh-plugin-remote-api = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../packages/zenoh-plugin-remote-api { };
        defaultText = lib.literalMD "this flake's package";
        description = "Zenoh websocket plugin, which the frontend's zenoh-ts client speaks to.";
      };
    };

    mavlink = {
      systemId = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "MAVLink system id for the onboard computer.";
      };

      componentId = mkOption {
        type = types.ints.positive;
        default = 194;
        description = "MAVLink component id for the onboard computer.";
      };
    };

    updates = {
      manifestUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://releases.example.com/blueos/manifest.json";
        description = ''
          Where the update daemon reads the list of published releases. Without
          one, the vehicle can still switch between the generations already on
          the card, but is told no remote versions exist.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (blueos.passthru or { }) ? src;
        message = "services.blueos.package must be the blueos-core package from this flake.";
      }
    ];

    services.blueos = {
      source = blueos.passthru.src;
      version = mkDefault blueos.passthru.version;
      revision = mkDefault blueos.passthru.rev;
      channel = mkDefault blueos.passthru.channel;
      # The native deployment runs the version it was built with, so the motd
      # can name it; a Docker guest cannot, since the version chooser moves it
      motdVersion = mkDefault blueos.passthru.version;
    };

    systemd.tmpfiles.rules = [
      "L+ /usr/blueos/static - - - - ${blueos.passthru.swagger-ui}"
    ];

    # Podman exists for extensions only
    virtualisation = {
      podman = {
        enable = mkDefault true;
        dockerCompat = mkDefault true;
        dockerSocket.enable = mkDefault true;
        defaultNetwork.settings.dns_enabled = mkDefault true;
      };
      containers = {
        enable = mkDefault true;
        containersConf.settings.engine = {
          compose_warning_logs = mkDefault false;
          # By default, Podman binds ports without listening,
          # making services undiscoverable by helper
          force_port_listen = mkDefault true;
        };
        registries.settings.unqualified-search-registries = mkDefault [ "docker.io" ];
      };
    };

    services.nginx = {
      enable = mkDefault true;
      config = nginxConf;
      validateConfigFile = false;
    };

    # helper reloads nginx through this pid file
    environment.etc."blueos/nginx.conf".text = nginxConf;

    systemd.services.nginx.serviceConfig = {
      ReadWritePaths = [
        "/usr/blueos"
        "/var/lib/blueos"
      ];
      LogsDirectory = "nginx";
      SupplementaryGroups = [
        "docker"
        "podman"
      ];
    };
  };
}
