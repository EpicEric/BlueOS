import logging
import os
import shutil
import urllib.request
from pathlib import Path

from targets.native import image
from targets.sil.vm import disk
from targets.sil.vm.qemu import Qemu
from targets.sil.vm.ssh import Ssh
from targets.target import Target
from utils.retry import wait_until

E2E_DIR = Path(__file__).resolve().parents[2]
logger = logging.getLogger(__name__)

# Endpoints the scenarios call, checked through nginx so a service that has not
# bound yet is caught here rather than as a 502 inside a test
PROBES = ("/ardupilot-manager/v1.0/available_boards", "/wifi-manager/v1.0/status")


class NativeTarget(Target):
    name = "native"
    vm_ssh_forward_port = 2222
    vm_http_forward_port = 8080
    required_tools = ("qemu-img", "qemu-system-x86_64", "ssh", "sshpass")

    def __init__(self) -> None:
        super().__init__()
        if missing := [tool for tool in self.required_tools if not shutil.which(tool)]:
            raise RuntimeError(f"the native target needs {', '.join(missing)} installed")
        if not os.environ.get("E2E_NATIVE_IMAGE") and not shutil.which("nix"):
            raise RuntimeError("the native target needs nix installed, or E2E_NATIVE_IMAGE set to a prebuilt qcow2")
        # Its own directory: the sil target owns .run and would otherwise fight over the pid file
        self.run_dir = E2E_DIR / ".run" / "native"
        self.ssh = Ssh(self.vm_ssh_forward_port)
        self.qemu: Qemu | None = None

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.vm_http_forward_port}"

    def up(self) -> None:
        base = image.build()
        self.run_dir.mkdir(parents=True, exist_ok=True)
        qemu = Qemu(
            self.run_dir,
            disk.overlay(base, self.run_dir / "disk.qcow2"),
            self.vm_ssh_forward_port,
            self.vm_http_forward_port,
        )
        logger.debug("starting vm")
        qemu.start()
        self.qemu = qemu
        self.ssh.wait_ready()
        logger.debug("waiting for blueos")
        self.wait_ready()

    def down(self) -> None:
        if self.qemu is None:
            return
        logger.debug("stopping vm")
        self.qemu.stop()
        self.qemu = None

    def shell(self, command: str) -> str:
        return self.ssh.run(command)

    def wait_ready(self, timeout: float = 600) -> None:
        """
        The units report `active (running)` while the Python services are still
        importing, and nginx answers before any of them bind. A unit that has not
        bound yet makes nginx reply 502, so the services the scenarios speak to
        are probed through nginx instead.
        """

        def ready() -> None:
            if self.shell("systemctl is-active blueos.target") != "active":
                raise RuntimeError("blueos.target is not active")
            for path in PROBES:
                with urllib.request.urlopen(f"{self.base_url}{path}", timeout=10):
                    pass

        wait_until(ready, timeout, interval=5, errors=(OSError, RuntimeError), description=f"BlueOS at {self.base_url}")
