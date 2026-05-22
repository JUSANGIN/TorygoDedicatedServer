#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="torygo-host-agent"
SERVICE_USER="${TORYGO_SERVICE_USER:-torygo}"
SERVICE_GROUP="${TORYGO_SERVICE_GROUP:-torygo}"
INSTALL_ROOT="${TORYGO_INSTALL_ROOT:-/opt/torygo}"
CONFIG_DIR="${TORYGO_CONFIG_DIR:-/etc/torygo}"
DATA_DIR="${TORYGO_DATA_DIR:-/var/lib/torygo}"
STATE_DIR_IS_EXPLICIT="0"
if [[ -n "${TORYGO_AGENT_STATE_DIR+x}" ]]; then
  STATE_DIR_IS_EXPLICIT="1"
fi
STATE_DIR="${TORYGO_AGENT_STATE_DIR:-$DATA_DIR/host-agent}"
SYSTEMD_UNIT_DIR="${TORYGO_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
ALLOW_NON_ROOT_DRY_RUN="${TORYGO_ALLOW_NON_ROOT_DRY_RUN:-0}"

HOST_AGENT_URL="${TORYGO_HOST_AGENT_URL:-}"
RUNTIME_URL="${TORYGO_DEDICATED_RUNTIME_URL:-}"
ARTIFACT_BASE_URL="${TORYGO_ARTIFACT_BASE_URL:-}"
RELEASE_MANIFEST_URL="${TORYGO_RELEASE_MANIFEST_URL:-}"
DEFAULT_RELEASE_MANIFEST_URL="${TORYGO_DEFAULT_RELEASE_MANIFEST_URL:-https://raw.githubusercontent.com/JUSANGIN/TorygoDedicatedServer/main/releases/dedicated-release-manifest.json}"
RELEASE_CHANNEL="${TORYGO_RELEASE_CHANNEL:-stable}"
RELEASE_VERSION="${TORYGO_RELEASE_VERSION:-}"
RESOLVED_RELEASE_CHANNEL=""
RESOLVED_RELEASE_VERSION=""
HOST_AGENT_SHA256="${TORYGO_HOST_AGENT_SHA256:-}"
RUNTIME_SHA256="${TORYGO_DEDICATED_RUNTIME_SHA256:-}"
HOST_AGENT_SHA256_URL="${TORYGO_HOST_AGENT_SHA256_URL:-}"
RUNTIME_SHA256_URL="${TORYGO_DEDICATED_RUNTIME_SHA256_URL:-}"
ACTIVATION_KEY="${TORYGO_ACTIVATION_KEY:-}"
CENTRAL_CONTROL_URL="${TORYGO_CENTRAL_CONTROL_URL:-https://gateway.invalid/torygo/control}"
GATEWAY_TUNNEL_URL="${TORYGO_GATEWAY_TUNNEL_URL:-wss://gateway.invalid/torygo/tunnel}"
AGENT_DRY_RUN="${TORYGO_AGENT_DRY_RUN:-0}"
RUNTIME_BIND_ADDR="${TORYGO_RUNTIME_BIND_ADDR:-127.0.0.1:7777}"
RUNTIME_HEALTH_URL="${TORYGO_RUNTIME_HEALTH_URL:-http://127.0.0.1:7777/health}"
RUNTIME_WS_URL="${TORYGO_RUNTIME_WS_URL:-ws://127.0.0.1:7777/ws}"
RUNTIME_HEALTH_CHECK_TIMEOUT_MS="${TORYGO_RUNTIME_HEALTH_CHECK_TIMEOUT_MS:-1500}"
HEARTBEAT_SECS="${TORYGO_AGENT_HEARTBEAT_SECS:-15}"
GATEWAY_CONNECT_TIMEOUT_SECS="${TORYGO_GATEWAY_CONNECT_TIMEOUT_SECS:-10}"
GATEWAY_SEND_TIMEOUT_SECS="${TORYGO_GATEWAY_SEND_TIMEOUT_SECS:-5}"
GATEWAY_RECONNECT_MIN_SECS="${TORYGO_GATEWAY_RECONNECT_MIN_SECS:-10}"
GATEWAY_RECONNECT_MAX_SECS="${TORYGO_GATEWAY_RECONNECT_MAX_SECS:-120}"

HOST_AGENT_DIR="$INSTALL_ROOT/host-agent"
RUNTIME_DIR="$INSTALL_ROOT/dedicated-runtime"
HOST_AGENT_BIN="$HOST_AGENT_DIR/torygo-host-agent"
RUNTIME_BIN="$RUNTIME_DIR/torygo-dedicated-server"
ENV_FILE="$CONFIG_DIR/host-agent.env"
UNIT_PATH="$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service"

