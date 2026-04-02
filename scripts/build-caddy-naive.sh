#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build-caddy-naive.sh <version> <arch> <output-dir>

Arguments:
  version     Caddy upstream version, with or without leading "v"
  arch        Target architecture: amd64 | arm64
  output-dir  Directory to place built artifacts

Environment:
  XCADDY_VERSION          default: latest
  FORWARDPROXY_REPO       default: https://github.com/klzgrad/forwardproxy.git
  FORWARDPROXY_REF        default: naive
  FORWARDPROXY_COMMIT     optional pinned commit after clone
  FORWARDPROXY_PATCH      default: scripts/patches/forwardproxy-naive-stats.patch
EOF
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 1
fi

VERSION="${1#v}"
ARCH="$2"
OUTPUT_DIR="$3"

case "${ARCH}" in
  amd64|arm64)
    ;;
  *)
    echo "unsupported arch: ${ARCH}" >&2
    exit 1
    ;;
esac

XCADDY_VERSION="${XCADDY_VERSION:-latest}"
FORWARDPROXY_REPO="${FORWARDPROXY_REPO:-https://github.com/klzgrad/forwardproxy.git}"
FORWARDPROXY_REF="${FORWARDPROXY_REF:-naive}"
FORWARDPROXY_COMMIT="${FORWARDPROXY_COMMIT:-}"
FORWARDPROXY_PATCH="${FORWARDPROXY_PATCH:-scripts/patches/forwardproxy-naive-stats.patch}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${FORWARDPROXY_PATCH}" != /* ]]; then
  if [[ -f "${PWD}/${FORWARDPROXY_PATCH}" ]]; then
    FORWARDPROXY_PATCH="${PWD}/${FORWARDPROXY_PATCH}"
  else
    FORWARDPROXY_PATCH="${SCRIPT_DIR}/../${FORWARDPROXY_PATCH}"
  fi
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

go install "github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}"

XCADDY_BIN="$(go env GOPATH)/bin/xcaddy"
if [[ ! -x "${XCADDY_BIN}" ]]; then
  echo "xcaddy not found after installation" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
FORWARDPROXY_DIR="${WORK_DIR}/forwardproxy"

git clone --depth=1 --branch "${FORWARDPROXY_REF}" "${FORWARDPROXY_REPO}" "${FORWARDPROXY_DIR}"
if [[ -n "${FORWARDPROXY_COMMIT}" ]]; then
  git -C "${FORWARDPROXY_DIR}" fetch --depth=1 origin "${FORWARDPROXY_COMMIT}"
  git -C "${FORWARDPROXY_DIR}" checkout "${FORWARDPROXY_COMMIT}"
fi
if [[ -n "${FORWARDPROXY_PATCH}" ]]; then
  if [[ ! -f "${FORWARDPROXY_PATCH}" ]]; then
    echo "forwardproxy patch not found: ${FORWARDPROXY_PATCH}" >&2
    exit 1
  fi
  git -C "${FORWARDPROXY_DIR}" apply "${FORWARDPROXY_PATCH}"
fi

pushd "${WORK_DIR}" >/dev/null
CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" \
  "${XCADDY_BIN}" build "v${VERSION}" \
    --output "${OUTPUT_DIR}/caddy" \
    --with "github.com/caddyserver/forwardproxy=${FORWARDPROXY_DIR}"
popd >/dev/null

cat > "${OUTPUT_DIR}/build-info.json" <<EOF
{
  "version": "${VERSION}",
  "goos": "linux",
  "goarch": "${ARCH}",
  "forwardproxy_repo": "${FORWARDPROXY_REPO}",
  "forwardproxy_ref": "${FORWARDPROXY_REF}",
  "forwardproxy_commit": "${FORWARDPROXY_COMMIT}",
  "forwardproxy_patch": "${FORWARDPROXY_PATCH}",
  "plugin": "github.com/caddyserver/forwardproxy (patched naive branch)",
  "note": "Built from official Caddy source with the naive forward_proxy module plus sx-ui stats patch."
}
EOF

chmod +x "${OUTPUT_DIR}/caddy"
