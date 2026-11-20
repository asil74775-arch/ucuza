from datetime import datetime, timedelta, timezone

from app.services import chronic, fake_reviews, matching, scoring

NOW = datetime.now(timezone.utc)


def test_best_choice_and_badges():
    schema = [{"key": "battery", "label": "Pil", "type": "number", "higher_is_better": True}]
    items = [
        scoring.ScoreInput(1, 1000, 4.6, 200, {"battery": 40}, 0.9, is_chronic_free=True),
        scoring.ScoreInput(2, 5000, 4.4, 900, {"battery": 30}, 0.8),
        scoring.ScoreInput(3, 1200, 2.4, 50, {"battery": 20}, 0.4, chronic_high=1, fake_ratio=0.4),
        scoring.ScoreInput(4, 6000, 4.0, 1000, {"battery": 20}, 0.7),
    ]
    res = {r.id: r for r in scoring.score_category(items, schema)}
    assert res[1].best_choice > res[3].best_choice
    assert scoring.BADGE_BEST_PRICE in res[1].badges
    assert scoring.BADGE_CHRONIC_FREE in res[1].badges
    assert scoring.BADGE_HIGH_RISK in res[3].badges
    assert scoring.BADGE_OVERPRICED in res[4].badges


def test_fake_detector_flags_copies_and_sponsored():
    rs = [
        fake_reviews.ReviewLite(1, "Harika ürün çok beğendim herkese tavsiye ederim gerçekten", 5, NOW),
        fake_reviews.ReviewLite(2, "Harika ürün çok beğendim herkese tavsiye ederim gerçekten!", 5, NOW),
        fake_reviews.ReviewLite(3, "Bu ürün marka tarafından hediye olarak gönderildi, mükemmel", 5, NOW),
        fake_reviews.ReviewLite(4, "Pil ömrü iyi ama kamera gece biraz zayıf kalıyor, fiyatına göre iyi.", 4,
                                NOW - timedelta(days=40)),
    ]
    v = {x.id: x for x in fake_reviews.heuristic_scores(rs)}
    assert v[1].probability >= 0.6 and v[3].probability >= 0.5
    assert v[4].probability < 0.3


def test_chronic_detection():
    ms = [chronic.ComplaintMention("battery_drain", "Pil çabuk bitiyor", NOW - timedelta(days=30 * m))
          for m in range(5) for _ in range(3)]
    issues = chronic.detect(ms, total_reviews=100)
    assert issues[0].is_chronic and issues[0].months_active == 5
    assert not chronic.is_chronic_free(issues, 100)
    assert chronic.is_chronic_free([], 50)


def test_compat_ram():
    loq = {"ram_type": "DDR5", "ram_form_factor": "SO-DIMM", "ram_max_gb": 32, "ram_max_speed_mhz": 4800}
    fast = {"capacity_gb": 16, "speed_mhz": 5600, "compat": {"ram_type": "DDR5", "ram_form_factor": "SO-DIMM",
            "capacity_gb": {"lte_device": "ram_max_gb"}, "speed_mhz": {"lte_device": "ram_max_speed_mhz"}},
            "compat_soft": ["speed_mhz ≤ ram_max_speed_mhz"]}
    ddr4 = {"capacity_gb": 16, "compat": {"ram_type": "DDR4", "ram_form_factor": "SO-DIMM"}}
    assert matching.check_compat(fast, loq)[0] == "partial"
    assert matching.check_compat(ddr4, loq)[0] == "none"


def test_price_parse_and_taste():
    assert matching.parse_price_limit("Bana 1500 TL altındaki en iyi kablosuz kulaklığı bul") == 1500
    assert matching.parse_price_limit("bütçem 25.000") == 25000
    w = matching.update_taste({"gaming": 0.3}, ["gaming"], "purchase", "budget")
    assert w["gaming"] > 0.3 and w["budget"] > 0.3
    assert matching.personalize(50, ["gaming"], None, {"gaming": 1.0}) > 50
