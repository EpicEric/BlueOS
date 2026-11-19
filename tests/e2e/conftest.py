import logging
import os
from collections.abc import Iterator

import pytest
from blueos.core import BlueOS
from targets.native.target import NativeTarget
from targets.sil.target import SilTarget
from targets.target import Target

logger = logging.getLogger(__name__)

TARGETS: dict[str, type[Target]] = {"sil": SilTarget, "native": NativeTarget}


def selected_targets() -> list[type[Target]]:
    names = [name.strip() for name in os.environ.get("E2E_TARGETS", "sil").split(",") if name.strip()]
    unknown = [name for name in names if name not in TARGETS]
    if unknown:
        raise ValueError(f"unknown E2E_TARGETS {unknown}, choose from {list(TARGETS)}")
    return [TARGETS[name] for name in names]


@pytest.fixture(
    name="target",
    scope="session",
    params=selected_targets(),
    ids=lambda target_class: target_class.name,
)
def target_fixture(request: pytest.FixtureRequest) -> Iterator[Target]:
    target = request.param()
    logger.info("setting up %s target...", target.name)
    try:
        target.up()
    except NotImplementedError:
        pytest.skip(f"{target.name} target not implemented")
    except BaseException:
        target.down()
        raise
    yield target
    target.down()


@pytest.fixture(name="blueos", scope="session")
def blueos_fixture(target: Target) -> BlueOS:
    # Readiness is the target's business: what "ready" means differs per backend
    return BlueOS(target.base_url)