usage() {
  cat <<'USAGE'
Usage:
  curl -fsSL https://artifact.example/install-dedicated-server.sh | sudo bash -s -- \
    --central-control-url https://gateway.example/control \
    --gateway-tunnel-url wss://gateway.example/tunnel \
    --gateway-reconnect-min-secs 10 \
    --gateway-reconnect-max-secs 120 \
    --config-dir /etc/torygo \
    --data-dir /var/lib/torygo \
    --systemd-unit-dir /etc/systemd/system \
    --activation-key one-time-key

Environment variables:
  TORYGO_HOST_AGENT_URL, TORYGO_DEDICATED_RUNTIME_URL
  TORYGO_ARTIFACT_BASE_URL
  TORYGO_RELEASE_MANIFEST_URL, TORYGO_DEFAULT_RELEASE_MANIFEST_URL
  TORYGO_RELEASE_CHANNEL, TORYGO_RELEASE_VERSION
  TORYGO_HOST_AGENT_SHA256, TORYGO_DEDICATED_RUNTIME_SHA256
  TORYGO_HOST_AGENT_SHA256_URL, TORYGO_DEDICATED_RUNTIME_SHA256_URL
  TORYGO_ACTIVATION_KEY
  TORYGO_CENTRAL_CONTROL_URL, TORYGO_GATEWAY_TUNNEL_URL
  TORYGO_GATEWAY_CONNECT_TIMEOUT_SECS, TORYGO_GATEWAY_SEND_TIMEOUT_SECS
  TORYGO_GATEWAY_RECONNECT_MIN_SECS, TORYGO_GATEWAY_RECONNECT_MAX_SECS
  TORYGO_RUNTIME_HEALTH_CHECK_TIMEOUT_MS
  TORYGO_AGENT_DRY_RUN=1 for local control-plane stubs
  TORYGO_ALLOW_NON_ROOT_DRY_RUN=1 only for local --dry-run harnesses with
  non-system install/config/data/systemd directories

If the official hosted installer has a default release manifest URL embedded,
or --release-manifest-url is provided, the installer downloads the manifest,
selects the current Linux architecture, verifies the requested channel/version,
and resolves Host Agent/Dedicated Runtime URLs and SHA256 pins automatically.

If --artifact-base-url is provided, the official layout is:
  <base>/linux-x64/torygo-host-agent
  <base>/linux-x64/torygo-host-agent.sha256
  <base>/linux-x64/torygo-dedicated-server
  <base>/linux-x64/torygo-dedicated-server.sha256
and the same paths under linux-arm64 for ARM64 Linux hosts.

URL templates may contain:
  {arch}   linux-x64 or linux-arm64
  {target} x86_64-unknown-linux-gnu or aarch64-unknown-linux-gnu

This installer does not configure nginx, a domain, certificates, reverse
proxies, or port forwarding. The host agent uses outbound connections to the
central Gateway and manages the local dedicated runtime under /opt/torygo.
USAGE
}

fail() {
  echo "[torygo-install] ERROR: $*" >&2
  exit 1
}

