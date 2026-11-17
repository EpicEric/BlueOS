# BlueOS on NixOS

NixOS support for BlueOS on Raspberry Pis 4 and 5.

The revision and build date come from the flake's own git metadata (`self.rev`, `self.lastModifiedDate`), while `version` and `channel` in `nix/packages/blueos-source` are literals, because a flake cannot read its own tags. They should be bumped as part of cutting a release.

## Module layout

`nix/modules/blueos` holds one deployment per file, on top of two shared halves:

- `options.nix` has the options both deployments need, and `host.nix` the OS settings both need: network stack, udev rules, the directories the container binds, kernel modules and sysctls.
- `native.nix` runs BlueOS from systemd, one unit per service. It adds the `blueos-core` package, the release metadata and the update daemon.
- `guest.nix` runs BlueOS in Docker behind `blueos-bootstrap`, and adds the image tag and the unit that creates and starts that container.

Only `native.nix` is exported as `nixosModules.default`, since the Docker deployment is a whole image rather than something to add to an existing system.

## Developing

The devshell carries the toolchain for both halves: `bun` and `nodejs` for the frontend, `uv` and `python311` for the Python services, and `cargo` and `rustc` for the Rust packages.

```fish
nix develop
```

Packages are built by the flake:

```fish
nix build .#blueos-core
```

The flake evaluates only git-tracked files, so make sure to `git add` them.

## Building an image

`nixosConfigurations.blueos-pi4`, `blueos-pi5`, `blueos-pi4-guest` and `blueos-pi5-guest` are `aarch64-linux` systems, so building one needs either an ARM host or `binfmt` QEMU emulation on an x86_64 machine.

The two plain names run BlueOS directly from systemd; the `-guest` names run the regular BlueOS containers under Docker, which is the closer match to how a Raspbian install works.

```fish
nix build .#nixosConfigurations.blueos-pi4.config.system.build.sdImage
nix build .#nixosConfigurations.blueos-pi4-guest.config.system.build.sdImage
```

The configurations in this repository call it with no release configured, so they report the literal version and use the placeholder manifest and cache described below. That is what CI caches.

## Releases

Publishing lives outside this repo.

`lib.mkImage` builds the same system with a different version, manifest or cache, which is what the release repo uses:

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

The release repo pins a BlueOS commit, tags it on its own schedule, builds the images and publishes `manifest.json`. Tagging images there rather than here keeps them off the Docker container's release cadence.

## Docker guests

`blueos-pi4-guest` and `blueos-pi5-guest` are the same board support and the same SD image as the native ones, but the OS is NixOS while BlueOS stays a set of containers behind `blueos-bootstrap`, as on Raspbian.

That choice is deliberate. The version chooser runs inside the core container and switches versions by rewriting `startup.json` and killing `blueos-core`; if NixOS owned that container as a systemd unit, every switch would silently come back on the declared image. Owning the bootstrap container instead keeps version switching and factory reset working exactly as they do today.

What NixOS owns is the tag the bootstrap starts from. Moving a vehicle to a new BlueOS is therefore either the version chooser (Docker) or a rebuild with a different tag:

```fish
nix build .#nixosConfigurations.blueos-pi4-guest.config.system.build.sdImage
```

```nix
blueos.lib.mkGuestImage {
  board = "4";
  tag = "1.4.7";
  cache = {
    host = "https://cache.example.com";
    publicKey = "cache.example.com-1:...";
  };
}
```

The image seeds `/root/.config/blueos/bootstrap/startup.json` on the first boot only, so it never undoes the version the vehicle is on. It also pulls the core image and tags it `:factory` at boot, because that tag has to exist locally for a factory reset to have something to fall back to.

