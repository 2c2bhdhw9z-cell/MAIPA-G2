#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MAIPA-G"
OUT="$HERE/build"
DERIVED="$OUT/DerivedData"
STAGE="$OUT/stage"
ENTITLEMENTS="$HERE/get-task-allow.entitlements"

mkdir -p "$OUT/Generated"

# Stamp CFBundleVersion with the GitHub Actions run number so on-device signers
# always recognize each new build as an upgrade instead of skipping installation.
BUILD_NUMBER="${MAIPAG_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
echo "==> stamping CFBundleVersion $BUILD_NUMBER"

python3 - "$HERE/project.yml" "$BUILD_NUMBER" <<'PY'
import re
import sys

path, build = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    text = handle.read()
pattern = re.compile(r'^(\s*CFBundleVersion:\s*)"[^"]*"$', re.MULTILINE)
text, count = pattern.subn(lambda m: f'{m.group(1)}"{build}"', text)
if count != 1:
    sys.exit(f"error: expected exactly one CFBundleVersion line, rewrote {count}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text)
print(f"CFBundleVersion set to {build}")
PY

echo "==> xcodegen generate"
(cd "$HERE" && xcodegen generate --spec project.yml --project .)

echo "==> xcodebuild"
xcodebuild \
  -project "$HERE/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP" ] || {
  echo "error: no app bundle at $APP" >&2
  find "$DERIVED/Build/Products" -maxdepth 3 -name '*.app' >&2 || true
  exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
BUNDLE="$STAGE/Payload/$APP_NAME.app"

echo "==> ad-hoc signing $APP_NAME.app with entitlements"
[ -f "$ENTITLEMENTS" ] || { echo "error: $ENTITLEMENTS missing" >&2; exit 1; }
codesign --force --sign - --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --generate-entitlement-der \
  "$BUNDLE"

echo "==> entitlements actually embedded:"
codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null | sed 's/^/      /' || true

IPA="$OUT/$APP_NAME.ipa"
rm -f "$IPA"
echo "==> zipping"
(cd "$STAGE" && zip -qry "$IPA" Payload)

echo "==> $IPA ($(du -h "$IPA" | cut -f1))"
unzip -l "$IPA" | sed 's/^/      /'
