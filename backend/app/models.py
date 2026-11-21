"""FiyatRadar veritabanı şeması (SQLAlchemy 2.0).

PostgreSQL üretim veritabanıdır; JSON sütunları PostgreSQL'de JSONB'ye,
testlerde SQLite JSON'una eşlenir.
"""
from datetime import datetime, timezone

from sqlalchemy import (
    JSON, Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base

JsonType = JSON().with_variant(JSONB(), "postgresql")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------- Kullanıcı
class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(80))
    avatar_url: Mapped[str | None] = mapped_column(String(500))
    fcm_token: Mapped[str | None] = mapped_column(String(500))
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    # Yasal onaylar (kayıtta alınır, sürümüyle saklanır)
    terms_version: Mapped[str] = mapped_column(String(20), default="")
    terms_accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    age_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)  # 18 yaş ve üzeri
    # KVKK açık rıza: içeriğin yurt dışındaki yapay zeka hizmetine (Google Gemini) aktarılması.
    # İSTEĞE BAĞLIDIR; verilmezse uygulama çalışır, AI özellikleri kural tabanlı moda düşer.
    ai_consent: Mapped[bool] = mapped_column(Boolean, default=False)
    ai_consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    taste: Mapped["TasteProfile"] = relationship(back_populates="user", uselist=False, cascade="all, delete-orphan")


class TasteProfile(Base):
    """Kişisel Zevk Profili: etiket -> ağırlık (0..1)."""
    __tablename__ = "taste_profiles"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    weights: Mapped[dict] = mapped_column(JsonType, default=dict)
    price_sensitivity: Mapped[float] = mapped_column(Float, default=0.5)  # 1 = çok fiyat odaklı
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    user: Mapped[User] = relationship(back_populates="taste")


class UserEvent(Base):
    """Zevk profilini öğrenmek için davranış olayları (view, like, cart, purchase, search)."""
    __tablename__ = "user_events"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"))
    kind: Mapped[str] = mapped_column(String(20))
    payload: Mapped[dict] = mapped_column(JsonType, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Block(Base):
    __tablename__ = "blocks"
    blocker_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    blocked_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)


class Report(Base):
    """Kullanıcı içeriği şikayeti (Google Play UGC politikası gereği)."""
    __tablename__ = "reports"
    id: Mapped[int] = mapped_column(primary_key=True)
    reporter_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    target_type: Mapped[str] = mapped_column(String(20))  # experience|question|answer|message|user
    target_id: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(300))
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class LegalNotice(Base):
    """Hak ihlali / içerik kaldırma / marka itirazı / KVKK başvurusu (giriş gerekmeden yapılabilir)."""
    __tablename__ = "legal_notices"
    id: Mapped[int] = mapped_column(primary_key=True)
    kind: Mapped[str] = mapped_column(String(30))  # icerik_kaldirma|marka_itirazi|kvkk_basvurusu|diger
    name: Mapped[str] = mapped_column(String(200))
    email: Mapped[str] = mapped_column(String(255))
    target_type: Mapped[str | None] = mapped_column(String(20))  # product|experience|question|answer|user
    target_id: Mapped[int | None] = mapped_column(Integer)
    description: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="open")  # open|accepted|rejected
    resolution: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


# ---------------------------------------------------------------- Katalog
class Category(Base):
    __tablename__ = "categories"
    id: Mapped[int] = mapped_column(primary_key=True)
    slug: Mapped[str] = mapped_column(String(80), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    icon: Mapped[str] = mapped_column(String(60), default="category")
    parent_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"))
    is_accessory: Mapped[bool] = mapped_column(Boolean, default=False)
    # Teknik özellik şeması: filtreleme + düello + alternatif bulucu bunu kullanır.
    # [{key,label,unit,type:number|enum|bool,higher_is_better,filterable,weight}]
    spec_schema: Mapped[list] = mapped_column(JsonType, default=list)
    tags: Mapped[list] = mapped_column(JsonType, default=list)  # zevk etiketleri: tech, gaming...


class Brand(Base):
    __tablename__ = "brands"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)


