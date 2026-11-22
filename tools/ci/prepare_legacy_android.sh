#!/usr/bin/env bash
# Prepares a copy of the project that builds with Flutter 3.32 for Android 5.0+ (API 21).
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
DST="${1:?destination dir}"
rm -rf "$DST" && mkdir -p "$DST"
cp -r "$SRC/lib" "$SRC/assets" "$SRC/packages" "$DST/"
cp "$SRC/pubspec_legacy.yaml.tmpl" "$DST/pubspec.yaml"
cd "$DST"
flutter create --platforms android --org io.github.gmwester --project-name universal_translator . >/dev/null
rm -rf test
M="$DST/android/app/src/main"
cp "$SRC/android/app/src/main/AndroidManifest.xml" "$M/AndroidManifest.xml"
rm -rf "$M/kotlin" && cp -r "$SRC/android/app/src/main/kotlin" "$M/kotlin"
cp -r "$SRC/android/app/src/main/res/." "$M/res/"
cp "$SRC/android/app/proguard-rules.pro" "$DST/android/app/"
python3 "$SRC/tools/ci/patch_android_gradle.py" "$DST/android/app/build.gradle.kts"
# Use the app's Android Gradle Plugin version for the FFI plugin too.
AGP=$(grep -oE 'com.android.application"\) version "[0-9.]+' "$DST/android/settings.gradle.kts" | grep -oE '[0-9.]+$' || true)
if [ -n "$AGP" ]; then
  sed -i -E "s/com.android.tools.build:gradle:[0-9.]+/com.android.tools.build:gradle:$AGP/" "$DST/packages/ipareader_ffi/android/build.gradle"
fi
# ONNX Runtime 1.21+ requires Android 7.0; 1.20 is the newest that runs on Android 5.0+.
cat >> "$DST/android/build.gradle.kts" <<'GRADLE'

subprojects {
    configurations.all {
        resolutionStrategy.force("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
    }
}
GRADLE
echo "legacy project ready in $DST (AGP $AGP)"
