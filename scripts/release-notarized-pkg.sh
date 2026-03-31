#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "This script only works on macOS." >&2
  exit 1
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd go
require_cmd pkgbuild
require_cmd productsign
require_cmd xcrun
require_cmd shasum

if ! xcrun notarytool --version >/dev/null 2>&1; then
  echo "xcrun notarytool is not available. Install Xcode Command Line Tools." >&2
  exit 1
fi

: "${DEVELOPER_ID_APP_CERT:?Set DEVELOPER_ID_APP_CERT, for example: Developer ID Application: Your Name (TEAMID)}"
: "${DEVELOPER_ID_INSTALLER_CERT:?Set DEVELOPER_ID_INSTALLER_CERT, for example: Developer ID Installer: Your Name (TEAMID)}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE (created with xcrun notarytool store-credentials)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.0.0)}"
PKG_NAME="spank-${VERSION}-macos-arm64"
UNSIGNED_PKG="dist/pkg/${PKG_NAME}-unsigned.pkg"
SIGNED_PKG="dist/pkg/${PKG_NAME}.pkg"

rm -rf pkgroot dist/pkg
mkdir -p pkgroot/usr/local/bin dist/pkg

GOFLAGS="${GOFLAGS:-}"
GOOS="${GOOS:-darwin}"
GOARCH="${GOARCH:-arm64}"
CGO_ENABLED="${CGO_ENABLED:-0}"
GOOS="$GOOS" GOARCH="$GOARCH" CGO_ENABLED="$CGO_ENABLED" go build ${GOFLAGS} -ldflags "-s -w -X main.version=${VERSION}" -o pkgroot/usr/local/bin/spank .
chmod 755 pkgroot/usr/local/bin/spank

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP_CERT" pkgroot/usr/local/bin/spank

pkgbuild \
  --root pkgroot \
  --identifier com.taigrr.spank \
  --version "$VERSION" \
  --install-location / \
  "$UNSIGNED_PKG"

productsign --sign "$DEVELOPER_ID_INSTALLER_CERT" "$UNSIGNED_PKG" "$SIGNED_PKG"

xcrun notarytool submit "$SIGNED_PKG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$SIGNED_PKG"

shasum -a 256 "$SIGNED_PKG" > dist/pkg/checksums.txt

echo "Done. Notarized package created: $SIGNED_PKG"
echo "Checksum written to: dist/pkg/checksums.txt"