class Product(Base):
    __tablename__ = "products"
    id: Mapped[int] = mapped_column(primary_key=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), index=True)
    brand_id: Mapped[int | None] = mapped_column(ForeignKey("brands.id"), index=True)
    name: Mapped[str] = mapped_column(String(300), index=True)
    model_code: Mapped[str | None] = mapped_column(String(120), index=True)
    description: Mapped[str] = mapped_column(Text, default="")
    specs: Mapped[dict] = mapped_column(JsonType, default=dict)
    images: Mapped[list] = mapped_column(JsonType, default=list)
    tags: Mapped[list] = mapped_column(JsonType, default=list)
    # AR: furniture (odada), wearable_face/wearable_body (üzerinde), tabletop (masada)
    ar_type: Mapped[str | None] = mapped_column(String(30))
    ar_model_url: Mapped[str | None] = mapped_column(String(500))  # .glb
    tryon_asset_url: Mapped[str | None] = mapped_column(String(500))  # şeffaf .png
    current_price: Mapped[float] = mapped_column(Float, default=0)
    currency: Mapped[str] = mapped_column(String(3), default="TRY")
    # AI ve skor alanları (pipeline tarafından güncellenir)
    # avg_rating: dış platform + uygulama içi puanların sayıya göre ağırlıklı ortalaması
    avg_rating: Mapped[float] = mapped_column(Float, default=0)
    external_rating_count: Mapped[int] = mapped_column(Integer, default=0)
    # ai_rating: FiyatRadar kullanıcı yorumlarının yapay zeka yıldızı (sahte yorumlar hariç)
    ai_rating: Mapped[float] = mapped_column(Float, default=0)
    rating_count: Mapped[int] = mapped_column(Integer, default=0)  # toplam puan sayısı (dış + iç)
    review_count: Mapped[int] = mapped_column(Integer, default=0)  # görünür uygulama içi yorum sayısı
    popularity: Mapped[float] = mapped_column(Float, default=0)
    durability_score: Mapped[float] = mapped_column(Float, default=0.5)
    fp_score: Mapped[float] = mapped_column(Float, default=0)
    best_choice_score: Mapped[float] = mapped_column(Float, default=0, index=True)
    score_breakdown: Mapped[dict] = mapped_column(JsonType, default=dict)
    fake_review_ratio: Mapped[float] = mapped_column(Float, default=0)
    is_chronic_free: Mapped[bool] = mapped_column(Boolean, default=False)
    badges: Mapped[list] = mapped_column(JsonType, default=list)
    external_ids: Mapped[dict] = mapped_column(JsonType, default=dict)
    source: Mapped[str] = mapped_column(String(40), default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    category: Mapped[Category] = relationship(lazy="joined")
    brand: Mapped[Brand | None] = relationship(lazy="joined")


class Offer(Base):
    """Satıcı teklifi (affiliate bağlantısıyla)."""
    __tablename__ = "offers"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    source: Mapped[str] = mapped_column(String(40))
    seller: Mapped[str] = mapped_column(String(120))
    price: Mapped[float] = mapped_column(Float)
    url: Mapped[str] = mapped_column(String(1000))
    affiliate_url: Mapped[str | None] = mapped_column(String(1000))
    in_stock: Mapped[bool] = mapped_column(Boolean, default=True)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class PriceHistory(Base):
    __tablename__ = "price_history"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"))
    price: Mapped[float] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(40), default="aggregate")
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    __table_args__ = (Index("ix_price_hist_prod_time", "product_id", "recorded_at"),)


class RatingHistory(Base):
    __tablename__ = "rating_history"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"))
    avg_rating: Mapped[float] = mapped_column(Float)
    ai_rating: Mapped[float] = mapped_column(Float, default=0)
    count: Mapped[int] = mapped_column(Integer)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    __table_args__ = (Index("ix_rating_hist_prod_time", "product_id", "recorded_at"),)


class ExternalRating(Base):
    """Dış platformlardaki YALNIZCA puan ve puan sayısı (yorum metni toplanmaz)."""
    __tablename__ = "external_ratings"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    source: Mapped[str] = mapped_column(String(60))  # ör. "Trendyol", "Hepsiburada", "Google Shopping"
    rating: Mapped[float] = mapped_column(Float)  # 1-5
    rating_count: Mapped[int] = mapped_column(Integer, default=0)
    url: Mapped[str | None] = mapped_column(String(1000))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    __table_args__ = (UniqueConstraint("product_id", "source", name="uq_ext_rating_src"),)


class ChronicIssue(Base):
    __tablename__ = "chronic_issues"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    key: Mapped[str] = mapped_column(String(80))
    title: Mapped[str] = mapped_column(String(200))
    mention_count: Mapped[int] = mapped_column(Integer)
    share: Mapped[float] = mapped_column(Float)
    months_active: Mapped[int] = mapped_column(Integer)
    severity: Mapped[str] = mapped_column(String(10))  # low|medium|high
    is_chronic: Mapped[bool] = mapped_column(Boolean, default=False)  # False => sadece "sık şikayet"
    first_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    timeline: Mapped[dict] = mapped_column(JsonType, default=dict)  # {"2026-01": 4, ...}


class Compatibility(Base):
    """Açık uyumluluk kaydı (aksesuar -> cihaz). Kural motoruna ek olarak kullanılır."""
    __tablename__ = "compatibility"
    id: Mapped[int] = mapped_column(primary_key=True)
    accessory_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    device_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    accessory_type: Mapped[str] = mapped_column(String(60))
    notes: Mapped[str] = mapped_column(String(300), default="")
    verified: Mapped[bool] = mapped_column(Boolean, default=False)


