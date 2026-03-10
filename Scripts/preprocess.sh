#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-ClashMenu}"
TARGET_ARCH="${TARGET_ARCH:-}"
MIHOMO_REPO="${MIHOMO_REPO:-MetaCubeX/mihomo}"
MIHOMO_VERSION="${MIHOMO_VERSION:-}"
DOWNLOAD_MIHOMO="${DOWNLOAD_MIHOMO:-1}"
REUSE_LOCAL_MIHOMO="${REUSE_LOCAL_MIHOMO:-1}"
PREPARE_MIHOMO_BINARY="${PREPARE_MIHOMO_BINARY:-1}"
DOWNLOAD_ZASHBOARD="${DOWNLOAD_ZASHBOARD:-1}"
REUSE_LOCAL_ZASHBOARD="${REUSE_LOCAL_ZASHBOARD:-1}"
PREPARE_ZASHBOARD="${PREPARE_ZASHBOARD:-1}"
ZASHBOARD_URL="${ZASHBOARD_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}"
PREPROCESS_DIR="${PREPROCESS_DIR:-$ROOT/dist/preprocess}"

MIHOMO_RESOURCE_PATH="$ROOT/Sources/ClashBar/Resources/bin/mihomo"
PREPROCESSED_MIHOMO_PATH="$PREPROCESS_DIR/mihomo"
ZASHBOARD_RESOURCE_PATH="$ROOT/Sources/ClashBar/Resources/zashboard"
PREPROCESSED_ZASHBOARD_PATH="$PREPROCESS_DIR/zashboard"
ICON_SOURCE="$ROOT/Sources/ClashBar/Resources/Brand/clashbar-icon.png"
PREPROCESSED_ICON_PATH="$PREPROCESS_DIR/${APP_NAME}.icns"
MIHOMO_TMP_DIR=""
ZASHBOARD_TMP_DIR=""

cleanup() {
  if [ -n "$MIHOMO_TMP_DIR" ]; then
    rm -rf "$MIHOMO_TMP_DIR"
  fi
  if [ -n "$ZASHBOARD_TMP_DIR" ]; then
    rm -rf "$ZASHBOARD_TMP_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$PREPROCESS_DIR"

is_mach_o_binary() {
  local path="$1"
  local file_desc
  file_desc="$(file "$path" 2>/dev/null || true)"
  [[ "$file_desc" == *"Mach-O"* ]]
}

resolve_target_arch() {
  local requested="$TARGET_ARCH"
  if [ -z "$requested" ]; then
    requested="$(uname -m)"
  fi

  case "$requested" in
    x86_64 | amd64) echo "x86_64" ;;
    arm64 | aarch64) echo "arm64" ;;
    *)
      echo "Unsupported architecture for mihomo asset selection: $requested" >&2
      exit 1
      ;;
  esac
}

resolve_mihomo_asset_candidates() {
  local arch="$1"
  case "$arch" in
    x86_64)
      cat <<EOF
mihomo-darwin-amd64-v2-go122-${MIHOMO_VERSION}.gz
mihomo-darwin-amd64-${MIHOMO_VERSION}.gz
EOF
      ;;
    arm64)
      cat <<EOF
mihomo-darwin-arm64-go122-${MIHOMO_VERSION}.gz
mihomo-darwin-arm64-${MIHOMO_VERSION}.gz
EOF
      ;;
    *)
      echo "Unsupported architecture for mihomo asset selection: $arch" >&2
      exit 1
      ;;
  esac
}

resolve_mihomo_version() {
  if [ -z "$MIHOMO_VERSION" ]; then
    MIHOMO_VERSION="$(curl -fsSL "https://github.com/${MIHOMO_REPO}/releases/latest/download/version.txt" | tr -d '\r\n')"
  fi

  if [[ "$MIHOMO_VERSION" != v* ]]; then
    MIHOMO_VERSION="v${MIHOMO_VERSION}"
  fi
}

download_mihomo_binary() {
  local arch="$1"
  local base_url="https://github.com/${MIHOMO_REPO}/releases/download/${MIHOMO_VERSION}"
  local archive_path=""
  local extracted_path=""
  local asset_name=""
  local candidate=""
  local candidate_url=""

  MIHOMO_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.mihomo.XXXXXX")"
  archive_path="$MIHOMO_TMP_DIR/mihomo.gz"
  extracted_path="$MIHOMO_TMP_DIR/mihomo"

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    candidate_url="${base_url}/${candidate}"
    if curl -fsSL "$candidate_url" -o "$archive_path"; then
      asset_name="$candidate"
      break
    fi
  done < <(resolve_mihomo_asset_candidates "$arch")

  if [ -z "$asset_name" ]; then
    echo "Failed to download mihomo asset for arch: $arch (version: $MIHOMO_VERSION)." >&2
    echo "Tried candidates:" >&2
    resolve_mihomo_asset_candidates "$arch" | sed 's/^/  - /' >&2
    exit 1
  fi

  gunzip -c "$archive_path" > "$extracted_path"
  install -m 755 "$extracted_path" "$PREPROCESSED_MIHOMO_PATH"

  echo "Prepared mihomo asset: $asset_name"
  echo "Prepared mihomo path: $PREPROCESSED_MIHOMO_PATH"
}

