"""Global ID / Loyalty ID pair allocation (plan sections 9.1, 9.3).

CLIENT-APPROVED logic, ported exactly from the existing Mule application identity-support-exp-api
(flows GET /generateGuestId and GET /generateLoyaltId, called by guest-identity-proc-api):

* Global ID  = ULID (de.huxhorn.sulky.ulid 8.3.0, ULID.nextULID()): 48-bit millisecond timestamp
  + 80 random bits, Crockford base32, upper case, 26 characters.
* Loyalty ID = "12" + randomInt(10000000) zero-padded to 7 digits + 1 check digit (10 digits).
  The check digit is the Mule DataWeave function luhnCheckDigit, reproduced bit for bit: digits of
  the 9-digit base are reversed, digits at ODD positions (1, 3, ...) are doubled (minus 9 if > 9),
  check = (10 - sum mod 10) mod 10. NOTE: textbook Luhn doubles the even positions of the reversed
  payload, so these IDs do not pass a standard Luhn validator - kept as-is because existing CRM IDs
  were generated this way; validate with aroya_check_digit() only.
* The Mule generators perform NO uniqueness check. This port adds one: a candidate pair whose keyed
  hash already exists in identity_projection is discarded and regenerated (bounded attempts), and
  UNIQUE constraints on the hashes are the final backstop. IDs that exist only in CRM and are not
  yet indexed can be checked only after the baseline load (iteration 1) - see README.
* Existing-ID eligibility rule (guest_identity-impl.xml): an existing pair is reusable only when
  BOTH IDs are present and the Global ID does not contain "-" (legacy UUID-form IDs).

A reservation belongs to exactly one decision (reserved_by_decision_id is UNIQUE), so a retry or
timeout never generates a second pair. SequencePairAllocator is kept for diagnostics/tests."""
from __future__ import annotations

import secrets
import time
from typing import Callable, Optional, Protocol

from sqlalchemy import or_, select, text
from sqlalchemy.engine import Connection

from app.config import Settings
from app.db.crypto import Crypto
from app.db.models import identity_projection as ip
from app.observability import metrics

_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


class PairAllocator(Protocol):
    def allocate(self, conn: Connection) -> tuple[str, str]: ...


class PairAllocationError(RuntimeError):
    pass


def ulid(now_ms: Optional[int] = None, randomness: Optional[int] = None) -> str:
    ts = int(time.time() * 1000) if now_ms is None else now_ms
    rnd = secrets.randbits(80) if randomness is None else randomness
    value = ((ts & ((1 << 48) - 1)) << 80) | (rnd & ((1 << 80) - 1))
    return "".join(_CROCKFORD[(value >> (5 * i)) & 31] for i in range(25, -1, -1))


def aroya_check_digit(base: str) -> str:
    """Mule luhnCheckDigit, exactly (see module docstring)."""
    total = 0
    for index, digit in enumerate(int(c) for c in reversed(base)):
        if index % 2 == 1:
            digit *= 2
            if digit > 9:
                digit -= 9
        total += digit
    return str((10 - total % 10) % 10)


def loyalty_id(prefix: str = "12", digits: int = 7, rand: Optional[Callable[[int], int]] = None) -> str:
    n = (rand or secrets.randbelow)(10 ** digits)
    base = prefix + str(n).zfill(digits)
    return base + aroya_check_digit(base)


def is_valid_loyalty_id(value: str, prefix: str = "12", digits: int = 7) -> bool:
    return (len(value) == len(prefix) + digits + 1 and value.isdigit() and value.startswith(prefix)
            and aroya_check_digit(value[:-1]) == value[-1])


def is_reusable_pair(global_id: Optional[str], loyalty_id_value: Optional[str]) -> bool:
    """Mule eligibility: both present and the Global ID is not a legacy '-' form."""
    return bool(global_id) and bool(loyalty_id_value) and "-" not in global_id


class MuleCompatPairAllocator:
    def __init__(self, settings: Settings, crypto: Crypto,
                 global_gen: Callable[[], str] = ulid, loyalty_gen: Optional[Callable[[], str]] = None):
        self.s, self.crypto, self._g = settings, crypto, global_gen
        self._l = loyalty_gen or (lambda: loyalty_id(settings.loyalty_id_prefix, settings.loyalty_id_random_digits))

    def _taken(self, conn: Connection, g: str, l: str) -> bool:
        return conn.execute(select(ip.c.identity_id).where(or_(
            ip.c.global_id_hash == self.crypto.keyed_hash(g),
            ip.c.loyalty_id_hash == self.crypto.keyed_hash(l))).limit(1)).first() is not None

    def allocate(self, conn: Connection) -> tuple[str, str]:
        for _ in range(max(1, self.s.id_allocation_max_attempts)):
            g, l = self._g(), self._l()
            if not self._taken(conn, g, l):
                return g, l
            metrics.PAIR_CONFLICTS.inc()
        raise PairAllocationError("no unique Global/Loyalty pair after the configured attempts")


class SequencePairAllocator:
    def __init__(self, settings: Settings):
        self._g, self._l = settings.global_id_format, settings.loyalty_id_format

    def allocate(self, conn: Connection) -> tuple[str, str]:
        n = conn.execute(text("SELECT nextval('gir_pair_seq')")).scalar_one()
        return self._g.format(n=n), self._l.format(n=n)


def build_allocator(settings: Settings, crypto: Crypto) -> PairAllocator:
    if settings.id_allocation_strategy.upper() == "SEQUENCE":
        return SequencePairAllocator(settings)
    return MuleCompatPairAllocator(settings, crypto)
