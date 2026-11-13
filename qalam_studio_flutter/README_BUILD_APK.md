# Qalam Studio — Offline Flutter Android Build Guide

1. Install Flutter SDK (3.22+) and Android SDK Platform 34.
2. Create project & copy these files into your Flutter workspace:
   ```bash
   flutter create qalam_studio
   cd qalam_studio
   ```
3. Place offline font files inside `assets/fonts/`:
   - `NotoNastaliqUrdu-Regular.ttf`, `NotoNastaliqUrdu-Bold.ttf`
   - `Gulzar-Regular.ttf`
   - `NotoNaskhArabic-Regular.ttf`, `NotoNaskhArabic-Bold.ttf`
   - `PlusJakartaSans-Regular.ttf`, `PlusJakartaSans-SemiBold.ttf`, `PlusJakartaSans-Bold.ttf`
   - `PlayfairDisplay-Regular.ttf`, `PlayfairDisplay-Bold.ttf`
4. Install packages & build standalone release APK (no server hosting required):
   ```bash
   flutter pub get
   flutter build apk --release --split-per-abi
   ```
5. Output APKs will be generated at `build/app/outputs/flutter-apk/`.
