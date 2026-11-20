"""Kronik Sorun tespiti.

Bir şikayet anahtarı KRONİK sayılır eğer:
  - yorumların en az %5'inde geçiyorsa (chronic_min_share) ve
  - en az 3 farklı ayda tekrar ediyorsa (chronic_min_months).
Sadece pay eşiğini geçen ama zamana yayılmayanlar "sık şikayet" olarak listelenir.
Hiç kronik sorunu olmayan ve yeterli yorum sayısına ulaşan ürün "Kroniksiz" olur.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class ComplaintMention:
    key: str
    label: str
    posted_at: datetime


@dataclass
class IssueResult:
    key: str
    title: str
    mention_count: int
    share: float
    months_active: int
    severity: str
    is_chronic: bool
    first_seen: datetime
    last_seen: datetime
    timeline: dict = field(default_factory=dict)


def detect(mentions: list[ComplaintMention], total_reviews: int, min_share: float = 0.05,
           min_months: int = 3, min_mentions: int = 3) -> list[IssueResult]:
    groups: dict[str, list[ComplaintMention]] = defaultdict(list)
    for m in mentions:
        groups[m.key].append(m)
    results = []
    for key, ms in groups.items():
        count = len(ms)
        share = count / max(1, total_reviews)
        if count < min_mentions or share < min_share * 0.6:
            continue
        timeline: dict[str, int] = defaultdict(int)
        for m in ms:
            timeline[m.posted_at.strftime("%Y-%m")] += 1
        months = len(timeline)
        is_chronic = share >= min_share and months >= min_months
        severity = "high" if share >= 0.15 else "medium" if share >= 0.08 else "low"
        label = max(set(m.label for m in ms), key=lambda lbl: sum(1 for m in ms if m.label == lbl))
        results.append(IssueResult(
            key=key, title=label, mention_count=count, share=round(share, 3), months_active=months,
            severity=severity, is_chronic=is_chronic,
            first_seen=min(m.posted_at for m in ms), last_seen=max(m.posted_at for m in ms),
            timeline=dict(sorted(timeline.items())),
        ))
    return sorted(results, key=lambda r: (-r.is_chronic, -r.share))


def is_chronic_free(issues: list[IssueResult], total_reviews: int, min_reviews: int = 20) -> bool:
    return total_reviews >= min_reviews and not any(i.is_chronic for i in issues)