prepare_mihomo() {
  mkdir -p "$(dirname "$MIHOMO_RESOURCE_PATH")"

  if [ "$REUSE_LOCAL_MIHOMO" = "1" ] && [ -f "$MIHOMO_RESOURCE_PATH" ] && is_mach_o_binary "$MIHOMO_RESOURCE_PATH"; then
    install -m 755 "$MIHOMO_RESOURCE_PATH" "$PREPROCESSED_MIHOMO_PATH"
    echo "Prepared mihomo from local resource: $MIHOMO_RESOURCE_PATH"
    echo "Prepared mihomo path: $PREPROCESSED_MIHOMO_PATH"
  else
    if [ "$DOWNLOAD_MIHOMO" != "1" ]; then
      echo "Local mihomo binary is missing or invalid, and DOWNLOAD_MIHOMO=$DOWNLOAD_MIHOMO." >&2
      echo "Provide a real Mach-O binary at $MIHOMO_RESOURCE_PATH or enable download." >&2
      exit 1
    fi

    resolve_mihomo_version
    download_mihomo_binary "$(resolve_target_arch)"
  fi

  if ! is_mach_o_binary "$PREPROCESSED_MIHOMO_PATH"; then
    echo "Prepared mihomo is not a valid Mach-O binary: $PREPROCESSED_MIHOMO_PATH" >&2
    exit 1
  fi

  install -m 755 "$PREPROCESSED_MIHOMO_PATH" "$MIHOMO_RESOURCE_PATH"
  echo "Updated source mihomo resource: $MIHOMO_RESOURCE_PATH"
}

is_dashboard_bundle() {
  local path="$1"
  [ -f "$path/index.html" ]
}

install_dashboard_bundle() {
  local source_path="$1"
  local target_path="$2"

  rm -rf "$target_path"
  mkdir -p "$(dirname "$target_path")"
  ditto "$source_path" "$target_path"
}

download_zashboard() {
  local archive_path=""
  local extract_dir=""
  local dashboard_root=""

  ZASHBOARD_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.zashboard.XXXXXX")"
  archive_path="$ZASHBOARD_TMP_DIR/zashboard.zip"
  extract_dir="$ZASHBOARD_TMP_DIR/extracted"
  mkdir -p "$extract_dir"

  curl -fsSL "$ZASHBOARD_URL" -o "$archive_path"
  ditto -x -k "$archive_path" "$extract_dir"

  dashboard_root="$(find "$extract_dir" -type f -name 'index.html' -print | head -n 1 || true)"
  if [ -z "$dashboard_root" ]; then
    echo "Failed to locate zashboard index.html in downloaded archive." >&2
    exit 1
  fi

  dashboard_root="$(dirname "$dashboard_root")"
  install_dashboard_bundle "$dashboard_root" "$PREPROCESSED_ZASHBOARD_PATH"

  echo "Prepared zashboard path: $PREPROCESSED_ZASHBOARD_PATH"
}

prepare_zashboard() {
  if [ "$REUSE_LOCAL_ZASHBOARD" = "1" ] && is_dashboard_bundle "$ZASHBOARD_RESOURCE_PATH"; then
    install_dashboard_bundle "$ZASHBOARD_RESOURCE_PATH" "$PREPROCESSED_ZASHBOARD_PATH"
    echo "Prepared zashboard from local resource: $ZASHBOARD_RESOURCE_PATH"
  else
    if [ "$DOWNLOAD_ZASHBOARD" != "1" ]; then
      echo "Local zashboard bundle is missing or invalid, and DOWNLOAD_ZASHBOARD=$DOWNLOAD_ZASHBOARD." >&2
      echo "Provide a valid dashboard bundle at $ZASHBOARD_RESOURCE_PATH or enable download." >&2
      exit 1
    fi

    download_zashboard
  fi

  if ! is_dashboard_bundle "$PREPROCESSED_ZASHBOARD_PATH"; then
    echo "Prepared zashboard bundle is invalid: $PREPROCESSED_ZASHBOARD_PATH" >&2
    exit 1
  fi

  install_dashboard_bundle "$PREPROCESSED_ZASHBOARD_PATH" "$ZASHBOARD_RESOURCE_PATH"
  echo "Updated source zashboard resource: $ZASHBOARD_RESOURCE_PATH"
}

prepare_icon() {
  if [ ! -f "$ICON_SOURCE" ]; then
    echo "Warning: app icon source not found at $ICON_SOURCE"
    return
  fi

  local iconset_work_dir
  local iconset_dir
  iconset_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/clashmenu.iconset.XXXXXX")"
  iconset_dir="${iconset_work_dir}.iconset"
  mv "$iconset_work_dir" "$iconset_dir"

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    local double_size
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$ICON_SOURCE" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
  done

  if iconutil --convert icns "$iconset_dir" --output "$PREPROCESSED_ICON_PATH"; then
    echo "Prepared app icon: $PREPROCESSED_ICON_PATH"
  else
    echo "Warning: failed to generate .icns from $ICON_SOURCE"
    rm -f "$PREPROCESSED_ICON_PATH"
  fi

  rm -rf "$iconset_dir"
}

if [ "$PREPARE_MIHOMO_BINARY" = "1" ]; then
  prepare_mihomo
else
  rm -f "$PREPROCESSED_MIHOMO_PATH"
  echo "Skipping mihomo preprocessing because PREPARE_MIHOMO_BINARY=$PREPARE_MIHOMO_BINARY"
fi

if [ "$PREPARE_ZASHBOARD" = "1" ]; then
  prepare_zashboard
else
  rm -rf "$PREPROCESSED_ZASHBOARD_PATH"
  echo "Skipping zashboard preprocessing because PREPARE_ZASHBOARD=$PREPARE_ZASHBOARD"
fi

prepare_icon
