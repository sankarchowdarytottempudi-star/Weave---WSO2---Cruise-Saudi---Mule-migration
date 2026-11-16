"""Weighted shadow model (plan section 12.9). Computed after the production decision and stored
only; it never changes the Phase 1 outcome (D11)."""
from __future__ import annotations

from app.domain.enums import ShadowLabel


def jaro_winkler(a: str | None, b: str | None, prefix_scale: float = 0.1) -> float:
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    la, lb = len(a), len(b)
    window = max(max(la, lb) // 2 - 1, 0)
    a_flags, b_flags = [False] * la, [False] * lb
    matches = 0
    for i, ch in enumerate(a):
        lo, hi = max(0, i - window), min(i + window + 1, lb)
        for j in range(lo, hi):
            if not b_flags[j] and b[j] == ch:
                a_flags[i] = b_flags[j] = True
                matches += 1
                break
    if matches == 0:
        return 0.0
    transpositions, k = 0, 0
    for i in range(la):
        if a_flags[i]:
            while not b_flags[k]:
                k += 1
            if a[i] != b[k]:
                transpositions += 1
            k += 1
    m = float(matches)
    jaro = (m / la + m / lb + (m - transpositions / 2) / m) / 3
    prefix = 0
    for x, y in zip(a[:4], b[:4]):
        if x != y:
            break
        prefix += 1
    return jaro + prefix * prefix_scale * (1 - jaro)


def shadow_score(first_a, first_b, last_a, last_b, dob_equal: bool, phone_equal: bool, email_equal: bool) -> dict:
    """Returns the raw components, the score and the label. Missing values, placeholders,
    over-shared contacts and tail-only phones must be passed in as not-equal (zero evidence)."""
    name = jaro_winkler(first_a, first_b) * 0.40 + jaro_winkler(last_a, last_b) * 0.60
    dob = 1.0 if dob_equal else 0.0
    phone = 1.0 if phone_equal else 0.0
    email = 1.0 if email_equal else 0.0
    score = round(name * 0.45 + dob * 0.30 + phone * 0.15 + email * 0.10, 4)
    if score >= 0.92:
        label = ShadowLabel.SHADOW_AUTO_CANDIDATE
    elif score >= 0.78:
        label = ShadowLabel.SHADOW_REVIEW_CANDIDATE
    else:
        label = ShadowLabel.SHADOW_SEPARATE
    return {"nameScore": round(name, 4), "dobScore": dob, "phoneScore": phone, "emailScore": email,
            "score": score, "label": label.value}