log() {
  echo "[torygo-install] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-agent-url)
      HOST_AGENT_URL="${2:-}"
      shift 2
      ;;
    --runtime-url)
      RUNTIME_URL="${2:-}"
      shift 2
      ;;
    --host-agent-sha256)
      HOST_AGENT_SHA256="${2:-}"
      shift 2
      ;;
    --runtime-sha256)
      RUNTIME_SHA256="${2:-}"
      shift 2
      ;;
    --host-agent-sha256-url)
      HOST_AGENT_SHA256_URL="${2:-}"
      shift 2
      ;;
    --runtime-sha256-url)
      RUNTIME_SHA256_URL="${2:-}"
      shift 2
      ;;
    --artifact-base-url)
      ARTIFACT_BASE_URL="${2:-}"
      shift 2
      ;;
    --release-manifest-url)
      RELEASE_MANIFEST_URL="${2:-}"
      shift 2
      ;;
    --release-channel)
      RELEASE_CHANNEL="${2:-}"
      shift 2
      ;;
    --release-version)
      RELEASE_VERSION="${2:-}"
      shift 2
      ;;
    --activation-key)
      ACTIVATION_KEY="${2:-}"
      shift 2
      ;;
    --central-control-url)
      CENTRAL_CONTROL_URL="${2:-}"
      shift 2
      ;;
    --gateway-tunnel-url)
      GATEWAY_TUNNEL_URL="${2:-}"
      shift 2
      ;;
    --gateway-reconnect-min-secs)
      GATEWAY_RECONNECT_MIN_SECS="${2:-}"
      shift 2
      ;;
    --gateway-reconnect-max-secs)
      GATEWAY_RECONNECT_MAX_SECS="${2:-}"
      shift 2
      ;;
    --dry-run)
      AGENT_DRY_RUN="1"
      shift
      ;;
    --install-root)
      INSTALL_ROOT="${2:-}"
      HOST_AGENT_DIR="$INSTALL_ROOT/host-agent"
      RUNTIME_DIR="$INSTALL_ROOT/dedicated-runtime"
      HOST_AGENT_BIN="$HOST_AGENT_DIR/torygo-host-agent"
      RUNTIME_BIN="$RUNTIME_DIR/torygo-dedicated-server"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="${2:-}"
      ENV_FILE="$CONFIG_DIR/host-agent.env"
      shift 2
      ;;
    --data-dir)
      DATA_DIR="${2:-}"
      if [[ "$STATE_DIR_IS_EXPLICIT" != "1" ]]; then
        STATE_DIR="$DATA_DIR/host-agent"
      fi
      shift 2
      ;;
    --systemd-unit-dir)
      SYSTEMD_UNIT_DIR="${2:-}"
      UNIT_PATH="$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service"
      shift 2
      ;;
    --allow-non-root-dry-run)
      ALLOW_NON_ROOT_DRY_RUN="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

