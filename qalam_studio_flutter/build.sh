#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=""
if command -v flutter >/dev/null 2>&1 && flutter --version >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
elif [ -x "$HOME/flutter_322/bin/flutter" ] && "$HOME/flutter_322/bin/flutter" --version >/dev/null 2>&1; then
  FLUTTER_BIN="$HOME/flutter_322/bin/flutter"
else
  git clone --depth 1 --branch 3.22.3 https://github.com/flutter/flutter.git "$HOME/flutter_322"
  FLUTTER_BIN="$HOME/flutter_322/bin/flutter"
fi

export PATH="$(dirname "$FLUTTER_BIN"):$PATH"
echo "==> Using Flutter: $FLUTTER_BIN"

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

mkdir -p assets/templates assets/fonts
download_full_ttf() {
  local fname="$1"
  local url="$2"
  local target="assets/fonts/$fname"
  if [ -s "$target" ] && [ "$(wc -c < "$target")" -gt 20000 ]; then
    return 0
  fi
  rm -f "$target"
  curl -fsSL "$url" -o "$target"
}

echo "==> Checking & downloading Urdu, English & 16 Signature .ttf fonts..."
download_full_ttf "NotoNastaliqUrdu-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/notonastaliqurdu/NotoNastaliqUrdu%5Bwght%5D.ttf"
cp -f assets/fonts/NotoNastaliqUrdu-Regular.ttf assets/fonts/NotoNastaliqUrdu-Bold.ttf
download_full_ttf "Gulzar-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/gulzar/Gulzar-Regular.ttf"
download_full_ttf "NotoNaskhArabic-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf"
cp -f assets/fonts/NotoNaskhArabic-Regular.ttf assets/fonts/NotoNaskhArabic-Bold.ttf
download_full_ttf "PlusJakartaSans-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf"
cp -f assets/fonts/PlusJakartaSans-Regular.ttf assets/fonts/PlusJakartaSans-SemiBold.ttf
cp -f assets/fonts/PlusJakartaSans-Regular.ttf assets/fonts/PlusJakartaSans-Bold.ttf
download_full_ttf "PlayfairDisplay-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf"
cp -f assets/fonts/PlayfairDisplay-Regular.ttf assets/fonts/PlayfairDisplay-Bold.ttf
download_full_ttf "IBMPlexSansArabic-SemiBold.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsansarabic/IBMPlexSansArabic-SemiBold.ttf"
download_full_ttf "Montserrat-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf"
download_full_ttf "Poppins-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-Regular.ttf"
download_full_ttf "Poppins-SemiBold.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-SemiBold.ttf"
download_full_ttf "Poppins-Bold.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-Bold.ttf"
download_full_ttf "BebasNeue-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/bebasneue/BebasNeue-Regular.ttf"
download_full_ttf "Lora-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/lora/Lora%5Bwght%5D.ttf"
download_full_ttf "Oswald-Regular.ttf" "https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald%5Bwght%5D.ttf"

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

echo "==> Running flutter clean, pub get & building Release APK..."
"$FLUTTER_BIN" clean
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --release
echo "==> Done! APK generated at build/app/outputs/flutter-apk/app-release.apk"
