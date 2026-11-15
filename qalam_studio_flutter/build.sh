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

# 2. Download real Urdu & English .ttf fonts automatically if assets/fonts/ is empty (NEVER strip fonts!)
mkdir -p assets/templates assets/fonts
download_gfont() {
  local fname="$1"
  local family="$2"
  local target="assets/fonts/$fname"
  if [ -s "$target" ] && [ "$(wc -c < "$target")" -gt 5000 ]; then
    return 0
  fi
  local ttf_url
  ttf_url="$(curl -fsSL -A "Wget/1.18" "https://fonts.googleapis.com/css?family=$family" | grep -oE 'https://fonts\.gstatic\.com[^)]*\.ttf' | head -n 1 || true)"
  if [ -n "$ttf_url" ]; then
    curl -fsSL "$ttf_url" -o "$target" || true
  fi
}

echo "==> Checking & downloading Urdu + English offline .ttf fonts..."
download_gfont "NotoNastaliqUrdu-Regular.ttf" "Noto+Nastaliq+Urdu:400"
download_gfont "NotoNastaliqUrdu-Bold.ttf" "Noto+Nastaliq+Urdu:700"
download_gfont "Gulzar-Regular.ttf" "Gulzar:400"
download_gfont "NotoNaskhArabic-Regular.ttf" "Noto+Naskh+Arabic:400"
download_gfont "NotoNaskhArabic-Bold.ttf" "Noto+Naskh+Arabic:700"
download_gfont "PlusJakartaSans-Regular.ttf" "Plus+Jakarta+Sans:400"
download_gfont "PlusJakartaSans-SemiBold.ttf" "Plus+Jakarta+Sans:600"
download_gfont "PlusJakartaSans-Bold.ttf" "Plus+Jakarta+Sans:700"
download_gfont "PlayfairDisplay-Regular.ttf" "Playfair+Display:400"
download_gfont "PlayfairDisplay-Bold.ttf" "Playfair+Display:700"

if [ -z "$(ls -A assets/fonts 2>/dev/null || true)" ]; then
  echo "==> Warning: No fonts downloaded (offline environment)."
fi


# 16 Signature Script & Calligraphy Fonts
download_full_ttf "GreatVibes-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/greatvibes/GreatVibes-Regular.ttf"
download_full_ttf "AlexBrush-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/alexbrush/AlexBrush-Regular.ttf"
download_full_ttf "Allura-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/allura/Allura-Regular.ttf"
download_full_ttf "Sacramento-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/sacramento/Sacramento-Regular.ttf"
download_full_ttf "Parisienne-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/parisienne/Parisienne-Regular.ttf"
download_full_ttf "PinyonScript-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/pinyonscript/PinyonScript-Regular.ttf"
download_full_ttf "Pacifico-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/pacifico/Pacifico-Regular.ttf"
download_full_ttf "Satisfy-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/apache/satisfy/Satisfy-Regular.ttf"
download_full_ttf "DancingScript-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/dancingscript/DancingScript%5Bwght%5D.ttf"
download_full_ttf "Caveat-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/caveat/Caveat%5Bwght%5D.ttf"
download_full_ttf "HerrVonMuellerhoff-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/herrvonmuellerhoff/HerrVonMuellerhoff-Regular.ttf"
download_full_ttf "HomemadeApple-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/apache/homemadeapple/HomemadeApple-Regular.ttf"
download_full_ttf "MrDafoe-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/mrdafoe/MrDafoe-Regular.ttf"
download_full_ttf "Yesteryear-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/yesteryear/Yesteryear-Regular.ttf"
download_full_ttf "MarckScript-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/marckscript/MarckScript-Regular.ttf"
download_full_ttf "ReenieBeanie.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/reeniebeanie/ReenieBeanie.ttf"

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
