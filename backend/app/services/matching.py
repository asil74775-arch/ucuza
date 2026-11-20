"""Uyumluluk kural motoru, benzerlik (alternatif bulucu) ve kişisel zevk profili."""
from __future__ import annotations

import math
import re
from datetime import datetime, timezone

# ------------------------------------------------------------------ Uyumluluk
# Aksesuar ürününün specs içinde `compat` alanı: cihazda karşılanması gereken koşullar.
#   {"ram_type": "DDR5", "ram_form_factor": "SO-DIMM", "ram_speed_mhz": {"max_of": "ram_max_speed_mhz"}}
# Koşul tipleri:
#   değer             -> cihaz specs[key] == değer (büyük/küçük harf duyarsız)
#   {"in": [..]}      -> cihaz değeri listede
#   {"lte_device": k} -> aksesuar değeri <= cihaz specs[k]   (ör. kapasite <= max RAM)
#   {"contains": v}   -> cihaz listesi/dizesi v içerir (ör. portlar içinde "USB-C")
# Uyum derecesi: "full" (hepsi), "partial" (yalnızca hız gibi yumuşak koşullar), "none".


def _eq(a, b) -> bool:
    return str(a).strip().lower() == str(b).strip().lower()


def check_compat(accessory_specs: dict, device_specs: dict) -> tuple[str, list[str]]:
    rules: dict = accessory_specs.get("compat", {})
    soft: set = set(accessory_specs.get("compat_soft", []))
    if not rules:
        return "none", ["Uyumluluk bilgisi yok"]
    notes, hard_fail, soft_fail = [], False, False
    for key, cond in rules.items():
        dv = device_specs.get(key)
        ok: bool
        if isinstance(cond, dict) and "in" in cond:
            ok = dv is not None and any(_eq(dv, c) for c in cond["in"])
        elif isinstance(cond, dict) and "lte_device" in cond:
            dk = cond["lte_device"]
            av = accessory_specs.get(key)
            dmax = device_specs.get(dk)
            ok = isinstance(av, (int, float)) and isinstance(dmax, (int, float)) and av <= dmax
            key = f"{key} ≤ {dk}"
        elif isinstance(cond, dict) and "contains" in cond:
            ok = dv is not None and str(cond["contains"]).lower() in str(dv).lower()
        else:
            ok = dv is not None and _eq(dv, cond)
        if not ok:
            if key in soft:
                soft_fail = True
                notes.append(f"Çalışır fakat {key} sınırlanır")
            else:
                hard_fail = True
                notes.append(f"{key} uyumsuz (cihaz: {dv})")
    if hard_fail:
        return "none", notes
    return ("partial" if soft_fail else "full"), notes or ["Tüm koşullar sağlanıyor"]


# ------------------------------------------------------------------ Benzerlik
def spec_vector(specs: dict, schema: list[dict], ranges: dict) -> dict[str, float]:
    vec = {}
    for f in schema:
        k = f["key"]
        v = specs.get(k)
        if f.get("type") == "number" and isinstance(v, (int, float)) and k in ranges:
            lo, hi = ranges[k]
            vec[k] = 0.5 if hi - lo < 1e-9 else (float(v) - lo) / (hi - lo)
        elif f.get("type") == "bool" and isinstance(v, bool):
            vec[k] = 1.0 if v else 0.0
        elif f.get("type") == "enum" and v is not None:
            vec[f"{k}={str(v).lower()}"] = 1.0
    return vec


def cosine(a: dict, b: dict) -> float:
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0) * b.get(k, 0) for k in keys)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    return dot / (na * nb) if na and nb else 0.0


# ------------------------------------------------------------------ Zevk profili
TASTE_TAGS = {
    "budget": "Uygun fiyatlı ürünler",
    "premium": "Premium ürünler",
    "gaming": "Oyun ekipmanları",
    "cosmetics": "Kozmetik",
    "tech": "Teknoloji",
    "home": "Ev & Yaşam",
    "fashion": "Moda",
    "sports": "Spor & Outdoor",
}
EVENT_WEIGHTS = {"view": 0.02, "like": 0.05, "search": 0.03, "cart": 0.08, "purchase": 0.15, "dismiss": -0.05}


def update_taste(weights: dict, product_tags: list[str], kind: str, price_tier: str | None) -> dict:
    """Üstel öğrenme: w = w + lr*(1-w) (olumlu) / w + lr*w (olumsuz)."""
    lr = EVENT_WEIGHTS.get(kind, 0.02)
    tags = list(product_tags) + ([price_tier] if price_tier else [])
    w = dict(weights)
    for t in tags:
        cur = w.get(t, 0.3)
        w[t] = round(cur + lr * (1 - cur) if lr > 0 else cur + lr * cur, 4)
    return w


def price_tier(price: float, category_prices: list[float]) -> str | None:
    if len(category_prices) < 3:
        return None
    s = sorted(category_prices)
    if price <= s[len(s) // 3]:
        return "budget"
    if price >= s[(2 * len(s)) // 3]:
        return "premium"
    return None


def personalize(base_score: float, product_tags: list[str], tier: str | None, weights: dict,
                alpha: float = 0.3) -> float:
    tags = list(product_tags) + ([tier] if tier else [])
    if not tags or not weights:
        return base_score
    affinity = sum(weights.get(t, 0.3) for t in tags) / len(tags)
    return round((1 - alpha) * base_score + alpha * affinity * 100, 2)


# ------------------------------------------------------------------ Doğal dil ayrıştırma (yedek)
_PRICE_RX = re.compile(r"(\d[\d.,]*)\s*(?:tl|₺|lira)?\s*(alt[ıi]|alt[ıi]nda|kadar|max|maksimum|en fazla)", re.I)
_PRICE_RX2 = re.compile(r"(?:max|maksimum|en fazla|b[uü]t[cç]e(?:m)?)\s*:?\s*(\d[\d.,]*)", re.I)


def parse_price_limit(text: str) -> float | None:
    m = _PRICE_RX.search(text) or _PRICE_RX2.search(text)
    if not m:
        return None
    raw = m.group(1).replace(".", "").replace(",", ".")
    try:
        return float(raw)
    except ValueError:
        return None


def months_ago(dt: datetime) -> float:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - dt).days / 30.0


def _stem(word: str) -> str:
    w = word.lower()
    return w[:max(4, len(w) - 2)]


def match_category(categories: list, text: str):
    """Türkçe çekim eklerine dayanıklı kategori tahmini ("kulaklığı" -> Kulaklık)."""
    t = text.lower()
    for c in categories:
        for word in [c.slug, *c.name.lower().split()]:
            if len(word) >= 3 and _stem(word) in t:
                return c
    return None


def infer_bool_filters(category, text: str) -> dict:
    """Metinde geçen evet/hayır özellikleri filtreye çevirir ("kablosuz" -> wireless=True)."""
    t = text.lower()
    out = {}
    for f in category.spec_schema or []:
        if f.get("type") == "bool" and _stem(f["label"].split()[0]) in t:
            out[f["key"]] = True
    return out
