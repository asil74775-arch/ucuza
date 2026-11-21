"""Akıllı "En İyi Seçim" puanı, F/P puanı ve güven rozetleri.

Puan bir KATEGORİ İÇİNDE göreceli hesaplanır (0-100):
  fiyat (ucuz = iyi), yorumlar (Bayes düzeltmeli AI yıldızı), özellikler
  (kategori şemasına göre normalize), dayanıklılık (kronik sorunlar),
  popülerlik (log ölçek) ve fiyat-performans dengesi.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

WEIGHTS = {
    "price": 0.15,
    "reviews": 0.25,
    "features": 0.20,
    "durability": 0.15,
    "popularity": 0.10,
    "value": 0.15,
}

BADGE_BEST_PRICE = "En İyi Fiyat"
BADGE_RELIABLE = "En Güvenilir"
BADGE_STUDENT = "Öğrenciler İçin İdeal"
BADGE_HIGH_RISK = "Yüksek Riskli"
BADGE_OVERPRICED = "Popüler Ama Aşırı Pahalı"
BADGE_CHRONIC_FREE = "Kroniksiz"
BADGE_BEST_CHOICE = "En İyi Seçim"


@dataclass
class ScoreInput:
    id: int
    price: float
    rating: float  # AI yıldız ortalaması (1-5), sahte yorumlar hariç
    rating_count: int
    specs: dict
    durability: float  # 0..1
    chronic_high: int = 0
    chronic_total: int = 0
    fake_ratio: float = 0.0
    is_chronic_free: bool = False


@dataclass
class ScoreResult:
    id: int
    best_choice: float
    fp: float
    breakdown: dict
    badges: list[str] = field(default_factory=list)


def _minmax(values: list[float]) -> tuple[float, float]:
    return (min(values), max(values)) if values else (0.0, 1.0)


def _norm(v: float, lo: float, hi: float) -> float:
    return 0.5 if hi - lo < 1e-9 else (v - lo) / (hi - lo)


def bayes_rating(avg: float, n: int, prior: float = 3.8, m: int = 15) -> float:
    """Az yorumlu ürünlerin 5 yıldızla zirveye oturmasını engeller."""
    return (avg * n + prior * m) / (n + m) if n + m else prior


def feature_score(specs: dict, schema: list[dict], ranges: dict[str, tuple[float, float]]) -> float:
    total_w, acc = 0.0, 0.0
    for f in schema:
        if f.get("type") == "number" and f.get("higher_is_better") is not None:
            v = specs.get(f["key"])
            if not isinstance(v, (int, float)) or f["key"] not in ranges:
                continue
            lo, hi = ranges[f["key"]]
            n = _norm(float(v), lo, hi)
            if not f["higher_is_better"]:
                n = 1 - n
            w = float(f.get("weight", 1))
            acc += n * w
            total_w += w
        elif f.get("type") == "bool" and f.get("higher_is_better") is not None:
            v = specs.get(f["key"])
            if isinstance(v, bool):
                w = float(f.get("weight", 0.5))
                acc += (1.0 if v == f["higher_is_better"] else 0.0) * w
                total_w += w
    return acc / total_w if total_w else 0.5


def spec_ranges(items: list[ScoreInput], schema: list[dict]) -> dict[str, tuple[float, float]]:
    ranges = {}
    for f in schema:
        if f.get("type") != "number":
            continue
        vals = [float(i.specs[f["key"]]) for i in items if isinstance(i.specs.get(f["key"]), (int, float))]
        if vals:
            ranges[f["key"]] = _minmax(vals)
    return ranges


def _percentile_rank(values: list[float], v: float) -> float:
    if len(values) <= 1:
        return 0.5
    below = sum(1 for x in values if x < v)
    return below / (len(values) - 1)


def score_category(items: list[ScoreInput], schema: list[dict]) -> list[ScoreResult]:
    if not items:
        return []
    prices = [i.price for i in items if i.price > 0]
    p_lo, p_hi = _minmax([math.log(p) for p in prices]) if prices else (0, 1)
    pops = [math.log1p(i.rating_count) for i in items]
    pop_lo, pop_hi = _minmax(pops)
    ranges = spec_ranges(items, schema)

    interim = []
    for i in items:
        price_s = 1 - _norm(math.log(i.price), p_lo, p_hi) if i.price > 0 else 0.5
        rev_s = (bayes_rating(i.rating, i.rating_count) - 1) / 4
        rev_s *= 1 - min(i.fake_ratio, 0.6) * 0.5  # sahte yorum oranı güveni düşürür
        feat_s = feature_score(i.specs, schema, ranges)
        chronic_penalty = min(0.6, 0.25 * i.chronic_high + 0.08 * max(0, i.chronic_total - i.chronic_high))
        dur_s = max(0.0, min(1.0, i.durability - chronic_penalty + (0.1 if i.is_chronic_free else 0)))
        pop_s = _norm(math.log1p(i.rating_count), pop_lo, pop_hi)
        quality = 0.45 * rev_s + 0.35 * feat_s + 0.20 * dur_s
        interim.append((i, price_s, rev_s, feat_s, dur_s, pop_s, quality))

    # Fiyat-performans = kalite / göreli fiyat (kategori içinde normalize)
    raw_value = [q / max(0.15, 1 - ps) for (_, ps, _, _, _, _, q) in interim]
    v_lo, v_hi = _minmax(raw_value)

    results: list[ScoreResult] = []
    for (i, ps, rs, fs, ds, pops_, q), rv in zip(interim, raw_value):
        value_s = _norm(rv, v_lo, v_hi)
        parts = {"price": ps, "reviews": rs, "features": fs, "durability": ds, "popularity": pops_, "value": value_s}
        total = sum(WEIGHTS[k] * v for k, v in parts.items()) * 100
        results.append(ScoreResult(
            id=i.id, best_choice=round(total, 1), fp=round(value_s * 100, 1),
            breakdown={k: round(v * 100, 1) for k, v in parts.items()} | {"quality": round(q * 100, 1)},
        ))
    assign_badges(items, results)
    return results


def assign_badges(items: list[ScoreInput], results: list[ScoreResult]) -> None:
    by_id = {i.id: i for i in items}
    prices = [i.price for i in items]
    fps = [r.fp for r in results]
    pops = [i.rating_count for i in items]
    n = len(items)

    trusted = [r for r in results if by_id[r.id].rating >= 3.5 and by_id[r.id].fake_ratio < 0.35]
    if trusted:
        cheapest = min(trusted, key=lambda r: by_id[r.id].price)
        cheapest.badges.append(BADGE_BEST_PRICE)
        top = max(results, key=lambda r: r.best_choice)
        top.badges.append(BADGE_BEST_CHOICE)

    for r in results:
        i = by_id[r.id]
        price_pct = _percentile_rank(prices, i.price)
        fp_pct = _percentile_rank(fps, r.fp)
        pop_pct = _percentile_rank(pops, i.rating_count)
        if i.is_chronic_free:
            r.badges.append(BADGE_CHRONIC_FREE)
        if (i.rating >= 4.2 and i.chronic_high == 0 and i.fake_ratio < 0.2
                and r.breakdown["durability"] >= 65):
            r.badges.append(BADGE_RELIABLE)
        if n >= 3 and price_pct <= 0.45 and fp_pct >= 0.6 and i.rating >= 3.8:
            r.badges.append(BADGE_STUDENT)
        if i.chronic_high >= 1 or i.fake_ratio >= 0.35 or (i.rating_count >= 10 and i.rating < 3.0):
            r.badges.append(BADGE_HIGH_RISK)
        if n >= 3 and pop_pct >= 0.7 and price_pct >= 0.7 and fp_pct <= 0.4:
            r.badges.append(BADGE_OVERPRICED)


# Her rozetin NESNEL dayanağı — ürün sayfasında rozete dokununca gösterilir.
# Dil bilinçli olarak "kullanıcı bildirimlerine göre" şeklindedir: bir kanaat/iddia değil,
# ölçülebilir verinin özetidir (marka itirazlarına karşı en önemli koruma).
BADGE_BASIS = {
    BADGE_BEST_PRICE: "Kategorideki, puanı 3,5 ve üzeri olan ürünler arasında şu anki en düşük fiyat.",
    BADGE_RELIABLE: "Puanı 4,2 ve üzeri, kullanıcıların bildirdiği yüksek önemde kronik sorunu yok ve "
                    "şüpheli yorum oranı düşük.",
    BADGE_STUDENT: "Kategorideki ürünlerin ucuz yarısında ve fiyat/performans puanı üst sıralarda.",
    BADGE_HIGH_RISK: "Kullanıcı bildirimlerine göre: yüksek oranda tekrarlayan bir sorun bildirilmiş, şüpheli yorum "
                     "oranı yüksek veya kullanıcı puanı düşük. Bu bir kalite tespiti değil, kullanıcı verisinin özetidir.",
    BADGE_OVERPRICED: "Kategoride en çok puanlanan ve en pahalı ürünler arasında, ancak fiyat/performans puanı "
                      "kategorinin alt yarısında.",
    BADGE_CHRONIC_FREE: "Yeterli sayıda kullanıcı yorumunda, birden çok aya yayılan tekrarlayan bir sorun bildirilmemiş.",
    BADGE_BEST_CHOICE: "Kategorideki En İyi Seçim puanı en yüksek ürün.",
}

DISCLAIMER = ("Puanlar, rozetler ve yapay zeka değerlendirmeleri; diğer platformlardaki puanlar ve BinÖlçBirAl "
              "kullanıcılarının yorumlarından otomatik olarak hesaplanır. Bilgilendirme amaçlıdır, hata içerebilir; "
              "ürün veya marka hakkında bir iddia ya da satın alma tavsiyesi değildir. Hatalı olduğunu düşündüğünüz "
              "bilgiler için itiraz edebilirsiniz.")
