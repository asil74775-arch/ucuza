from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Dengi.com"
    app_env: str = "development"
    secret_key: str = "dev-secret-change-me-dev-secret-change-me"
    access_token_minutes: int = 60 * 24 * 30
    database_url: str = "sqlite+aiosqlite:///./dengi.db"
    redis_url: str | None = None
    media_root: str = "./media"
    public_base_url: str = "http://10.0.2.2:8000"
    max_upload_mb: int = 50

    # Yasal metinlerde görünen işletme bilgileri (yayından önce DOLDURUN)
    operator_name: str = "[İşletme adı / şahıs şirketi unvanı]"
    operator_address: str = "[Adres]"
    contact_email: str = "destek@dengi.com"
    terms_version: str = "2026-11"

    gemini_api_key: str | None = None
    gemini_model: str = "gemini-2.5-flash"
    # Ücretli katmanda Google gönderilen içeriği model eğitimi için KULLANMAZ; ücretsiz katmanda kullanabilir.
    # Açık rıza metni bu ayara göre kullanıcıya doğru bilgiyi verir.
    gemini_paid_tier: bool = False

    affiliate_feed_urls: str = ""  # virgülle ayrılmış JSON feed URL'leri

    # Sahte yorum eşikleri
    fake_hide_threshold: float = 0.70
    fake_warn_threshold: float = 0.45
    # Kronik sorun eşikleri
    chronic_min_share: float = 0.05
    chronic_min_months: int = 3
    chronic_free_min_reviews: int = 10  # uygulama içi yorum sayısı eşiği


@lru_cache
def get_settings() -> Settings:
    return Settings()
