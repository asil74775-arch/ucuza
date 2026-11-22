#!/usr/bin/env bash
# FiyatRadar sunucu kurulumu (Ubuntu 22.04/24.04, root):
#   curl -fsSL https://raw.githubusercontent.com/asil74775-arch/ucuza/claude/mobile-shopping-ai-analysis-app-l68vqm/deploy/install.sh | bash
# Tekrar çalıştırmak güvenlidir: kodu günceller, ayarları korur, servisleri yeniden başlatır.
set -euo pipefail

REPO="https://github.com/asil74775-arch/ucuza.git"
BRANCH="claude/mobile-shopping-ai-analysis-app-l68vqm"
DIR="/opt/fiyatradar"

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { echo "Bu betik root olarak çalıştırılmalı."; exit 1; }

say "Gerekli paketler kuruluyor"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl openssl ca-certificates >/dev/null
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

say "Kod indiriliyor"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$DIR" reset --hard FETCH_HEAD
else
  git clone --depth 1 -b "$BRANCH" "$REPO" "$DIR"
fi
cd "$DIR"

if [ ! -f .env ] || [ ! -f backend/.env ]; then
  say "İlk kurulum ayarları"
  IP="$(curl -4 -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"
  DOMAIN="${IP//./-}.sslip.io"

  GEMINI=""
  DEMO="e"
  if [ -r /dev/tty ]; then
    read -rp "Gemini API anahtarı (yoksa boş bırakıp Enter): " GEMINI </dev/tty || true
    read -rp "Örnek ürünler yüklensin mi? (affiliate gelene kadar önerilir) [E/h]: " DEMO </dev/tty || true
  fi
  case "${DEMO:-e}" in [hHnN]*) SEED_DEMO=false ;; *) SEED_DEMO=true ;; esac

  PG_PASS="$(openssl rand -hex 16)"
  cat > .env <<EOF
API_DOMAIN=$DOMAIN
POSTGRES_PASSWORD=$PG_PASS
EOF
  cat > backend/.env <<EOF
APP_ENV=production
SECRET_KEY=$(openssl rand -hex 32)
DATABASE_URL=postgresql+asyncpg://fiyatradar:$PG_PASS@db:5432/fiyatradar
REDIS_URL=redis://redis:6379/0
MEDIA_ROOT=/data/media
PUBLIC_BASE_URL=https://$DOMAIN
OPERATOR_NAME=
OPERATOR_ADDRESS=
CONTACT_EMAIL=destek@fiyatradar.net.tr
GEMINI_API_KEY=$GEMINI
GEMINI_MODEL=gemini-2.5-flash
GEMINI_PAID_TIER=false
SEED_DEMO=$SEED_DEMO
AFFILIATE_FEED_URLS=
EOF
  chmod 600 .env backend/.env
fi

DOMAIN="$(grep '^API_DOMAIN=' .env | cut -d= -f2)"

say "Servisler başlatılıyor (ilk seferde 3-5 dakika sürebilir)"
docker compose up -d --build --remove-orphans

say "Sunucunun hazır olması bekleniyor"
for _ in $(seq 1 60); do
  if curl -fsS "https://$DOMAIN/health" >/dev/null 2>&1; then
    printf '\n\033[1;32mKURULUM TAMAM\033[0m\n'
    echo "API adresi: https://$DOMAIN"
    echo "Bu adresi Claude'a gönder; uygulama bu sunucuya bağlanacak."
    exit 0
  fi
  sleep 5
done

echo "Sunucu 5 dakikada yanıt vermedi. Son kayıtlar:"
docker compose logs --tail 40 api caddy
exit 1
