import pytest
from blueos.core import BlueOS
from images import CORE
from targets.target import Target


def test_blueos_runs_expected_image(blueos: BlueOS, target: Target) -> None:
    if not target.runs_docker_images:
        pytest.skip(f"the {target.name} target runs BlueOS without container images")

    repository, _, tag = CORE.rpartition(":")
    version = blueos.version()
    assert (version["repository"], version["tag"]) == (repository, tag)
