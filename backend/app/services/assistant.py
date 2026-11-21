"""Uygulama içi yapay zeka asistanları.

Tüm modlar kataloğu ve "En İyi Seçim" sıralamasını GERÇEK veri olarak kullanır:
Gemini fonksiyon çağırma ile araçları tetikler, araç sonuçları veritabanından gelir.
Böylece model ürün/fiyat uydurmaz. Anahtar yoksa kural tabanlı yanıt üretilir.
"""
from __future__ import annotations

import json
import logging
import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import AiMessage, AiSession, CartItem, Category, Product, Project, User
from . import catalog, matching, pipeline
from .gemini import GeminiError, ai_ok, gemini

log = logging.getLogger("dengi.assistant")

SYSTEM = (
    "Sen Dengi'nin alışveriş asistanısın. Türkçe, samimi ve net konuş. Ürün, fiyat veya özellik "
    "UYDURMA: her zaman araçları kullanarak veritabanındaki gerçek ürünleri ve 'En İyi Seçim' "
    "sıralamasını getir. 'Şu özelliği istiyorsan şunu al' tarzında, kullanıcının ihtiyacına göre "
    "somut öneri ver; her öneride ürün adını, fiyatını ve neden önerdiğini belirt. Kronik sorunları ve "
    "Yüksek Riskli rozetlerini mutlaka uyar; bunları her zaman 'kullanıcıların bildirdiğine göre' diye anlat, "
    "marka veya ürün hakkında kesin hüküm, hakaret ya da doğrulanmamış iddia kurma. Fiyatlar TL'dir."
)

TOOLS = [
    {"name": "list_categories", "description": "Kategorileri ve teknik özellik şemalarını listeler",
     "parameters": {"type": "OBJECT", "properties": {}}},
    {"name": "search_products",
     "description": "Kategoride ürün arar ve En İyi Seçim puanına (veya başka sıralamaya) göre döner",
     "parameters": {"type": "OBJECT", "properties": {
         "query": {"type": "STRING"}, "category_slug": {"type": "STRING"},
         "max_price": {"type": "NUMBER"}, "min_price": {"type": "NUMBER"},
         "sort": {"type": "STRING", "enum": ["best", "cheapest", "expensive", "fp", "rating", "popular"]},
         "spec_filters_json": {"type": "STRING", "description": 'Örn {"ram_gb":{"min":16},"anc":true}'},
         "limit": {"type": "INTEGER"}}}},
    {"name": "get_product", "description": "Ürün detayı, özellikler, kronik sorunlar, fiyat istatistiği",
     "parameters": {"type": "OBJECT", "properties": {"product_id": {"type": "INTEGER"}}, "required": ["product_id"]}},
    {"name": "find_alternatives", "description": "Benzer özellikli daha ucuz alternatifler",
     "parameters": {"type": "OBJECT", "properties": {"product_id": {"type": "INTEGER"}}, "required": ["product_id"]}},
    {"name": "compare_products", "description": "İki ürünü kategori kategori karşılaştırır",
     "parameters": {"type": "OBJECT", "properties": {"a_id": {"type": "INTEGER"}, "b_id": {"type": "INTEGER"}},
                    "required": ["a_id", "b_id"]}},
    {"name": "discover_online", "description": "Sistemde olmayan bir ürünü internetteki kaynaklarda bulup ekler",
     "parameters": {"type": "OBJECT", "properties": {"query": {"type": "STRING"}}, "required": ["query"]}},
    {"name": "add_to_cart", "description": "Ürünü kullanıcının sepetine ekler (yalnızca kullanıcı isterse)",
     "parameters": {"type": "OBJECT", "properties": {"product_id": {"type": "INTEGER"}, "quantity": {"type": "INTEGER"}},
                    "required": ["product_id"]}},
]