is_system_path() {
  local value="${1%/}"
  case "$value" in
    ""|/|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/lib|/lib/*|/lib64|/lib64/*|/opt|/opt/*|/proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/sys|/sys/*|/usr|/usr/*|/var|/var/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_non_root_dry_run_path() {
  local label="$1"
  local value="$2"
  if is_system_path "$value"; then
    fail "$label must not target a system path when --allow-non-root-dry-run is used: $value"
  fi
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if [[ "$AGENT_DRY_RUN" == "1" && "$ALLOW_NON_ROOT_DRY_RUN" == "1" ]]; then
    assert_non_root_dry_run_path "Install root" "$INSTALL_ROOT"
    assert_non_root_dry_run_path "Config dir" "$CONFIG_DIR"
    assert_non_root_dry_run_path "Data dir" "$DATA_DIR"
    assert_non_root_dry_run_path "Systemd unit dir" "$SYSTEMD_UNIT_DIR"
    log "Running local non-root dry-run install harness."
  else
    fail "Run this installer as root, for example with sudo."
  fi
fi

ensure_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing missing prerequisite: $command_name"
    apt-get update
    apt-get install -y "$command_name"
    return
  fi

  fail "Missing required command: $command_name"
}

detect_arch() {
  local machine
  machine="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$machine" in
    x86_64|amd64)
      echo "linux-x64:x86_64-unknown-linux-gnu"
      ;;
    aarch64|arm64)
      echo "linux-arm64:aarch64-unknown-linux-gnu"
      ;;
    *)
      fail "Unsupported Linux architecture: $machine"
      ;;
  esac
}

arch_info="$(detect_arch)"
ARCH_TOKEN="${arch_info%%:*}"
RUST_TARGET="${arch_info##*:}"

resolve_url_template() {
  local value="$1"
  value="${value//\{arch\}/$ARCH_TOKEN}"
  value="${value//\{target\}/$RUST_TARGET}"
  value="${value//\{platform\}/linux}"
  printf '%s' "$value"
}

RELEASE_MANIFEST_URL="$(resolve_url_template "$RELEASE_MANIFEST_URL")"
DEFAULT_RELEASE_MANIFEST_URL="$(resolve_url_template "$DEFAULT_RELEASE_MANIFEST_URL")"

if [[ -z "$HOST_AGENT_URL" && -n "$ARTIFACT_BASE_URL" ]]; then
  HOST_AGENT_URL="${ARTIFACT_BASE_URL%/}/$ARCH_TOKEN/torygo-host-agent"
fi

if [[ -z "$RUNTIME_URL" && -n "$ARTIFACT_BASE_URL" ]]; then
  RUNTIME_URL="${ARTIFACT_BASE_URL%/}/$ARCH_TOKEN/torygo-dedicated-server"
fi

if [[ -z "$HOST_AGENT_SHA256" && -z "$HOST_AGENT_SHA256_URL" && -n "$ARTIFACT_BASE_URL" ]]; then
  HOST_AGENT_SHA256_URL="${ARTIFACT_BASE_URL%/}/$ARCH_TOKEN/torygo-host-agent.sha256"
fi

if [[ -z "$RUNTIME_SHA256" && -z "$RUNTIME_SHA256_URL" && -n "$ARTIFACT_BASE_URL" ]]; then
  RUNTIME_SHA256_URL="${ARTIFACT_BASE_URL%/}/$ARCH_TOKEN/torygo-dedicated-server.sha256"
fi

HOST_AGENT_URL="$(resolve_url_template "$HOST_AGENT_URL")"
RUNTIME_URL="$(resolve_url_template "$RUNTIME_URL")"
HOST_AGENT_SHA256_URL="$(resolve_url_template "$HOST_AGENT_SHA256_URL")"
RUNTIME_SHA256_URL="$(resolve_url_template "$RUNTIME_SHA256_URL")"

is_placeholder_value() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$value" \
    || "$value" == *"example.com"* \
    || "$value" == *"your_official_artifact_host"* \
    || "$value" == *"replace-me"* \
    || "$value" == *"placeholder"* \
    || "$value" == *"gateway.invalid"* \
    || "$value" == *"__"* ]]
}

assert_download_url() {
  local label="$1"
  local url="$2"
  if is_placeholder_value "$url"; then
    fail "$label URL is empty or still a placeholder. Set a real artifact URL."
  fi
  case "$url" in
    https://*|http://*) ;;
    *) fail "$label URL must start with http:// or https://: $url" ;;
  esac
}

assert_url_matches_detected_platform() {
  local label="$1"
  local url="$2"
  if [[ -z "$url" ]]; then
    return
  fi

  case "$ARCH_TOKEN" in
    linux-x64)
      if [[ "$url" == *"linux-arm64"* ]]; then
        fail "$label URL points at linux-arm64, but this host requires linux-x64: $url"
      fi
      ;;
    linux-arm64)
      if [[ "$url" == *"linux-x64"* ]]; then
        fail "$label URL points at linux-x64, but this host requires linux-arm64: $url"
      fi
      ;;
  esac
}

assert_control_endpoint() {
  local label="$1"
  local url="$2"
  if [[ "$AGENT_DRY_RUN" == "1" ]]; then
    return
  fi
  if is_placeholder_value "$url"; then
    fail "$label is still a placeholder. Use --dry-run only for local control-plane stubs."
  fi
}

if [[ -z "$RELEASE_MANIFEST_URL" ]]; then
  if ! is_placeholder_value "$DEFAULT_RELEASE_MANIFEST_URL"; then
    RELEASE_MANIFEST_URL="$DEFAULT_RELEASE_MANIFEST_URL"
    log "Using default release manifest URL embedded in the installer entrypoint."
  fi
fi

needs_release_manifest_resolution() {
  [[ -n "$RELEASE_MANIFEST_URL" \
    && ( -z "$HOST_AGENT_URL" \
      || -z "$RUNTIME_URL" \
      || ( -z "$HOST_AGENT_SHA256" && -z "$HOST_AGENT_SHA256_URL" ) \
      || ( -z "$RUNTIME_SHA256" && -z "$RUNTIME_SHA256_URL" ) ) ]]
}

load_release_manifest() {
  local tmp_file
  local assignment_file

  tmp_file="$(mktemp)"
  assignment_file="$(mktemp)"
  log "Downloading release manifest: $RELEASE_MANIFEST_URL"
  if ! curl -fsSL "$RELEASE_MANIFEST_URL" -o "$tmp_file"; then
    rm -f "$tmp_file" "$assignment_file"
    fail "Failed to download release manifest."
  fi

  if ! python3 - "$tmp_file" "$RELEASE_MANIFEST_URL" "$ARCH_TOKEN" "$RELEASE_CHANNEL" "$RELEASE_VERSION" > "$assignment_file" <<'PY'
import json
import re
import shlex
import sys
from urllib.parse import urljoin

manifest_path, manifest_url, arch_token, requested_channel, requested_version = sys.argv[1:6]

with open(manifest_path, "r", encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)

channel = str(manifest.get("channel", "")).strip()
version = str(manifest.get("version", "")).strip()

if not channel:
    raise SystemExit("release manifest channel is missing")

if not version:
    raise SystemExit("release manifest version is missing")

if requested_channel.strip() and channel != requested_channel.strip():
    raise SystemExit("release manifest channel mismatch")

if requested_version.strip() and version != requested_version.strip():
    raise SystemExit("release manifest version mismatch")

platforms = manifest.get("artifacts")
if not isinstance(platforms, dict):
    raise SystemExit("release manifest artifacts map is missing")

platform = platforms.get(arch_token)
if not isinstance(platform, dict):
    raise SystemExit("release manifest does not include the detected platform")

def read_artifact(key):
    artifact = platform.get(key)
    if not isinstance(artifact, dict):
        raise SystemExit(f"release manifest artifact is missing: {key}")

    location = str(artifact.get("url") or artifact.get("path") or "").strip()
    checksum = str(artifact.get("sha256") or "").strip().lower()

    if not location:
        raise SystemExit(f"release manifest artifact URL/path is missing: {key}")

    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise SystemExit(f"release manifest artifact SHA256 is invalid: {key}")

    return urljoin(manifest_url, location), checksum

host_agent_url, host_agent_sha256 = read_artifact("hostAgent")
runtime_url, runtime_sha256 = read_artifact("dedicatedRuntime")

def emit(name, value):
    print(f"{name}={shlex.quote(value)}")

emit("MANIFEST_HOST_AGENT_URL", host_agent_url)
emit("MANIFEST_RUNTIME_URL", runtime_url)
emit("MANIFEST_HOST_AGENT_SHA256", host_agent_sha256)
emit("MANIFEST_RUNTIME_SHA256", runtime_sha256)
emit("MANIFEST_RELEASE_CHANNEL", channel)
emit("MANIFEST_RELEASE_VERSION", version)
PY
  then
    rm -f "$tmp_file" "$assignment_file"
    fail "Failed to parse release manifest."
  fi

  # shellcheck disable=SC1090
  . "$assignment_file"
  rm -f "$tmp_file" "$assignment_file"

  if [[ -z "$HOST_AGENT_URL" ]]; then
    HOST_AGENT_URL="$MANIFEST_HOST_AGENT_URL"
  fi
  if [[ -z "$RUNTIME_URL" ]]; then
    RUNTIME_URL="$MANIFEST_RUNTIME_URL"
  fi
  if [[ -z "$HOST_AGENT_SHA256" && -z "$HOST_AGENT_SHA256_URL" ]]; then
    HOST_AGENT_SHA256="$MANIFEST_HOST_AGENT_SHA256"
  fi
  if [[ -z "$RUNTIME_SHA256" && -z "$RUNTIME_SHA256_URL" ]]; then
    RUNTIME_SHA256="$MANIFEST_RUNTIME_SHA256"
  fi
  RESOLVED_RELEASE_CHANNEL="$MANIFEST_RELEASE_CHANNEL"
  RESOLVED_RELEASE_VERSION="$MANIFEST_RELEASE_VERSION"
  log "Using release manifest channel=$RESOLVED_RELEASE_CHANNEL version=$RESOLVED_RELEASE_VERSION platform=$ARCH_TOKEN"
}

if needs_release_manifest_resolution; then
  assert_download_url "Release manifest" "$RELEASE_MANIFEST_URL"
  ensure_command curl
  ensure_command python3
  load_release_manifest
fi

assert_download_url "Host Agent artifact" "$HOST_AGENT_URL"
assert_download_url "Dedicated Runtime artifact" "$RUNTIME_URL"
assert_url_matches_detected_platform "Host Agent artifact" "$HOST_AGENT_URL"
assert_url_matches_detected_platform "Dedicated Runtime artifact" "$RUNTIME_URL"
if [[ -n "$HOST_AGENT_SHA256_URL" ]]; then
  assert_download_url "Host Agent checksum" "$HOST_AGENT_SHA256_URL"
  assert_url_matches_detected_platform "Host Agent checksum" "$HOST_AGENT_SHA256_URL"
fi
if [[ -n "$RUNTIME_SHA256_URL" ]]; then
  assert_download_url "Dedicated Runtime checksum" "$RUNTIME_SHA256_URL"
  assert_url_matches_detected_platform "Dedicated Runtime checksum" "$RUNTIME_SHA256_URL"
fi
assert_control_endpoint "Central control endpoint" "$CENTRAL_CONTROL_URL"

if [[ "$AGENT_DRY_RUN" != "1" ]] && is_placeholder_value "$GATEWAY_TUNNEL_URL"; then
  log "WARNING: Gateway tunnel endpoint is a placeholder; activation response must provide gatewayTunnelUrl."
fi

IDENTITY_FILE="$STATE_DIR/identity.json"
RELEASE_PROVENANCE_FILE="$STATE_DIR/install-release-provenance.json"

if [[ "$AGENT_DRY_RUN" != "1" && -z "${ACTIVATION_KEY// }" && -s "$IDENTITY_FILE" ]]; then
  log "Existing Host Agent identity found; activation key is not required for this run."
fi

if [[ "$AGENT_DRY_RUN" != "1" && -z "${ACTIVATION_KEY// }" && ! -s "$IDENTITY_FILE" ]]; then
  if [[ -t 0 ]]; then
    read -rsp "Torygo activation key: " ACTIVATION_KEY
    echo
  else
    fail "Activation key is required. Pass --activation-key or set TORYGO_ACTIVATION_KEY."
  fi
fi

ensure_sha256sum() {
  if command -v sha256sum >/dev/null 2>&1; then
    return
  fi

  fail "Missing required command: sha256sum. Install coreutils or omit checksum validation only for non-production dry runs."
}

normalize_sha256_value() {
  local raw="$1"
  local first_line="${raw%%$'\n'*}"
  first_line="${first_line%$'\r'}"

  if [[ "$first_line" =~ ^[[:space:]]*([A-Fa-f0-9]{64})([[:space:]].*)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

load_checksum_from_url() {
  local result_var="$1"
  local label="$2"
  local url="$3"
  local tmp_file
  local raw
  local parsed

  tmp_file="$(mktemp)"
  log "Downloading $label SHA256 checksum: $url"
  if ! curl -fsSL "$url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    fail "Failed to download $label checksum."
  fi

  raw="$(< "$tmp_file")"
  rm -f "$tmp_file"

  if ! parsed="$(normalize_sha256_value "$raw")"; then
    fail "$label checksum content must be either a 64-character hex string or sha256sum output."
  fi

  printf -v "$result_var" '%s' "$parsed"
}

verify_checksum() {
  local label="$1"
  local file_path="$2"
  local expected_sha256="$3"
  local normalized_sha256

  if [[ -z "${expected_sha256// }" ]]; then
    log "WARNING: $label checksum was not provided. Continuing, but official validation should pass a SHA256 value."
    return 0
  fi

  if ! normalized_sha256="$(normalize_sha256_value "$expected_sha256")"; then
    fail "$label SHA256 must be a 64-character hex string or sha256sum output."
  fi

  ensure_sha256sum
  log "Verifying $label SHA256 checksum"
  printf '%s  %s\n' "$normalized_sha256" "$file_path" | sha256sum -c - >/dev/null
}

file_byte_length() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    printf '0'
    return
  fi

  wc -c < "$file_path" | tr -d '[:space:]'
}

string_byte_length() {
  local value="$1"
  printf '%s' "$value" | wc -c | tr -d '[:space:]'
}

sha256_matches_file() {
  local file_path="$1"
  local expected_sha256="$2"
  local normalized_sha256
  local actual_line
  local actual_sha256

  if [[ ! -f "$file_path" || -z "${expected_sha256// }" ]]; then
    printf 'false'
    return
  fi

  if ! normalized_sha256="$(normalize_sha256_value "$expected_sha256" 2>/dev/null)"; then
    printf 'false'
    return
  fi

  ensure_sha256sum
  actual_line="$(sha256sum "$file_path")"
  actual_sha256="${actual_line%% *}"
  if [[ "$actual_sha256" == "$normalized_sha256" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

bool_from_presence() {
  local value="$1"
  if [[ -n "${value// }" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

ensure_command curl
ensure_command systemctl
ensure_command install
ensure_command getent

if [[ -z "$HOST_AGENT_SHA256" && -n "$HOST_AGENT_SHA256_URL" ]]; then
  load_checksum_from_url HOST_AGENT_SHA256 "Host Agent" "$HOST_AGENT_SHA256_URL"
fi

if [[ -z "$RUNTIME_SHA256" && -n "$RUNTIME_SHA256_URL" ]]; then
  load_checksum_from_url RUNTIME_SHA256 "Dedicated Runtime" "$RUNTIME_SHA256_URL"
fi

create_service_account() {
  if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
    log "Creating group: $SERVICE_GROUP"
    groupadd --system "$SERVICE_GROUP"
  fi

  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    log "Creating user: $SERVICE_USER"
    useradd --system \
      --gid "$SERVICE_GROUP" \
      --home-dir "$DATA_DIR" \
      --shell /usr/sbin/nologin \
      "$SERVICE_USER"
  fi
}

download_binary() {
  local label="$1"
  local url="$2"
  local destination="$3"
  local expected_sha256="$4"
  local tmp_file
  tmp_file="$(mktemp)"

  log "Downloading $label: $url"
  if ! curl -fsSL "$url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    fail "Failed to download $label artifact."
  fi

  if ! verify_checksum "$label" "$tmp_file" "$expected_sha256"; then
    rm -f "$tmp_file"
    fail "$label checksum verification failed."
  fi

  install -m 0755 "$tmp_file" "$destination"
  rm -f "$tmp_file"
}

systemd_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  printf '"%s"' "$value"
}

write_env_file() {
  log "Writing EnvironmentFile: $ENV_FILE"
  mkdir -p "$CONFIG_DIR"
  umask 077
  {
    echo "# Generated by scripts/install-dedicated-server.sh"
    printf 'TORYGO_AGENT_DRY_RUN=%s\n' "$(systemd_quote "$AGENT_DRY_RUN")"
    printf 'TORYGO_ACTIVATION_KEY=%s\n' "$(systemd_quote "$ACTIVATION_KEY")"
    printf 'TORYGO_CENTRAL_CONTROL_URL=%s\n' "$(systemd_quote "$CENTRAL_CONTROL_URL")"
    printf 'TORYGO_GATEWAY_TUNNEL_URL=%s\n' "$(systemd_quote "$GATEWAY_TUNNEL_URL")"
    printf 'TORYGO_AGENT_STATE_DIR=%s\n' "$(systemd_quote "$STATE_DIR")"
    printf 'TORYGO_AGENT_HEARTBEAT_SECS=%s\n' "$(systemd_quote "$HEARTBEAT_SECS")"
    printf 'TORYGO_GATEWAY_CONNECT_TIMEOUT_SECS=%s\n' "$(systemd_quote "$GATEWAY_CONNECT_TIMEOUT_SECS")"
    printf 'TORYGO_GATEWAY_SEND_TIMEOUT_SECS=%s\n' "$(systemd_quote "$GATEWAY_SEND_TIMEOUT_SECS")"
    printf 'TORYGO_GATEWAY_RECONNECT_MIN_SECS=%s\n' "$(systemd_quote "$GATEWAY_RECONNECT_MIN_SECS")"
    printf 'TORYGO_GATEWAY_RECONNECT_MAX_SECS=%s\n' "$(systemd_quote "$GATEWAY_RECONNECT_MAX_SECS")"
    printf 'TORYGO_RUNTIME_BIN=%s\n' "$(systemd_quote "$RUNTIME_BIN")"
    printf 'TORYGO_RUNTIME_WORKDIR=%s\n' "$(systemd_quote "$RUNTIME_DIR")"
    printf 'TORYGO_RUNTIME_BIND_ADDR=%s\n' "$(systemd_quote "$RUNTIME_BIND_ADDR")"
    printf 'TORYGO_RUNTIME_HEALTH_URL=%s\n' "$(systemd_quote "$RUNTIME_HEALTH_URL")"
    printf 'TORYGO_RUNTIME_HEALTH_CHECK_TIMEOUT_MS=%s\n' "$(systemd_quote "$RUNTIME_HEALTH_CHECK_TIMEOUT_MS")"
    printf 'TORYGO_RUNTIME_WS_URL=%s\n' "$(systemd_quote "$RUNTIME_WS_URL")"
  } > "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
}

install_systemd_unit() {
  log "Installing systemd unit: $UNIT_PATH"
  mkdir -p "$SYSTEMD_UNIT_DIR"
  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=Torygo Host Agent (primary dedicated server service)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$HOST_AGENT_DIR
EnvironmentFile=-$ENV_FILE
ExecStart=$HOST_AGENT_BIN
SyslogIdentifier=torygo-host-agent
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
}

wait_for_service() {
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      return 0
    fi
    sleep 1
  done

  systemctl status "$SERVICE_NAME" --no-pager || true
  journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
  fail "$SERVICE_NAME did not become active."
}

wait_for_local_health() {
  local deadline=$((SECONDS + 45))
  while (( SECONDS < deadline )); do
    if curl -fsS "$RUNTIME_HEALTH_URL" >/dev/null 2>&1; then
      log "Dedicated Runtime health OK: $RUNTIME_HEALTH_URL"
      return 0
    fi
    sleep 1
  done

  journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
  fail "Dedicated Runtime local health check failed: $RUNTIME_HEALTH_URL"
}

clear_activation_key_after_activation() {
  if [[ "$AGENT_DRY_RUN" == "1" && ! -s "$IDENTITY_FILE" ]]; then
    return
  fi

  if [[ -z "${ACTIVATION_KEY// }" ]]; then
    return
  fi

  if [[ ! -s "$IDENTITY_FILE" ]]; then
    log "WARNING: Host Agent identity was not found at $IDENTITY_FILE; leaving activation key in $ENV_FILE for service retry."
    return
  fi

  log "Clearing activation key from EnvironmentFile after identity creation"
  ACTIVATION_KEY=""
  write_env_file

  log "Restarting $SERVICE_NAME so the process environment no longer contains the activation key"
  systemctl restart "$SERVICE_NAME"
  wait_for_service
}

write_release_provenance() {
  local release_channel="$RESOLVED_RELEASE_CHANNEL"
  local release_version="$RESOLVED_RELEASE_VERSION"
  local release_channel_present
  local release_version_present
  local release_channel_byte_length
  local release_version_byte_length
  local host_agent_byte_length
  local runtime_byte_length
  local host_agent_sha256_matched
  local runtime_sha256_matched
  local all_sha256_matched
  local activation_key_cleared
  local generated_at

  if [[ -z "${release_channel// }" ]]; then
    release_channel="$RELEASE_CHANNEL"
  fi
  if [[ -z "${release_version// }" ]]; then
    release_version="$RELEASE_VERSION"
  fi

  release_channel_present="$(bool_from_presence "$release_channel")"
  release_version_present="$(bool_from_presence "$release_version")"
  release_channel_byte_length="$(string_byte_length "$release_channel")"
  release_version_byte_length="$(string_byte_length "$release_version")"
  host_agent_byte_length="$(file_byte_length "$HOST_AGENT_BIN")"
  runtime_byte_length="$(file_byte_length "$RUNTIME_BIN")"
  host_agent_sha256_matched="$(sha256_matches_file "$HOST_AGENT_BIN" "$HOST_AGENT_SHA256")"
  runtime_sha256_matched="$(sha256_matches_file "$RUNTIME_BIN" "$RUNTIME_SHA256")"
  all_sha256_matched="false"
  if [[ "$host_agent_sha256_matched" == "true" && "$runtime_sha256_matched" == "true" ]]; then
    all_sha256_matched="true"
  fi
  activation_key_cleared="false"
  if [[ -z "${ACTIVATION_KEY// }" ]]; then
    activation_key_cleared="true"
  fi
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$STATE_DIR"
  umask 077
  cat > "$RELEASE_PROVENANCE_FILE" <<PROVENANCE
{
  "schemaVersion": 1,
  "status": "installed",
  "generatedAt": "$generated_at",
  "platform": "$ARCH_TOKEN",
  "release": {
    "channelPresent": $release_channel_present,
    "channelByteLength": $release_channel_byte_length,
    "versionPresent": $release_version_present,
    "versionByteLength": $release_version_byte_length
  },
  "artifacts": {
    "hostAgentByteLength": $host_agent_byte_length,
    "runtimeByteLength": $runtime_byte_length,
    "hostAgentSha256Matched": $host_agent_sha256_matched,
    "runtimeSha256Matched": $runtime_sha256_matched,
    "allSha256Matched": $all_sha256_matched
  },
  "activation": {
    "activationKeyCleared": $activation_key_cleared
  },
  "rawMaterialExposed": false
}
PROVENANCE
  chmod 0600 "$RELEASE_PROVENANCE_FILE"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$RELEASE_PROVENANCE_FILE"
  log "Wrote installed release provenance metadata."
}

log "Detected platform: $ARCH_TOKEN ($RUST_TARGET)"
create_service_account

mkdir -p "$HOST_AGENT_DIR" "$RUNTIME_DIR" "$STATE_DIR"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_ROOT" "$DATA_DIR" "$STATE_DIR"

download_binary "Host Agent" "$HOST_AGENT_URL" "$HOST_AGENT_BIN" "$HOST_AGENT_SHA256"
download_binary "Dedicated Runtime" "$RUNTIME_URL" "$RUNTIME_BIN" "$RUNTIME_SHA256"
chown "$SERVICE_USER:$SERVICE_GROUP" "$HOST_AGENT_BIN" "$RUNTIME_BIN"

write_env_file
install_systemd_unit

log "Enabling and starting $SERVICE_NAME"
systemctl enable --now "$SERVICE_NAME"
wait_for_service
wait_for_local_health
clear_activation_key_after_activation
wait_for_local_health
write_release_provenance

log "Agent status:"
systemctl --no-pager --full status "$SERVICE_NAME" || true
log "Install completed. No inbound port, domain, certificate, or reverse proxy setup was required."
