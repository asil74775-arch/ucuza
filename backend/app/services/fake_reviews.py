"""Sahte Yorum Dedektörü.

İki katman:
 1) Deterministik sinyaller (her zaman çalışır): kopya/benzer metin, sponsor
    ifadeleri, aşırı kısa genel övgü, aynı gün yığılma, aşırı ünlem/büyük harf,
    puan-metin çelişkisi.
 2) Gemini sınıflandırması (anahtar varsa): olasılık + gerekçe.
Son olasılık = max(kural, 0.4*kural + 0.6*AI). Eşik üstü yorumlar gizlenir.
"""
from __future__ import annotations

import hashlib
import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime

SPONSOR_PATTERNS = [
    r"\bsponsor", r"#ad\b", r"#reklam", r"i[sş]birli[gğ]i", r"hediye (olarak )?(g[oö]nderildi|edildi)",
    r"[uü]cretsiz (olarak )?(g[oö]nderildi|verildi)", r"kupon kod", r"indirim kod", r"affiliate",
    r"bu [uü]r[uü]n bana .* taraf[iı]ndan", r"free product", r"in exchange for",
]
GENERIC_PRAISE = [
    "çok güzel", "harika ürün", "tavsiye ederim", "süper", "mükemmel", "çok iyi", "beğendim",
    "great product", "highly recommend", "love it", "best ever",
]


@dataclass
class ReviewLite:
    id: int
    text: str
    rating: float | None
    posted_at: datetime
    author: str = ""


@dataclass
class FakeVerdict:
    id: int
    probability: float
    reasons: list[str] = field(default_factory=list)


def normalize(text: str) -> str:
    t = text.lower()
    t = re.sub(r"[^\wçğıöşü\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def content_hash(text: str) -> str:
    return hashlib.sha256(normalize(text).encode()).hexdigest()


def shingles(text: str, k: int = 3) -> set[str]:
    words = normalize(text).split()
    if len(words) < k:
        return {" ".join(words)} if words else set()
    return {" ".join(words[i:i + k]) for i in range(len(words) - k + 1)}


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


def heuristic_scores(reviews: list[ReviewLite]) -> list[FakeVerdict]:
    sh = {r.id: shingles(r.text) for r in reviews}
    day_counts = Counter(r.posted_at.date() for r in reviews)
    avg_per_day = len(reviews) / max(1, len(day_counts))
    author_counts = Counter(r.author.lower() for r in reviews if r.author)
    out = []
    for r in reviews:
        score, reasons = 0.0, []
        norm = normalize(r.text)
        # 1) Kopya / neredeyse kopya
        best = max((jaccard(sh[r.id], sh[o.id]) for o in reviews if o.id != r.id), default=0)
        if best >= 0.85:
            score += 0.6
            reasons.append("Başka bir yorumla neredeyse birebir aynı (kopyalanmış)")
        elif best >= 0.6:
            score += 0.3
            reasons.append("Başka yorumlarla yüksek metin benzerliği")
        # 2) Sponsorlu
        if any(re.search(p, norm) for p in SPONSOR_PATTERNS):
            score += 0.55
            reasons.append("Sponsorlu/hediye ürün ifadesi içeriyor")
        # 3) Kısa, genel, aşırı olumlu
        words = norm.split()
        if r.rating and r.rating >= 5 and len(words) <= 6 and any(g in norm for g in GENERIC_PRAISE):
            score += 0.25
            reasons.append("Çok kısa ve genel övgü")
        # 4) Aynı gün yorum yığılması
        if day_counts[r.posted_at.date()] >= max(5, 4 * avg_per_day):
            score += 0.2
            reasons.append("Aynı gün olağandışı yorum yığılması")
        # 5) Ünlem / büyük harf
        if r.text.count("!") >= 5 or (len(r.text) > 20 and sum(c.isupper() for c in r.text) / len(r.text) > 0.5):
            score += 0.1
            reasons.append("Aşırı ünlem veya büyük harf")
        # 6) Aynı yazar çok sayıda yorum
        if r.author and author_counts[r.author.lower()] >= 3:
            score += 0.2
            reasons.append("Aynı hesaptan çok sayıda yorum")
        out.append(FakeVerdict(r.id, round(min(score, 0.99), 2), reasons))
    return out


AI_SCHEMA = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "id": {"type": "INTEGER"},
            "stars": {"type": "NUMBER", "description": "Metne göre 1-5 arası yıldız"},
            "sentiment": {"type": "STRING", "enum": ["pos", "neu", "neg"]},
            "fake_probability": {"type": "NUMBER"},
            "fake_reason": {"type": "STRING"},
            "complaints": {
                "type": "ARRAY",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "key": {"type": "STRING", "description": "snake_case İngilizce kalıcı anahtar, örn battery_drain"},
                        "label": {"type": "STRING", "description": "Türkçe kısa başlık"},
                    },
                    "required": ["key", "label"],
                },
            },
        },
        "required": ["id", "stars", "sentiment", "fake_probability", "complaints"],
    },
}

AI_SYSTEM = (
    "Sen bir e-ticaret yorum analistisin. Her yorum için: metnin gerçek duygusuna göre 1-5 yıldız ver, "
    "sahte/kopyalanmış/sponsorlu/bot olma olasılığını 0-1 arası tahmin et ve gerekçesini Türkçe kısa yaz, "
    "ürüne dair somut şikayetleri (ör. pil çabuk bitiyor, ekran yanması, menteşe kırılması) kalıcı "
    "snake_case anahtarlarla çıkar. Aynı sorun için her zaman aynı anahtarı kullan."
)


def combine(rule: float, ai: float | None) -> float:
    if ai is None:
        return rule
    return round(max(rule, 0.4 * rule + 0.6 * ai), 2)
