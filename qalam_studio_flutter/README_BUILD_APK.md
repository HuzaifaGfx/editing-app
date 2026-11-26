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

## APK size note

The shipped APK is a universal APK (one file for all devices, currently
about 31 MB, well under the 40 MB limit). If its size ever approaches the
limit, building with `--split-per-abi` instead (`flutter build apk --release
--split-per-abi`) produces one smaller APK per device architecture, roughly
a third of the universal size each. The CI build (`build.sh` /
`.github/workflows/build-apk.yml`) intentionally keeps the universal APK for
now, so do not switch it to split builds unless size forces it.
