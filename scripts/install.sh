#!/usr/bin/env bash
# Install Phron on this machine: detect the platform, download the matching
# registry archive, verify it, put `phron` on PATH, and seed the folders it needs.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/phronexusai/phron-node-registry/main/scripts/install.sh | bash
#   bash install.sh
#   bash install.sh --version 0.1.0
#
# Optional env:
#   PHRON_INDEX_URL   package index (default: GitHub raw versions.json)
#   PHRON_VERSION     pin a version (same as --version)
#   PHRON_BIN_DIR     where to place the binary (default: ~/.local/bin)
#   PHRON_DATA_DIR    Phron data dir (default: ~/.local/share/phron)
#
# Do not use sudo. This is a user install.

set -euo pipefail

INDEX_URL="${PHRON_INDEX_URL:-https://raw.githubusercontent.com/phronexusai/phron-node-registry/main/versions.json}"
RELEASES_PAGE="https://github.com/phronexusai/phron-node-registry/releases"
ISSUES_PAGE="https://github.com/phronexusai/phron-node-registry/issues"

BIN_DIR="${PHRON_BIN_DIR:-${HOME}/.local/bin}"
# systemd workdir used by `phron enroll` / `phron install` when none is passed
WORK_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/phron"
DATA_DIR="${PHRON_DATA_DIR:-$WORK_DIR}"

PINNED_VERSION="${PHRON_VERSION:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Install Phron for this machine.

Usage:
  $(basename "$0") [--version <ver>] [--bin-dir <dir>]
  curl -fsSL <install.sh url> | bash

Options:
  --version <ver>   Install this version instead of the latest for the platform
  --bin-dir <dir>   Install the binary here (default: ~/.local/bin)
  -h, --help        Show this help

Phron currently ships Linux x86_64 builds. Other platforms get a short note
instead of a broken download.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version needs a value"
      PINNED_VERSION="$2"
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || die "--bin-dir needs a value"
      BIN_DIR="$2"
      shift 2
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "need '$1' on PATH to continue"
}

download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 20 \
      -A "phron-install/1" -o "$dest" "$url" \
      || die "download failed: $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=20 -O "$dest" "$url" \
      || die "download failed: $url"
  else
    die "need curl or wget to download Phron"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "need sha256sum or shasum to verify the download"
  fi
}

detect_os() {
  local u
  u="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$u" in
    linux*)            echo linux ;;
    darwin*)           echo darwin ;;
    mingw*|msys*|cygwin*) echo windows ;;
    *)                 echo "$u" ;;
  esac
}

detect_arch() {
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64|amd64)  echo x86_64 ;;
    aarch64|arm64) echo aarch64 ;;
    *)             echo "$a" ;;
  esac
}

# Prints: url<TAB>sha256<TAB>version<TAB>filename
# Exit 2 = no matching package.
pick_package() {
  local index="$1" os="$2" arch="$3" pin="$4"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$index" "$os" "$arch" "$pin" <<'PY' || return $?
import json, sys
path, os_name, arch, pin = sys.argv[1:5]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
pkgs = [
    p for p in data.get("packages", [])
    if p.get("name") == "phron" and p.get("os") == os_name and p.get("arch") == arch
]
if pin:
    pkgs = [p for p in pkgs if str(p.get("version", "")) == pin]
if not pkgs:
    sys.exit(2)
pkg = sorted(pkgs, key=lambda p: str(p.get("version", "")), reverse=True)[0]
for key in ("url", "sha256", "version", "filename"):
    if not pkg.get(key):
        sys.exit(3)
print("\t".join([pkg["url"], pkg["sha256"], str(pkg["version"]), pkg["filename"]]))
PY
    return 0
  fi

  # Minimal fallback when python3 is missing (index format is stable).
  local filename="phron-${os}-${arch}.tar.gz"
  if ! grep -Fq "\"filename\": \"${filename}\"" "$index"; then
    return 2
  fi
  local url sha version
  url="$(grep -oE "https://[^\" ]+/${filename}" "$index" | head -1 || true)"
  sha="$(grep -A8 -F "\"filename\": \"${filename}\"" "$index" | grep -oE '"sha256":[[:space:]]*"[0-9a-f]{64}"' | head -1 | grep -oE '[0-9a-f]{64}' || true)"
  version="$(grep -B12 -F "\"filename\": \"${filename}\"" "$index" | grep -oE '"version":[[:space:]]*"[^"]+"' | tail -1 | sed 's/.*"\([^"]*\)"/\1/' || true)"
  if [[ -n "$pin" && "$version" != "$pin" ]]; then
    return 2
  fi
  [[ -n "$url" && -n "$sha" && -n "$version" ]] || return 3
  printf '%s\t%s\t%s\t%s\n' "$url" "$sha" "$version" "$filename"
}

list_supported() {
  local index="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$index" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
rows = []
for p in data.get("packages", []):
    if p.get("name") != "phron":
        continue
    rows.append("  • %s/%s  —  Phron %s" % (p.get("os","?"), p.get("arch","?"), p.get("version","?")))
if not rows:
    print("  (none listed in the index)")
else:
    print("\n".join(rows))
PY
    return
  fi
  grep -oE 'phron-[a-z0-9]+-[a-z0-9_]+\.tar\.gz' "$index" | sort -u | sed 's/^/  • /' || true
}

