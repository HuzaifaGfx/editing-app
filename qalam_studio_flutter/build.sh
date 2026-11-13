#!/usr/bin/env bash
set -euo pipefail

# 1. Pick a working Flutter binary (supports macOS 11 Big Sur via Flutter 3.22.3)
FLUTTER_BIN=""
if command -v flutter >/dev/null 2>&1 && flutter --version >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [ -x "$HOME/flutter_322/bin/flutter" ] && "$HOME/flutter_322/bin/flutter" --version >/dev/null 2>&1; then
  FLUTTER_BIN="$HOME/flutter_322/bin/flutter"
else
  echo "==> System Flutter unavailable or macOS < 14 detected."
  echo "==> Installing macOS 11-compatible Flutter 3.22.3 into ~/flutter_322..."
  git clone --depth 1 --branch 3.22.3 https://github.com/flutter/flutter.git "$HOME/flutter_322"
  FLUTTER_BIN="$HOME/flutter_322/bin/flutter"
fi

export PATH="$(dirname "$FLUTTER_BIN"):$PATH"
echo "==> Using Flutter: $FLUTTER_BIN"

# 2. Ensure declared asset directories exist so flutter pub get never fails
mkdir -p assets/templates assets/fonts
if [ -z "$(ls -A assets/fonts 2>/dev/null || true)" ]; then
  echo "==> Note: assets/fonts/ is empty; preparing clean pubspec backup if needed..."
  if grep -q "assets/fonts/" pubspec.yaml; then
    cp pubspec.yaml pubspec.yaml.bak
    awk '
      /^  fonts:/ { skip=1; next }
      skip && /^[^ ]/ { skip=0 }
      !skip { print }
    ' pubspec.yaml.bak > pubspec.yaml
  fi
fi

# 3. Generate Android Gradle files (android/gradlew, build.gradle, settings.gradle) if missing
if [ ! -f "android/gradlew" ]; then
  echo "==> Initializing Android Gradle project..."
  TMP_DIR="/tmp/qalam_studio_bootstrap_$$"
  rm -rf "$TMP_DIR"
  "$FLUTTER_BIN" create "$TMP_DIR" --platforms=android --org com.qalam --project-name qalam_studio
  mkdir -p android
  if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
    cp android/app/src/main/AndroidManifest.xml "/tmp/qalam_manifest_$$.xml"
  fi
  cp -R "$TMP_DIR/android/"* android/
  if [ -f "/tmp/qalam_manifest_$$.xml" ]; then
    cp "/tmp/qalam_manifest_$$.xml" android/app/src/main/AndroidManifest.xml
    rm -f "/tmp/qalam_manifest_$$.xml"
  fi
  rm -rf "$TMP_DIR"
fi

echo "==> Running flutter pub get & building Release APK..."
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --release

echo "==> Running Gradle assembleRelease..."
cd android
chmod +x ./gradlew
./gradlew assembleRelease
echo "==> Done! APK generated at build/app/outputs/flutter-apk/app-release.apk"
