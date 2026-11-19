from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import ClassVar, TypeVar, cast

T = TypeVar("T")


class Target(ABC):
    name: ClassVar[str]
    # Whether BlueOS runs the images the suite is given, instead of being the OS itself
    runs_docker_images: ClassVar[bool] = False

    def __init__(self) -> None:
        self.features: dict[object, object] = {}

    def feature(self, kind: Callable[..., T]) -> T:
        try:
            return cast(T, self.features[kind])
        except KeyError:
            raise NotImplementedError(f"{self.name} does not implement {kind}") from None

    @property
    @abstractmethod
    def base_url(self) -> str:
        ...

    @abstractmethod
    def up(self) -> None:
        """Returns once BlueOS answers, which is what the fixtures rely on"""
        ...

    @abstractmethod
    def down(self) -> None:
        ...

    @abstractmethod
    def shell(self, command: str) -> str:
        ...