class ToolBox:
    def __init__(self, db: AsyncSession, user: User):
        self.db, self.user = db, user
        self.cards: list[dict] = []

    async def _cat_id(self, slug: str | None) -> int | None:
        if not slug:
            return None
        c = await self.db.scalar(select(Category).where(Category.slug == slug))
        return c.id if c else None

    async def run(self, name: str, args: dict) -> dict:
        db = self.db
        if name == "list_categories":
            cats = (await db.scalars(select(Category))).all()
            return {"categories": [{"slug": c.slug, "name": c.name,
                                    "specs": [f"{f['key']} ({f['label']})" for f in c.spec_schema or []]} for c in cats]}
        if name == "search_products":
            filters = {}
            if args.get("spec_filters_json"):
                try:
                    filters = json.loads(args["spec_filters_json"])
                except json.JSONDecodeError:
                    filters = {}
            res = await catalog.search(db, category_id=await self._cat_id(args.get("category_slug")),
                                       q=args.get("query"), sort=args.get("sort", "best"),
                                       min_price=args.get("min_price"), max_price=args.get("max_price"),
                                       spec_filters=filters, user=self.user, limit=int(args.get("limit", 8)))
            self.cards.extend(res[:5])
            return {"results": res}
        if name == "get_product":
            p = await db.get(Product, int(args["product_id"]))
            if not p:
                return {"error": "bulunamadı"}
            issues = await catalog.chronic_list(db, p.id)
            return {**catalog.card(p), "specs": p.specs, "score_breakdown": p.score_breakdown,
                    "price_stats": await catalog.price_stats(db, p.id),
                    "issues": [{"title": i.title, "chronic": i.is_chronic, "severity": i.severity} for i in issues]}
        if name == "find_alternatives":
            p = await db.get(Product, int(args["product_id"]))
            alts = await catalog.alternatives(db, p) if p else []
            self.cards.extend(alts[:3])
            return {"alternatives": alts}
        if name == "compare_products":
            a, b = await db.get(Product, int(args["a_id"])), await db.get(Product, int(args["b_id"]))
            return await catalog.duel(db, a, b) if a and b else {"error": "ürün yok"}
        if name == "discover_online":
            found = await pipeline.discover(db, args["query"])
            cards = [catalog.card(p) for p in found]
            self.cards.extend(cards)
            return {"added": cards}
        if name == "add_to_cart":
            db.add(CartItem(user_id=self.user.id, product_id=int(args["product_id"]),
                            quantity=int(args.get("quantity", 1))))
            await db.commit()
            return {"ok": True}
        return {"error": f"bilinmeyen araç {name}"}


async def run_tool_loop(db: AsyncSession, user: User, history: list[dict], system: str = SYSTEM,
                        max_steps: int = 6) -> tuple[str, list[dict]]:
    box = ToolBox(db, user)
    contents = list(history)
    for _ in range(max_steps):
        resp = await gemini.generate(contents, system=system, tools=TOOLS)
        parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
        calls = [p["functionCall"] for p in parts if "functionCall" in p]
        if not calls:
            return gemini.text_of(resp), box.cards
        contents.append({"role": "model", "parts": parts})
        responses = []
        for c in calls:
            result = await box.run(c["name"], c.get("args", {}) or {})
            responses.append({"functionResponse": {"name": c["name"], "response": {"result": result}}})
        contents.append({"role": "user", "parts": responses})
    return "Biraz karmaşık bir istek oldu, lütfen biraz daha net anlatır mısın?", box.cards


# ------------------------------------------------------------------ Genel sohbet
async def chat(db: AsyncSession, user: User, session: AiSession, text: str) -> AiMessage:
    db.add(AiMessage(session_id=session.id, role="user", text=text))
    await db.commit()
    past = (await db.scalars(select(AiMessage).where(AiMessage.session_id == session.id)
                             .order_by(AiMessage.id.desc()).limit(20))).all()[::-1]
    history = [{"role": m.role, "parts": [{"text": m.text}]} for m in past]
    taste = await catalog.taste_of(db, user)
    system = SYSTEM + (f"\nKullanıcının zevk profili (0-1): {json.dumps(taste, ensure_ascii=False)}" if taste else "")
    if ai_ok(user):
        try:
            reply, cards = await run_tool_loop(db, user, history, system)
        except GeminiError as e:
            log.warning("sohbet hatası %s", e)
            reply, cards = await _fallback_chat(db, user, text)
    else:
        reply, cards = await _fallback_chat(db, user, text)
    msg = AiMessage(session_id=session.id, role="model", text=reply, data={"cards": cards[:6]})
    db.add(msg)
    await db.commit()
    return msg


