#!/bin/zsh
# 사용법:
#   ./build.sh           앱 빌드 (build/Trackpad-no-Tatsujin.app, 이 Mac의 아키텍처만)
#   ./build.sh run       빌드 후 실행
#   ./build.sh test      Core 자체 테스트
#   ./build.sh release   배포용: 유니버설(Apple Silicon + Intel) 빌드 → dist/Trackpad-no-Tatsujin-<버전>.dmg
#
# 배포 서명 (Apple Developer Program 가입 후):
#   SIGN_ID="Developer ID Application: 이름 (TEAMID)"   있으면 이 인증서로 서명, 없으면 임시 서명
#   NOTARY_PROFILE=프로필이름                           있으면 공증까지
#     (처음 한 번: xcrun notarytool store-credentials 프로필이름 --apple-id … --team-id … )
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-app.trackpad-no-tatsujin.mac}"
SIGN_ID="${SIGN_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

SOURCES=(Sources/Core/*.swift Sources/App/*.swift Sources/App/Scenes/*.swift)
APP=build/Trackpad-no-Tatsujin.app
mkdir -p .build

if [[ "${1:-}" == "test" ]]; then
    swiftc -O Sources/Core/*.swift Tests/main.swift -o .build/selftest
    exec .build/selftest
fi

if [[ "${1:-}" == "release" ]]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$(uname -m)")
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINARIES=()
for arch in $ARCHS; do
    echo "컴파일: $arch"
    swiftc -O -target "$arch-apple-macos14" -module-name TrackpadNoTatsujin $SOURCES -o ".build/Trackpad-no-Tatsujin-$arch"
    BINARIES+=".build/Trackpad-no-Tatsujin-$arch"
done
lipo -create $BINARIES -output "$APP/Contents/MacOS/Trackpad-no-Tatsujin"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>트릭패드의 달인</string>
    <key>CFBundleDisplayName</key><string>트릭패드의 달인</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Trackpad-no-Tatsujin</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music-games</string>
    <key>NSHumanReadableCopyright</key><string>트릭패드의 달인</string>
</dict>
</plist>
PLIST

# iCloud Drive 안에서는 Finder 정보 같은 확장 속성이 붙어서 서명이 거부된다
xattr -cr "$APP"
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    echo "서명: $SIGN_ID"
else
    codesign --force --sign - "$APP"
fi
echo "빌드 완료: $APP ($(lipo -archs "$APP/Contents/MacOS/Trackpad-no-Tatsujin"))"

if [[ "${1:-}" == "run" ]]; then
    open "$APP"
fi

if [[ "${1:-}" == "release" ]]; then
    DMG="dist/Trackpad-no-Tatsujin-$VERSION.dmg"
    # iCloud Drive 안에서는 서명 뒤에도 확장 속성이 다시 붙으므로 바깥 임시 폴더에서 서명하고 묶는다
    STAGE="$(mktemp -d)/dmg"
    trap 'rm -rf "${STAGE:h}"' EXIT
    rm -f "$DMG"
    mkdir -p "$STAGE" dist
    ditto --noextattr --noqtn "$APP" "$STAGE/트릭패드의 달인.app"
    if [[ -n "$SIGN_ID" ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/트릭패드의 달인.app"
    else
        codesign --force --sign - "$STAGE/트릭패드의 달인.app"
    fi
    codesign --verify --deep --strict "$STAGE/트릭패드의 달인.app"
    ln -s /Applications "$STAGE/Applications"
    cp "INSTALL.md" "$STAGE/설치 방법.txt"
    hdiutil create -volname "트릭패드의 달인 $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

    if [[ -n "$SIGN_ID" ]]; then
        codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
    fi
    if [[ -n "$SIGN_ID" && -n "$NOTARY_PROFILE" ]]; then
        echo "공증 요청 중… (몇 분 걸릴 수 있어요)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
    echo "배포 파일: $DMG"
    shasum -a 256 "$DMG"
fi
