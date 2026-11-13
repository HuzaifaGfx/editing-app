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

# Auto-detect Android SDK & Java 17 (Codespaces Linux or macOS)
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ -d "$HOME/android-sdk" ]; then
    export ANDROID_HOME="$HOME/android-sdk"
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
  fi
fi
if [ -n "${ANDROID_HOME:-}" ]; then
  export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
  "$FLUTTER_BIN" config --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
fi
if ls /usr/lib/jvm/java-17-openjdk-*/bin/java >/dev/null 2>&1; then
  JDK17_DIR="$(dirname "$(dirname "$(readlink -f "$(ls /usr/lib/jvm/java-17-openjdk-*/bin/java | head -n 1)")")")"
  "$FLUTTER_BIN" config --jdk-dir "$JDK17_DIR" >/dev/null 2>&1 || true
fi

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

# 3. Generate clean official Android v2 Gradle files (android/gradlew, build.gradle, settings.gradle) if missing or missing v2 embedding
if [ ! -f "android/gradlew" ] || ! grep -q 'flutterEmbedding' android/app/src/main/AndroidManifest.xml 2>/dev/null; then
  echo "==> Generating clean Android v2 Gradle project..."
  TMP_DIR="/tmp/qalam_studio_bootstrap_$$"
  rm -rf "$TMP_DIR" android
  "$FLUTTER_BIN" create "$TMP_DIR" --platforms=android --org com.qalam --project-name qalam_studio
  mkdir -p android
  cp -R "$TMP_DIR/android/"* android/
  rm -rf "$TMP_DIR"

  # Add offline storage permissions cleanly to the generated v2 AndroidManifest.xml
  MANIFEST="android/app/src/main/AndroidManifest.xml"
  if [ -f "$MANIFEST" ] && ! grep -q 'READ_MEDIA_IMAGES' "$MANIFEST"; then
    awk '
      /<application/ && !done {
        print "    <uses-permission android:name=\"android.permission.READ_MEDIA_IMAGES\" />"
        print "    <uses-permission android:name=\"android.permission.READ_EXTERNAL_STORAGE\" android:maxSdkVersion=\"32\" />"
        print "    <uses-permission android:name=\"android.permission.WRITE_EXTERNAL_STORAGE\" android:maxSdkVersion=\"29\" />"
        done=1
      }
      { print }
    ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  fi
fi

echo "==> Running flutter clean, pub get & building Release APK..."
"$FLUTTER_BIN" clean
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --release

echo "==> Running Gradle assembleRelease..."
cd android
chmod +x ./gradlew
./gradlew assembleRelease
echo "==> Done! APK generated at build/app/outputs/flutter-apk/app-release.apk"
