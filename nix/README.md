# BlueOS on NixOS

NixOS support for BlueOS on Raspberry Pis 4 and 5.

The flake at the repository root is BlueOS itself. `blueos-core`, `blueos-frontend` and the image all build from this checkout, so the version they report cannot drift from the code they contain. The revision and build date come from the flake's own git metadata (`self.rev`, `self.lastModifiedDate`); `version` and `channel` in `nix/packages/blueos-source` are literals, because a flake cannot read its own tags. Bump them as part of cutting a release.

`version` currently sits between releases, so it is `1.5.0-dev` and the channel is `dev`. Two consequences worth knowing:

- BlueOS reports `1.5.0-dev-0-g<rev>`. The version chooser lists local generations, which are distinguished by their store path and revision.
- Sentry stays off. `commonwealth/utils/sentry_config.py` only enables it when the describe string matches `<x.y.z>-<commits>-g<hash>`, and the `-dev` suffix fails that check. That is intended: crashes in a dev build are not crashes of a release that exists.

## Developing

The devshell carries the toolchain for both halves: `bun` and `nodejs` for the frontend, `uv` and `python311` for the services, `cargo` and `rustc` for the Rust packages.

```fish
nix develop
```

Packages the services run are built by the flake, so a change to one is a `nix build` rather than a container rebuild:

```fish
nix build .#blueos-core
```

The flake evaluates only tracked files, so an untracked scratch file is invisible to it. `git add` it, or build with `nix build --impure --expr`.

## Building an image

`nixosConfigurations.blueos-pi4` and `blueos-pi5` are `aarch64-linux` systems, so building one needs either an ARM host or `boot.binfmt.emulatedSystems` on an x86_64 machine. CI runs on `ubuntu-24.04-arm` and builds them natively. There is no cross-compiled variant.

```fish
nix build .#nixosConfigurations.blueos-pi4.config.system.build.sdImage
```

`lib.mkImage` builds the same system with a different version, manifest or cache, which is what a release repository uses:

```nix
blueos.lib.mkImage {
  board = "4";
  version = "1.5.0";
  channel = "stable";
  manifestUrl = "https://releases.example.com/blueos/manifest.json";
  cache = {
    host = "https://cache.example.com";
    publicKey = "cache.example.com-1:...";
  };
}
```

The configurations in this repository call it with no release configured, so they report the literal version and use the placeholder manifest and cache described below. That is what CI caches.

## Releases

Publishing lives outside this repository. This one builds and caches; a separate repository pins a BlueOS commit, tags it on its own schedule, builds the images and publishes `manifest.json`. Tagging images there rather than here keeps them off the Docker container's release cadence.

The cache host and manifest URL currently default to the standalone flake's personal infrastructure, in `nixConfig` and in `lib.mkImage`. They are placeholders: both have to move to BlueRobotics-owned endpoints before these images are handed to anyone else, and until then the flake's `nixConfig` asks every evaluator to trust that key. `services.blueos.cache` accepts `null` to ship a device that trusts no cache beyond nixpkgs, and `lib.mkImage` accepts `manifestUrl = null` to offer no remote releases.

## QEMU guests

Two x86_64 guests exist for the end-to-end tests, sharing `nix/nixos/qemu/common.nix`. They are different things and answer different questions:

- `blueos-guest` is a Docker host. It contains no BlueOS; the build under test arrives as a container selected by the test run, so the image never tracks a BlueOS revision and can serve upstream's suite at any commit.
- `blueos-native` runs `services.blueos` from this checkout. It exists to catch regressions in the port.

```fish
nix build .#packages.x86_64-linux.blueos-guest-qemu
nix build .#packages.x86_64-linux.blueos-native-qemu
```

`system.build.images.qemu` runs its install step inside `vmTools.runInLinuxVM`, so building either image requires the `kvm` system feature. The system closure does not, which is why CI caches that instead: `qemu-system` in `nix.yml` builds and pins `config.system.build.toplevel`, and an image built from a cached closure needs no network, since `nixos-install` is called with `--substituters ""`.

`blueos-native` sets `rollback.enable = false`. `rollback.nix` reads `config.hardware.raspberry-pi.firmware.path`, which only exists with nixos-hardware's Pi modules, so the option cannot evaluate on x86_64.

## Patch policy

Upstream is a container image: it installs services into `/home/pi`, runs them under `tmux`, and derives the version from a Docker tag. This flake runs the same services as systemd units. The patches bridge that gap.

Every patch has to fall into exactly one of these buckets:

- **Never upstream.** The change is wrong for the container image. Each of these needs a comment in the patch itself saying so and why, so it does not get proposed again.
- **Permanently carried.** A feature this flake needs that upstream will not take, or has not taken yet.

The patches currently carried:

| Patch | Bucket | Why |
| --- | --- | --- |
| `blueos-core/cable-guy-dhcpcd.patch` | Never upstream | A `dhcpcd` daemon already owns the interface on Bookworm and Bullseye; the one-shot client would regress the inherited `DHCPCD` handler. |
| `blueos-core/helper-nixos-factory-mode.patch` | Never upstream | Skips the factory-mode probe, which asks the container version chooser for a `factory` tag. Generations have no such tag, so the probe only ever 404s here. |
| `blueos-core/helper-nginx-paths.patch` | Permanently carried | Points helper at this flake's nginx pid file, extension directory and config. Upstream's paths are container-specific. |

A patch that upstream merges is deleted in the same commit that notices it, never kept in case. `git apply --check -p1` is not a reliable signal: a patch can apply cleanly while being entirely obsolete, because it landed on unrelated code.

## Known gaps

- **Log rotation.** Upstream removed the `log_zipper` service without a replacement. `/var/logs/blueos` now grows until `nix.gc` removes an old generation. Worth revisiting if upstream adds rotation back.
- **Navigator EEPROM.** The EEPROM endpoints read `/sys/bus/i2c/devices/0-0050/eeprom`, which only exists when the `navigator-eeprom` device tree overlay is loaded. The Pi 4 image loads it; the Pi 5 board script does not, so those endpoints report `EEPROM_NOT_FOUND` there.