That work is a single unit, `blueos-bootstrap`, mirroring what `install/install.sh` does in sequence: load or pull what is missing, tag `:factory`, `docker create` the bootstrap container if it does not already exist, then `docker start` it. It retries indefinitely, so a board that powers up without a network or with a wrong clock (a Pi has no battery-backed RTC, and Docker Hub's certificates validate by date) simply keeps trying until it succeeds. `install/configs/blueos.service` on Raspbian is the equivalent of the last step alone.

Deliberately not `virtualisation.oci-containers`: that module runs `docker rm -f` and then `docker run` on every unit start. The version chooser switches bootstrap by renaming the container to `bootstrap-backup` and creating a new one under the old name, so remove-and-run at boot would silently undo the switch. `docker create` guarded by "does this container already exist" leaves it alone, which is what Raspbian does.

NixOS also gets the classic Docker image store, which BlueOS's bootstrap, version chooser and extension tooling all assume, and Docker is the only container runtime enabled; the native deployments use Podman for extensions instead.

### Factory images on the card

The guests ship both containers by default, so a card that has never seen a network still boots into a working BlueOS: `blueos-release` pins one published image, and `mkGuestImage` passes both archives to `services.blueos.docker.images`. They are loaded on first boot, before anything is pulled. Loading is skipped when the image is already in Docker's store, so it costs one unpack per card rather than one per boot.

`blueos-release` is a separate package from the images CI publishes, because it is a fixed-output derivation: the tag, the multi-arch digest and the archive hash all name one image, and moving it means bumping all three. That also pins a moving tag, so `master` here is one specific build rather than whatever `master` points at later. To move it:

```fish
nix build --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs =
  f.inputs.nixpkgs.legacyPackages.aarch64-linux; in pkgs.dockerTools.pullImage
  { imageName = "bluerobotics/blueos-core"; finalImageTag = "master";
    imageDigest = "sha256:..."; arch = "arm64"; os = "linux";
    outputHash = pkgs.lib.fakeHash; outputHashAlgo = "sha256"; }'
```

The digest is what the tag resolves to in the multi-arch manifest, not the per-architecture digest listed inside it. Building with a stale hash reports the new one.

The pin is on `master` because no released tag carries `5bcc07cba` (navigator: accept NixOS serials on RPi4). Without it the Pi 4 Navigator detector falls back to the Bullseye mapping, `ttyAMA1`-`ttyAMA3`, which do not exist on the NixOS host, so `Serial` rejects them and every firmware install fails. Move the pin to a tag once one contains that commit.

Use `lib.mkGuestImage { board = "4"; offline = false; }` for a card that should carry no images and pull from the registry on first boot instead.

## QEMU guests

Two x86_64 guests exist for end-to-end tests, sharing `nix/nixos/qemu/common.nix`:

- `blueos-guest` is a Docker host. BlueOS is installed as a container by the test run.
- `blueos-native` runs `services.blueos` from this checkout. It exists to catch regressions in the port.

```fish
nix build .#packages.x86_64-linux.blueos-guest-qemu
nix build .#packages.x86_64-linux.blueos-native-qemu
```

`system.build.images.qemu` runs its install step inside `vmTools.runInLinuxVM`, so building either image requires the `kvm` system feature.

`blueos-native` disables the rollback feature, since it requires nixos-hardware's Raspberry Pi modules.

## Patch policy

Patches allow the NixOS version to diverge from the Docker origin in a controlled manner.

Every patch has to fall into exactly one of these buckets:

- **Never upstream.** The change is wrong for the container image. Each of these needs a comment in the patch itself saying so and why, so it does not get proposed again.
- **Permanently carried.** A feature this flake needs that the main repo will not take, or has not taken yet.

The patches currently carried:

| Patch | Bucket | Why |
| --- | --- | --- |
| `blueos-core/cable-guy-dhcpcd.patch` | Never upstream | A `dhcpcd` daemon already owns the interface on Bookworm and Bullseye; the one-shot client would regress the inherited `DHCPCD` handler. |
| `blueos-core/helper-nixos-factory-mode.patch` | Never upstream | Skips the factory-mode probe, which asks the container version chooser for a `factory` tag. Generations have no such concept, so the probe would always fail. |
| `blueos-core/helper-nginx-paths.patch` | Permanently carried | Points helper at this flake's nginx pid file, extension directory and config. |

A patch that upstream merges must be deleted in the same commit that notices it.

## Known gaps

- **No RPi3 support.** A Navigator cannot be used on a Pi3, the hat expects a pinout the board does not have.
- **Log rotation.** BlueOS removed the `log_zipper` service without a replacement. `/var/logs/blueos` now grows until `nix.gc` removes an old generation.
- **Navigator EEPROM.** The EEPROM endpoints read `/sys/bus/i2c/devices/0-0050/eeprom`, which only exists when the `navigator-eeprom` device tree overlay is loaded. The Pi 4 image loads it, but the Pi 5 board script does not, so those endpoints report `EEPROM_NOT_FOUND` there.
