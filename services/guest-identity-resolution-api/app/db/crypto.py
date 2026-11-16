"""Protection of display values and ID pairs (plan sections 8.2, 18).

AES-256-GCM with a key read from a mounted secret (GIR_DATA_KEY[_FILE]); each value carries its
key id so keys can be rotated. Equality/uniqueness of Global and Loyalty IDs uses HMAC-SHA256
with a separate key, so plaintext IDs are never indexed. Keys are never logged or returned."""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
from typing import Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

_VERSION = b"\x01"


class Crypto:
    def __init__(self, key_b64: str, key_id: str, hmac_key_b64: str):
        if not key_b64 or not hmac_key_b64:
            raise RuntimeError("data protection keys are not configured")
        key = base64.b64decode(key_b64)
        if len(key) != 32:
            raise RuntimeError("GIR_DATA_KEY must be 32 bytes (base64)")
        self._aead = AESGCM(key)
        self._key_id = key_id.encode()[:16]
        self._hmac = base64.b64decode(hmac_key_b64)

    def __repr__(self) -> str:  # never show key material
        return "Crypto(<keys hidden>)"

    def encrypt(self, value: Optional[str]) -> Optional[bytes]:
        if value is None:
            return None
        nonce = os.urandom(12)
        ct = self._aead.encrypt(nonce, str(value).encode("utf-8"), self._key_id)
        return _VERSION + bytes([len(self._key_id)]) + self._key_id + nonce + ct

    def decrypt(self, blob: Optional[bytes]) -> Optional[str]:
        if blob is None:
            return None
        blob = bytes(blob)
        if blob[:1] != _VERSION:
            raise ValueError("unknown protected value format")
        n = blob[1]
        key_id = blob[2:2 + n]
        nonce = blob[2 + n:14 + n]
        return self._aead.decrypt(nonce, blob[14 + n:], key_id).decode("utf-8")

    def keyed_hash(self, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return hmac.new(self._hmac, str(value).encode("utf-8"), hashlib.sha256).hexdigest()
