#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/YamiboReader.xcodeproj"
SCHEME="YamiboReader"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${ROOT_DIR}/build/UnsignedIPA"
EXPORT_DIR="${ROOT_DIR}/build/UnsignedIPAExport"
STAGING_DIR="${EXPORT_DIR}/staging"
SWIFT_OPTIMIZATION_LEVEL="${SWIFT_OPTIMIZATION_LEVEL:--Onone}"

cd "${ROOT_DIR}"

echo "Building ${SCHEME} (${CONFIGURATION}) for iphoneos without code signing..."
echo "Swift optimization level: ${SWIFT_OPTIMIZATION_LEVEL}"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  SWIFT_OPTIMIZATION_LEVEL="${SWIFT_OPTIMIZATION_LEVEL}" \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app bundle not found: ${APP_PATH}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Info.plist")"
if [[ -z "${VERSION}" ]]; then
  echo "error: failed to read CFBundleShortVersionString from built app" >&2
  exit 1
fi

IPA_PATH="${EXPORT_DIR}/YamiboReader_v${VERSION}_unsigned.ipa"

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/Payload"
cp -R "${APP_PATH}" "${STAGING_DIR}/Payload/"

(
  cd "${STAGING_DIR}"
  zip -qry -X "${IPA_PATH}" Payload
)

if find "${STAGING_DIR}/Payload/${SCHEME}.app" -name "_CodeSignature" -print -quit | grep -q .; then
  echo "warning: _CodeSignature exists in staged app; output may not be unsigned" >&2
fi

if codesign -dv "${STAGING_DIR}/Payload/${SCHEME}.app" >/dev/null 2>&1; then
  echo "warning: staged app appears to be signed" >&2
fi

echo "Unsigned IPA exported:"
echo "${IPA_PATH}"
echo
echo "Release checklist:"
echo "- Upload the IPA to GitHub Releases."
echo "- Update app-repo.json versions[0].version to ${VERSION}."
echo "- Update app-repo.json versions[0].downloadURL to the release asset URL."
echo "- Update app-repo.json versions[0].size to $(stat -f%z "${IPA_PATH}") bytes."
