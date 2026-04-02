#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  build-sing-box-stats.sh <version> <arch> <output-dir>

Arguments:
  version     sing-box upstream version, with or without leading "v"
  arch        linux target arch: amd64 or arm64
  output-dir  directory to place built files

Environment overrides:
  UPSTREAM_REPO        default: https://github.com/SagerNet/sing-box.git
  UPSTREAM_RELEASE_URL default: https://github.com/SagerNet/sing-box/releases/download
  GOOS                default: linux
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 3 ]]; then
    usage >&2
    exit 1
fi

VERSION_INPUT="$1"
ARCH="$2"
OUTPUT_DIR="$3"

GOOS="${GOOS:-linux}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/SagerNet/sing-box.git}"
UPSTREAM_RELEASE_URL="${UPSTREAM_RELEASE_URL:-https://github.com/SagerNet/sing-box/releases/download}"

case "${ARCH}" in
    amd64|arm64)
        ;;
    *)
        echo "unsupported arch: ${ARCH}" >&2
        exit 1
        ;;
esac

VERSION="${VERSION_INPUT#v}"
TAG="v${VERSION}"
WORK_DIR="$(mktemp -d)"
SRC_DIR="${WORK_DIR}/sing-box"
DIST_DIR="${WORK_DIR}/dist"
OFFICIAL_DIR="${WORK_DIR}/official"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${DIST_DIR}" "${OUTPUT_DIR}"

git clone --depth=1 --branch "${TAG}" "${UPSTREAM_REPO}" "${SRC_DIR}"

BUILD_TAGS="$(tr -d '\n' < "${SRC_DIR}/release/DEFAULT_BUILD_TAGS")"
BUILD_TAGS="${BUILD_TAGS},with_purego,with_v2ray_api"
LDFLAGS_SHARED="$(tr -d '\n' < "${SRC_DIR}/release/LDFLAGS")"

pushd "${SRC_DIR}" >/dev/null
CGO_ENABLED=0 \
GOOS="${GOOS}" \
GOARCH="${ARCH}" \
go build -v -trimpath -o "${DIST_DIR}/sing-box" \
    -tags "${BUILD_TAGS}" \
    -ldflags "-X github.com/sagernet/sing-box/constant.Version=${VERSION} ${LDFLAGS_SHARED} -s -w -buildid=" \
    ./cmd/sing-box
popd >/dev/null

OFFICIAL_ARCHIVE="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
curl -fsSL -o "${WORK_DIR}/${OFFICIAL_ARCHIVE}" \
    "${UPSTREAM_RELEASE_URL}/${TAG}/${OFFICIAL_ARCHIVE}"
tar -xzf "${WORK_DIR}/${OFFICIAL_ARCHIVE}" -C "${WORK_DIR}"

if [[ ! -f "${WORK_DIR}/sing-box-${VERSION}-linux-${ARCH}/libcronet.so" ]]; then
    echo "libcronet.so not found in official archive ${OFFICIAL_ARCHIVE}" >&2
    exit 1
fi

cp "${DIST_DIR}/sing-box" "${OUTPUT_DIR}/sing-box"
cp "${WORK_DIR}/sing-box-${VERSION}-linux-${ARCH}/libcronet.so" "${OUTPUT_DIR}/libcronet.so"

cat > "${OUTPUT_DIR}/build-info.json" <<EOF
{
  "upstream_repo": "${UPSTREAM_REPO}",
  "upstream_tag": "${TAG}",
  "target_os": "${GOOS}",
  "target_arch": "${ARCH}",
  "build_tags": "${BUILD_TAGS}",
  "note": "Built from official sing-box source with upstream default Linux purego tags plus with_v2ray_api."
}
EOF

chmod +x "${OUTPUT_DIR}/sing-box"
