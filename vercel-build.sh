#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Building ZEV Flutter Web for Vercel..."
echo "=========================================="

# Check if flutter is available, otherwise download shallow clone
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

echo "🔨 Running flutter build web --release..."
flutter build web --release

# Ensure SPA rewrites exist in output
if [ -f "vercel.json" ]; then
  cp vercel.json build/web/
fi

echo "✅ Build complete! Output ready in build/web"
