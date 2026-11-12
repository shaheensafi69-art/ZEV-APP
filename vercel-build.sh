#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Building ZEV Flutter Web for Vercel..."
echo "=========================================="

# Public build-time configuration ONLY (never bundle .env or server secrets into client builds)
SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-https://zjwmioalrhkyfbzhdnnw.supabase.co}"
SUPABASE_ANON_KEY="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-sb_publishable_mhRdQoBdG-Ha0_nQ4dHIVw_MrXwmR5z}"
ZEV_API_URL="${ZEV_API_BASE_URL:-https://www.zevapp.com}"
R2_DOMAIN="${CLOUDFLARE_R2_PUBLIC_DOMAIN:-https://media.zevapp.com}"

# 1. Check if flutter is available, otherwise download shallow clone
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

echo "🔨 Running flutter build web --release (public dart-defines only)..."
flutter build web --release \
  --dart-define="NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
  --dart-define="ZEV_API_BASE_URL=${ZEV_API_URL}" \
  --dart-define="CLOUDFLARE_R2_PUBLIC_DOMAIN=${R2_DOMAIN}" \
  ${FIREBASE_VAPID_KEY:+--dart-define="FIREBASE_VAPID_KEY=${FIREBASE_VAPID_KEY}"}

echo "📋 Copying PWA assets (sw.js, manifest.json, offline.html, screenshots, app-ads.txt) to build/web..."
rm -rf build/web/screenshots
cp -r web/screenshots build/web/ 2>/dev/null || true
cp web/sw.js build/web/ 2>/dev/null || true
cp web/offline.html build/web/ 2>/dev/null || true
cp web/manifest.json build/web/ 2>/dev/null || true
cp web/app-ads.txt build/web/ 2>/dev/null || true
cp app-ads.txt build/web/ 2>/dev/null || true

# Prevent deprecated flutter_service_worker.js from overriding /sw.js at scope '/'
rm -f build/web/flutter_service_worker.js
node -e '
const fs = require("fs");
const p = "build/web/flutter_bootstrap.js";
if (fs.existsSync(p)) {
  const src = fs.readFileSync(p, "utf8");
  const patched = src.replace(/_flutter\.loader\.load\(\{[\s\S]*$/, "_flutter.loader.load({});\n");
  fs.writeFileSync(p, patched, "utf8");
}
' 2>/dev/null || true

echo "✅ Build complete! Output ready in build/web"
