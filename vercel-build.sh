#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Building ZEV Flutter Web for Vercel..."
echo "=========================================="

# 1. Ensure .env file exists for Flutter asset bundler & runtime
if [ ! -f ".env" ]; then
  echo "📝 Generating .env for Flutter build..."
  touch .env
  
  # Inject default public client configuration
  echo "NEXT_PUBLIC_SUPABASE_URL=${NEXT_PUBLIC_SUPABASE_URL:-https://enpuoypqpklndnnhndax.supabase.co}" >> .env
  echo "NEXT_PUBLIC_SUPABASE_ANON_KEY=${NEXT_PUBLIC_SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVucHVveXBxcGtsbmRubmhuZGF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMwNzg1MjgsImV4cCI6MjA5ODY1NDUyOH0.slU2vYIzM0BXG_3ksR5pcfvP-cpFH7IkwIyuzF1pNCo}" >> .env
  echo "NEXT_PUBLIC_SITE_URL=${NEXT_PUBLIC_SITE_URL:-https://safiacademy.org/en}" >> .env
  echo "NEXT_PUBLIC_AGORA_APP_ID=${NEXT_PUBLIC_AGORA_APP_ID:-25dab5216d9341a7a7fe769c0844e3ce}" >> .env
  
  # Forward any additional environment variables defined in Vercel
  [ -n "$GOOGLE_GEMINI_API_KEY" ] && echo "GOOGLE_GEMINI_API_KEY=$GOOGLE_GEMINI_API_KEY" >> .env
  [ -n "$NEXT_PUBLIC_TELEGRAM_BOT_TOKEN" ] && echo "NEXT_PUBLIC_TELEGRAM_BOT_TOKEN=$NEXT_PUBLIC_TELEGRAM_BOT_TOKEN" >> .env
  [ -n "$NEXT_PUBLIC_TELEGRAM_CHAT_ID" ] && echo "NEXT_PUBLIC_TELEGRAM_CHAT_ID=$NEXT_PUBLIC_TELEGRAM_CHAT_ID" >> .env
  [ -n "$NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2" ] && echo "NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2=$NEXT_PUBLIC_TELEGRAM_BOT_TOKEN2" >> .env
  [ -n "$NEXT_PUBLIC_TELEGRAM_CHAT_ID2" ] && echo "NEXT_PUBLIC_TELEGRAM_CHAT_ID2=$NEXT_PUBLIC_TELEGRAM_CHAT_ID2" >> .env
  [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && echo "CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID" >> .env
  [ -n "$CLOUDFLARE_R2_ACCESS_KEY_ID" ] && echo "CLOUDFLARE_R2_ACCESS_KEY_ID=$CLOUDFLARE_R2_ACCESS_KEY_ID" >> .env
  [ -n "$CLOUDFLARE_R2_SECRET_ACCESS_KEY" ] && echo "CLOUDFLARE_R2_SECRET_ACCESS_KEY=$CLOUDFLARE_R2_SECRET_ACCESS_KEY" >> .env
  [ -n "$CLOUDFLARE_R2_BUCKET_NAME" ] && echo "CLOUDFLARE_R2_BUCKET_NAME=$CLOUDFLARE_R2_BUCKET_NAME" >> .env
  [ -n "$CLOUDFLARE_R2_PUBLIC_DOMAIN" ] && echo "CLOUDFLARE_R2_PUBLIC_DOMAIN=$CLOUDFLARE_R2_PUBLIC_DOMAIN" >> .env
  [ -n "$ADMOB_APP_ID" ] && echo "ADMOB_APP_ID=$ADMOB_APP_ID" >> .env
  [ -n "$ADMOB_FEED_AD_UNIT_ID" ] && echo "ADMOB_FEED_AD_UNIT_ID=$ADMOB_FEED_AD_UNIT_ID" >> .env
  [ -n "$ADMOB_REELS_AD_UNIT_ID" ] && echo "ADMOB_REELS_AD_UNIT_ID=$ADMOB_REELS_AD_UNIT_ID" >> .env
  
  echo "✅ .env created successfully with $(wc -l < .env) lines."
fi

# 2. Check if flutter is available, otherwise download shallow clone
if ! command -v flutter &> /dev/null; then
  echo "📥 Flutter not found in PATH, fetching Flutter SDK..."
  if [ ! -d "flutter-sdk" ]; then
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter-sdk
  fi
  export PATH="$PATH:$(pwd)/flutter-sdk/bin"
fi

echo "📌 Flutter Version:"
flutter --version

echo "⚙️ Enabling Web..."
flutter config --enable-web

echo "📦 Fetching dependencies..."
flutter pub get

echo "🔨 Running flutter build web --release..."
flutter build web --release

echo "📋 Copying PWA assets (sw.js, manifest.json, offline.html, screenshots) to build/web..."
cp -r web/screenshots build/web/ 2>/dev/null || true
cp web/sw.js build/web/ 2>/dev/null || true
cp web/offline.html build/web/ 2>/dev/null || true
cp web/manifest.json build/web/ 2>/dev/null || true

echo "✅ Build complete! Output ready in build/web"