async def _fallback_chat(db: AsyncSession, user: User, text: str) -> tuple[str, list[dict]]:
    limit = matching.parse_price_limit(text)
    cats = (await db.scalars(select(Category))).all()
    cat = matching.match_category(cats, text)
    res = await catalog.search(db, category_id=cat.id if cat else None, q=None if cat else _keywords(text),
                               max_price=limit, spec_filters=matching.infer_bool_filters(cat, text) if cat else None,
                               user=user, limit=3)
    if not res:
        return "Bu isteğe uygun ürün bulamadım. Kategori veya bütçe belirterek tekrar dener misin?", []
    lines = [f"• {r['name']} — {r['price']:.0f} TL (En İyi Seçim: {r['best_choice_score']:.0f})" for r in res]
    return "İhtiyacına göre En İyi Seçim sıralamasından öneriler:\n" + "\n".join(lines), res


def _keywords(text: str) -> str | None:
    stop = {"bana", "bul", "en", "iyi", "için", "altında", "altındaki", "tl", "bir", "ne", "almalıyım", "öner"}
    words = [w for w in re.findall(r"[\wçğıöşü]+", text.lower()) if w not in stop and not w.isdigit()]
    return " ".join(words[:2]) or None


# ------------------------------------------------------------------ Satın Almalı Mıyım?
VERDICT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "verdict": {"type": "STRING", "enum": ["AL", "ALMA", "BEKLE"]},
        "headline": {"type": "STRING"},
        "reasons": {"type": "ARRAY", "items": {"type": "STRING"}},
        "fit_score": {"type": "NUMBER", "description": "İhtiyaca uygunluk 0-100"},
        "suggestion": {"type": "STRING"},
    },
    "required": ["verdict", "headline", "reasons", "fit_score"],
}
VERDICT_LABEL = {"AL": "Satın Al", "ALMA": "Satın Alma", "BEKLE": "Bekle"}


async def should_buy(db: AsyncSession, user: User, product: Product, budget: float | None, needs: str) -> dict:
    sig = await catalog.buy_signals(db, product, budget)
    result = {"verdict": sig["verdict"], "headline": "", "reasons": sig["signals"], "fit_score": None,
              "suggestion": "", "signals": sig}
    if ai_ok(user):
        try:
            ai = await gemini.json(
                f"Ürün: {json.dumps(catalog.card(product), ensure_ascii=False)}\n"
                f"Özellikler: {json.dumps(product.specs, ensure_ascii=False)}\n"
                f"Bütçe: {budget or 'belirtilmedi'} TL\nİhtiyaçlar: {needs}\n"
                f"Analiz sinyalleri: {json.dumps(sig, ensure_ascii=False, default=str)}\n"
                "Kullanıcıya net bir karar ver: AL, ALMA veya BEKLE. Sinyallerdeki ALMA kararını (bütçe aşımı, "
                "ciddi kronik sorun, yüksek risk) asla AL'a çevirme. Ürün ihtiyaçları karşılamıyorsa ALMA de ve "
                "alternatif öner.", VERDICT_SCHEMA, system=SYSTEM)
            if sig["verdict"] == "ALMA" and ai["verdict"] == "AL":
                ai["verdict"] = "ALMA"
            result.update({k: ai.get(k, result.get(k)) for k in ("verdict", "headline", "reasons", "fit_score", "suggestion")})
        except GeminiError as e:
            log.warning("should_buy AI hatası %s", e)
    if not result["headline"]:
        result["headline"] = f"{VERDICT_LABEL[result['verdict']]}: {product.name}"
    result["verdict_label"] = VERDICT_LABEL[result["verdict"]]
    result["disclaimer"] = ("Bu öneri, fiyat geçmişi ve kullanıcı verilerinden otomatik üretilmiştir; "
                            "kesin bir tavsiye değildir. Son karar size aittir.")
    return result


