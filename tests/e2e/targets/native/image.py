import logging
import os
import subprocess
from pathlib import Path

E2E_DIR = Path(__file__).resolve().parents[2]
REPO = E2E_DIR.parents[1]
PACKAGE = "packages.x86_64-linux.blueos-native-qemu"
logger = logging.getLogger(__name__)


def build() -> Path:
    if override := os.environ.get("E2E_NATIVE_IMAGE"):
        image = Path(override).expanduser().resolve()
        if image.suffix != ".qcow2" or not image.is_file():
            raise ValueError(f"E2E_NATIVE_IMAGE has to be an existing .qcow2, got {image}")
        return image

    logger.info("realising %s, which compiles BlueOS the first time", PACKAGE)
    # stderr stays attached so the build log is visible; the store path is on stdout
    result = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", f".#{PACKAGE}"],
        cwd=REPO,
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    out = Path(result.stdout.strip())
    images = list(out.glob("*.qcow2"))
    if len(images) != 1:
        raise RuntimeError(f"expected one qcow2 in {out}, found {[image.name for image in images]}")
    return images[0]
