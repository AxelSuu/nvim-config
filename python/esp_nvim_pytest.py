"""pytest plugin with the helper fixtures ESP-IDF examples expect from ESP-IDF's own (CI-only) conftest.

Loaded by Neovim's Space Et/EI test runner: PYTHONPATH=~/.config/nvim/python pytest -p esp_nvim_pytest
"""

import logging
import typing as t

import pytest


@pytest.fixture
def log_minimum_free_heap_size(dut: t.Any) -> t.Callable[..., None]:
    def real_func() -> None:
        res = dut.expect(r"Minimum free heap size: (\d+) bytes")
        logging.info("minimum free heap size: %s bytes", res.group(1).decode("utf8"))

    return real_func


@pytest.fixture
def log_performance(record_property: t.Callable[[str, object], None]) -> t.Callable[[str, str], None]:
    def real_func(item: str, value: str) -> None:
        logging.info("[Performance][%s]: %s", item, value)
        record_property(item, value)

    return real_func


@pytest.fixture
def check_performance() -> t.Callable[[str, float, str], None]:
    def real_func(item: str, value: float, target: str) -> None:
        logging.info("[Performance][%s][%s]: %s (no thresholds outside ESP-IDF CI)", target, item, value)

    return real_func