# ---------------------------------------------------------------- Alışveriş
class Project(Base):
    __tablename__ = "projects"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text)
    budget: Mapped[float | None] = mapped_column(Float)
    plan: Mapped[dict] = mapped_column(JsonType, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class CartItem(Base):
    __tablename__ = "cart_items"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"))
    offer_id: Mapped[int | None] = mapped_column(ForeignKey("offers.id", ondelete="SET NULL"))
    project_id: Mapped[int | None] = mapped_column(ForeignKey("projects.id", ondelete="SET NULL"))
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    note: Mapped[str] = mapped_column(String(300), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    product: Mapped[Product] = relationship(lazy="joined")


class Ownership(Base):
    """Kullanıcının sahip olduğu ürünler (Bizden Alanlar ve Soru-Cevap sahip rozeti)."""
    __tablename__ = "ownerships"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)  # affiliate dönüşümüyle doğrulanır
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


# ---------------------------------------------------------------- AI
class AiSession(Base):
    __tablename__ = "ai_sessions"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    mode: Mapped[str] = mapped_column(String(20))  # general|should_buy|mission|project
    context: Mapped[dict] = mapped_column(JsonType, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AiMessage(Base):
    __tablename__ = "ai_messages"
    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("ai_sessions.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(10))  # user|model
    text: Mapped[str] = mapped_column(Text)
    data: Mapped[dict] = mapped_column(JsonType, default=dict)  # kartlar, karar vb.
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class VideoJob(Base):
    __tablename__ = "video_jobs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    file_path: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(20), default="queued")  # queued|processing|done|failed
    stage: Mapped[str] = mapped_column(String(60), default="")
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"))
    result: Mapped[dict] = mapped_column(JsonType, default=dict)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


# ---------------------------------------------------------------- Topluluk
class Experience(Base):
    """FiyatRadar kullanıcı yorumu = Gerçek Kullanıcı Deneyimi (Keşfet + Bizden Alanlar).
    Uygulamadaki TEK yorum kaynağıdır; yapay zeka analizi bu kayıtlar üzerinde çalışır."""
    __tablename__ = "experiences"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    text: Mapped[str] = mapped_column(String(1000))
    rating: Mapped[int] = mapped_column(Integer)
    media: Mapped[list] = mapped_column(JsonType, default=list)  # [{type: image|video, url}]
    verified_purchase: Mapped[bool] = mapped_column(Boolean, default=False)
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False)  # şikayet/moderasyon veya sahte
    # Yapay zeka analizi
    ai_stars: Mapped[float | None] = mapped_column(Float)
    sentiment: Mapped[str | None] = mapped_column(String(10))
    complaints: Mapped[list] = mapped_column(JsonType, default=list)  # [{key,label}]
    fake_probability: Mapped[float] = mapped_column(Float, default=0)
    fake_reasons: Mapped[list] = mapped_column(JsonType, default=list)
    analyzed: Mapped[bool] = mapped_column(Boolean, default=False)
    content_hash: Mapped[str] = mapped_column(String(64), default="", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    user: Mapped[User] = relationship(lazy="joined")
    product: Mapped[Product] = relationship(lazy="joined")
    # Kullanıcı başına ürün başına tek yorum (puan şişirmeyi önler)
    __table_args__ = (UniqueConstraint("user_id", "product_id", name="uq_experience_user_product"),)


class ExperienceLike(Base):
    __tablename__ = "experience_likes"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    experience_id: Mapped[int] = mapped_column(ForeignKey("experiences.id", ondelete="CASCADE"), primary_key=True)


class Question(Base):
    __tablename__ = "questions"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    text: Mapped[str] = mapped_column(String(600))
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    user: Mapped[User] = relationship(lazy="joined")
    answers: Mapped[list["Answer"]] = relationship(lazy="selectin", cascade="all, delete-orphan")


class Answer(Base):
    __tablename__ = "answers"
    id: Mapped[int] = mapped_column(primary_key=True)
    question_id: Mapped[int] = mapped_column(ForeignKey("questions.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    text: Mapped[str] = mapped_column(String(1000))
    is_owner: Mapped[bool] = mapped_column(Boolean, default=False)
    helpful_count: Mapped[int] = mapped_column(Integer, default=0)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    user: Mapped[User] = relationship(lazy="joined")


# ---------------------------------------------------------------- Mesajlaşma
class Conversation(Base):
    __tablename__ = "conversations"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"))
    last_message_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    members: Mapped[list["ConversationMember"]] = relationship(lazy="selectin", cascade="all, delete-orphan")


class ConversationMember(Base):
    __tablename__ = "conversation_members"
    conversation_id: Mapped[int] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    last_read_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    user: Mapped[User] = relationship(lazy="joined")


class Message(Base):
    __tablename__ = "messages"
    id: Mapped[int] = mapped_column(primary_key=True)
    conversation_id: Mapped[int] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"), index=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    text: Mapped[str] = mapped_column(String(2000), default="")
    media_url: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