# ------------------------------------------------------------------ Alışveriş Görevi
MISSION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "category_slug": {"type": "STRING"},
        "keywords": {"type": "STRING"},
        "max_price": {"type": "NUMBER", "nullable": True},
        "min_price": {"type": "NUMBER", "nullable": True},
        "spec_filters_json": {"type": "STRING"},
        "priorities": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["category_slug"],
}
STRENGTH_LABELS = {
    "price": "En uygun fiyat", "reviews": "Kullanıcılar çok memnun", "features": "En güçlü teknik özellikler",
    "durability": "Dayanıklılığı yüksek, kronik sorun yok", "popularity": "En çok tercih edilen",
    "value": "En iyi fiyat/performans",
}


async def mission(db: AsyncSession, user: User, text: str) -> dict:
    cats = (await db.scalars(select(Category))).all()
    plan = {"category_slug": None, "keywords": _keywords(text), "max_price": matching.parse_price_limit(text),
            "spec_filters_json": "{}", "priorities": []}
    if ai_ok(user):
        try:
            plan.update(await gemini.json(
                f"İstek: {text}\nKategoriler ve özellik anahtarları: "
                f"{[{'slug': c.slug, 'name': c.name, 'specs': [f['key'] for f in c.spec_schema or []]} for c in cats]}\n"
                "İsteği arama planına dönüştür. Özellik filtrelerini yalnızca şemadaki anahtarlarla yaz.",
                MISSION_SCHEMA))
        except GeminiError:
            pass
    cat = next((c for c in cats if c.slug == plan.get("category_slug")), None)
    if not cat:
        cat = matching.match_category(cats, text)
    try:
        filters = json.loads(plan.get("spec_filters_json") or "{}")
    except json.JSONDecodeError:
        filters = {}
    if cat and not filters and not ai_ok(user):
        filters = matching.infer_bool_filters(cat, text)
    kw = None if cat else plan.get("keywords")
    res = await catalog.search(db, category_id=cat.id if cat else None, q=kw, max_price=plan.get("max_price"),
                               min_price=plan.get("min_price"), spec_filters=filters, user=user, limit=20)
    if len(res) < 3:  # yeterli sonuç yoksa internette ara ve ekle
        await pipeline.discover(db, text if not cat else f"{plan.get('keywords') or ''} {cat.name}")
        res = await catalog.search(db, category_id=cat.id if cat else None, q=kw, max_price=plan.get("max_price"),
                                   spec_filters=filters, user=user, limit=20)
    res = [r for r in res if "Yüksek Riskli" not in r["badges"]] or res
    top = res[:3]
    used: set[str] = set()
    for r in top:
        p = await db.get(Product, r["id"])
        ranked = sorted((p.score_breakdown or {}).items(), key=lambda kv: -kv[1])
        key = next((k for k, _ in ranked if k in STRENGTH_LABELS and k not in used), "value")
        used.add(key)
        r["strength"] = STRENGTH_LABELS[key]
    summary = ""
    if ai_ok(user) and top:
        try:
            summary = await gemini.text(
                f"Kullanıcının isteği: {text}\nKarşılaştırılan en iyi 3 ürün: {json.dumps(top, ensure_ascii=False)}\n"
                "Her ürünün güçlü yönünü tek cümleyle yaz ve kimin hangisini seçmesi gerektiğini söyle. Kısa ol.",
                system=SYSTEM)
        except GeminiError:
            pass
    return {"plan": plan, "compared": len(res), "top3": top,
            "summary": summary or "En iyi 3 seçenek, En İyi Seçim puanına ve her birinin öne çıkan yönüne göre listelendi."}