platform_hint() {
  local os="$1"
  case "$os" in
    darwin)
      printf '%s\n' "macOS builds are not published yet. A Darwin script can live beside this one later."
      ;;
    windows)
      printf '%s\n' "Windows is not published yet. A PowerShell installer (scripts/install.ps1) can sit beside this script later."
      ;;
    linux)
      printf '%s\n' "A Linux build exists, but not for this CPU. x86_64 (amd64) is the current target."
      ;;
    *)
      printf '%s\n' "This operating system is not in the registry yet."
      ;;
  esac
}

unsupported() {
  local os="$1" arch="$2" index="$3" pin="$4"
  printf '\n'
  printf 'Phron does not yet have a build for %s/%s.\n' "$os" "$arch"
  printf '\n'
  platform_hint "$os"
  printf '\n'
  printf 'Builds listed in the registry right now:\n'
  list_supported "$index"
  if [[ -n "$pin" ]]; then
    printf '\n(You asked for version %s.)\n' "$pin"
  fi
  printf '\n'
  printf 'Detected this machine as %s/%s  (uname: %s / %s).\n' \
    "$os" "$arch" "$(uname -s)" "$(uname -m)"
  printf 'If that looks wrong, please tell us: %s\n' "$ISSUES_PAGE"
  printf 'Published archives: %s\n' "$RELEASES_PAGE"
  printf '\n'
  exit 1
}

need_cmd tar
need_cmd uname
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
  || die "need curl or wget to download Phron"

OS="${PHRON_OS:-$(detect_os)}"
ARCH="${PHRON_ARCH:-$(detect_arch)}"
log "detected ${OS}/${ARCH}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/phron-install.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

INDEX="$TMP/versions.json"
log "reading package index"
download "$INDEX_URL" "$INDEX"

PICK_RC=0
PICK="$(pick_package "$INDEX" "$OS" "$ARCH" "$PINNED_VERSION")" || PICK_RC=$?
if [[ "$PICK_RC" -eq 2 || -z "${PICK:-}" ]]; then
  unsupported "$OS" "$ARCH" "$INDEX" "$PINNED_VERSION"
fi
[[ "$PICK_RC" -eq 0 ]] || die "could not read the package index (need python3, or a well-formed versions.json)"

URL="$(printf '%s' "$PICK" | cut -f1)"
EXPECT_SHA="$(printf '%s' "$PICK" | cut -f2)"
VERSION="$(printf '%s' "$PICK" | cut -f3)"
FILENAME="$(printf '%s' "$PICK" | cut -f4)"

log "Phron ${VERSION}  (${FILENAME})"

ARCHIVE="$TMP/$FILENAME"
log "downloading"
download "$URL" "$ARCHIVE"

GOT_SHA="$(sha256_file "$ARCHIVE")"
[[ "$GOT_SHA" == "$EXPECT_SHA" ]] || die "checksum mismatch for ${FILENAME}
  expected: ${EXPECT_SHA}
  got:      ${GOT_SHA}
  the download may be corrupt — please try again"

EXTRACT="$TMP/extract"
mkdir -p "$EXTRACT"
tar -xzf "$ARCHIVE" -C "$EXTRACT"
[[ -f "$EXTRACT/phron" ]] || die "archive did not contain a phron binary"

mkdir -p "$BIN_DIR" "$WORK_DIR" \
  "$DATA_DIR/engines" "$DATA_DIR/models" "$DATA_DIR/downloads"

cp -f "$EXTRACT/phron" "$BIN_DIR/phron"
chmod 755 "$BIN_DIR/phron"

if ! HELP_OUT="$("$BIN_DIR/phron" --help 2>&1)"; then
  if printf '%s' "$HELP_OUT" | grep -q 'GLIBC_'; then
    die "this Phron build cannot start on this machine (GNU C library is too old)"
  fi
  die "phron did not start:
$HELP_OUT"
fi

if [[ -f "$EXTRACT/config.toml.example" ]]; then
  cp -f "$EXTRACT/config.toml.example" "$WORK_DIR/config.toml.example"
  if [[ ! -f "$WORK_DIR/config.toml" ]]; then
    cp "$EXTRACT/config.toml.example" "$WORK_DIR/config.toml"
    log "wrote ${WORK_DIR}/config.toml"
  else
    log "keeping existing ${WORK_DIR}/config.toml"
  fi
fi

printf '\n'
log "Phron ${VERSION} is installed"
printf '    binary:  %s\n' "${BIN_DIR}/phron"
printf '    config:  %s\n' "${WORK_DIR}/config.toml"
printf '    data:    %s\n' "${DATA_DIR}"
printf '\n'

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *)
    printf 'warning: %s is not on PATH in this shell\n' "$BIN_DIR"
    printf '    Add it with:\n'
    printf '      echo '\''export PATH="%s:$PATH"'\'' >> ~/.profile\n' "$BIN_DIR"
    printf '      export PATH="%s:$PATH"\n' "$BIN_DIR"
    printf '\n'
    ;;
esac

cat <<EOF
Next, enroll this machine from the Nexus register page:

  phron enroll --url "<nexus-api>" --token "nxn_..."

Or try it in the foreground first:

  phron run --config "${WORK_DIR}/config.toml"

EOF
