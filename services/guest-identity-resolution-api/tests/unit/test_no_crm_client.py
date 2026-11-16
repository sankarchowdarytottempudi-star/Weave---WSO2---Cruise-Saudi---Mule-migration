"""Plan 21.8: the Python source and tests prove no CRM client or CRM credential exists in the service."""
import ast
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "app"
FORBIDDEN_IMPORTS = {"requests", "httpx", "aiohttp", "urllib3", "http.client", "urllib.request", "zcrmsdk",
                     "zohocrmsdk", "pycurl", "socket", "websockets", "grpc", "kafka", "confluent_kafka", "aiokafka"}
FORBIDDEN_TEXT = re.compile(r"zohoapis|accounts\.zoho|/crm/v\d|client_secret|refresh_token|oauth/v2|"
                            r"zoho_(?:token|client|secret)|crm_(?:token|password|secret|client_id)", re.I)
RUNTIME_FORBIDDEN_PACKAGES = {"requests", "httpx", "aiohttp", "urllib3", "zcrmsdk", "zohocrmsdk", "pycurl",
                              "kafka-python", "confluent-kafka", "aiokafka"}


def _py_files():
    return sorted(APP.rglob("*.py")) + sorted((ROOT / "migrations").rglob("*.py"))


@pytest.mark.parametrize("path", _py_files(), ids=lambda p: str(p.relative_to(ROOT)))
def test_no_network_client_imports(path):
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            names = [node.module]
        for n in names:
            assert not any(n == f or n.startswith(f + ".") for f in FORBIDDEN_IMPORTS), f"{path}: imports {n}"


@pytest.mark.parametrize("path", _py_files(), ids=lambda p: str(p.relative_to(ROOT)))
def test_no_crm_endpoint_or_credential_in_source(path):
    assert not FORBIDDEN_TEXT.search(path.read_text()), f"{path} mentions a CRM endpoint/credential"


def test_runtime_lock_has_no_http_or_crm_client():
    lock = (ROOT / "requirements.txt").read_text().lower()
    pkgs = {line.split("==")[0].strip() for line in lock.splitlines() if "==" in line and not line.startswith(" ")}
    assert not pkgs & RUNTIME_FORBIDDEN_PACKAGES, pkgs & RUNTIME_FORBIDDEN_PACKAGES


def test_settings_have_no_crm_credential():
    from app.config import Settings
    names = {f.lower() for f in Settings.__dataclass_fields__}
    assert not [n for n in names if ("crm" in n or "zoho" in n) and n != "crm_direct_event_enabled"]
    assert not [n for n in names if "kafka" in n]       # Kafka is consumed by WSO2, not by Python


def test_config_catalogue_secrets_contain_no_crm_credential():
    text = (ROOT / "config" / "config-catalogue.yaml").read_text()
    secrets = text.split("\nsecrets:", 1)[1]
    assert "CRM" not in secrets.upper().replace("CRM_DIRECT", "")