# ------------------------------------------------------------------ Proje Asistanı
PROJECT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "items": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "name": {"type": "STRING"}, "search_query": {"type": "STRING"}, "category_slug": {"type": "STRING"},
            "quantity": {"type": "INTEGER"}, "priority": {"type": "STRING", "enum": ["must", "nice"]},
            "why": {"type": "STRING"}}, "required": ["name", "search_query", "quantity", "priority"]}},
        "tips": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["items"],
}


async def project_plan(db: AsyncSession, user: User, title: str, description: str, budget: float | None,
                       add_to_cart: bool = True) -> dict:
    cats = (await db.scalars(select(Category))).all()
    if ai_ok(user):
        try:
            plan = await gemini.json(
                f"Proje: {title}\nAçıklama: {description}\nBütçe: {budget or 'belirtilmedi'} TL\n"
                f"Kategoriler: {[c.slug for c in cats]}\nBu proje için gereken tüm eşyaları çıkar.",
                PROJECT_SCHEMA, system=SYSTEM)
        except GeminiError:
            plan = {"items": [{"name": title, "search_query": title, "quantity": 1, "priority": "must"}]}
    else:
        plan = {"items": [{"name": w.strip(), "search_query": w.strip(), "quantity": 1, "priority": "must"}
                          for w in re.split(r"[,\n]", description) if w.strip()]}
    project = Project(user_id=user.id, title=title, description=description, budget=budget, plan=plan)
    db.add(project)
    await db.flush()

    # En uygun (ucuz ama güvenilir) ürünü seç; önce "must" kalemler, bütçeyi aşma
    chosen, total, missing = [], 0.0, []
    items = sorted(plan["items"], key=lambda i: i.get("priority") != "must")
    for it in items:
        cat = next((c for c in cats if c.slug == it.get("category_slug")), None)
        cands = await catalog.search(db, category_id=cat.id if cat else None,
                                     q=None if cat else it["search_query"], sort="cheapest",
                                     user=user, personalize=False, limit=15)
        if not cands and cat:
            cands = await catalog.search(db, q=it["search_query"], sort="cheapest", personalize=False, limit=15)
        if not cands:
            await pipeline.discover(db, it["search_query"], limit=3)
            cands = await catalog.search(db, q=it["search_query"], sort="cheapest", personalize=False, limit=15)
        ok = [c for c in cands if (c["ai_rating"] or c["rating"] or 3.5) >= 3.5 and "Yüksek Riskli" not in c["badges"]]
        pick = (ok or cands or [None])[0]
        if not pick:
            missing.append(it["name"])
            continue
        cost = pick["price"] * it.get("quantity", 1)
        if budget and total + cost > budget and it.get("priority") != "must":
            missing.append(f"{it['name']} (bütçe yetmedi)")
            continue
        total += cost
        chosen.append({"item": it, "product": pick, "line_total": cost})
        if add_to_cart:
            db.add(CartItem(user_id=user.id, product_id=pick["id"], project_id=project.id,
                            quantity=it.get("quantity", 1), note=it["name"]))
    project.plan = {**plan, "chosen": chosen, "total": total, "missing": missing}
    await db.commit()
    return {"project_id": project.id, "items": chosen, "total": round(total, 2), "budget": budget,
            "over_budget": bool(budget and total > budget), "missing": missing, "tips": plan.get("tips", [])}


async def duel_commentary(result: dict) -> str:
    if not gemini.available:
        w = result["a"] if result["overall_winner"] == "a" else result["b"]
        return (f"{w['name']} {max(result['score'].values())} kategoride önde. "
                f"Skor: {result['score']['a']} - {result['score']['b']}.")
    try:
        return await gemini.text(
            "Bu karşılaştırma düellosunu yorumla: hangi kullanıcı tipi hangisini seçmeli, genel kazanan kim? "
            f"Kısa ve net ol.\n{json.dumps(result, ensure_ascii=False)}", system=SYSTEM)
    except GeminiError:
        return ""
