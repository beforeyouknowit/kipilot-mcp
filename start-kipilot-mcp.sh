#!/usr/bin/env bash
#
# Launch the KiPilot MCP server on macOS or Linux.
#
# This is the Unix counterpart of start-kipilot-mcp.ps1. It creates .venv
# when needed, installs the runtime package, applies conservative default
# environment variables, and starts the stdio MCP server.
#
# Usage:
#   ./start-kipilot-mcp.sh                  Bootstrap and start the server
#   ./start-kipilot-mcp.sh --skip-run       Bootstrap only (for MCP hosts)
#   ./start-kipilot-mcp.sh --force-install  Reinstall the runtime into .venv
#   ./start-kipilot-mcp.sh --check          Bootstrap and verify KiCad IPC
#   ./start-kipilot-mcp.sh --bionic         Print a ready-to-paste Bionic mcp.json entry
#   ./start-kipilot-mcp.sh --mcp-json       Print a generic mcpServers entry (Bionic, Claude Desktop, ...)
#   ./start-kipilot-mcp.sh --vscode-json    Print a VS Code mcp.json (servers) entry
#   ./start-kipilot-mcp.sh --python PATH    Use a specific Python interpreter
#
# Notes:
#   - Status and diagnostics go to stderr so stdout stays clean for MCP traffic.
#   - KiCad itself is a separate GUI application. Start KiCad 9+ and open the
#     target project in the PCB Editor before board-aware tools can connect.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv_path="$repo_root/.venv"
venv_python="$venv_path/bin/python"

force_install=0
skip_run=0
do_check=0
mcp_host=""
python_override=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-install) force_install=1; shift ;;
        --skip-run) skip_run=1; shift ;;
        --check) do_check=1; shift ;;
        --bionic) mcp_host="bionic"; shift ;;
        --mcp-json) mcp_host="generic"; shift ;;
        --vscode-json) mcp_host="vscode"; shift ;;
        --python) python_override="${2:?--python requires a path}"; shift 2 ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

write_status() {
    echo "$1" >&2
}

# Classify an interpreter's Mach-O architecture as "native", "foreign",
# or "unknown". Universal binaries count as native. Using `file` on the
# binary (rather than platform.machine()) is important: under Rosetta,
# platform.machine() can report the host architecture even when the running
# interpreter is x86_64, which silently breaks native wheel/build selection.
# On non-macOS systems there is no cross-arch interpreter scenario worth
# checking, so every interpreter classifies as "native".
python_arch_class() {
    local candidate="$1" host_arch="$2" file_out
    [[ "$(uname -s)" == "Darwin" ]] || { echo "native"; return 0; }
    file_out="$(file -b "$(command -v "$candidate")" 2>/dev/null)" || return 0
    case "$file_out" in
        *universal*) echo "native" ;;
        *"$host_arch"*) echo "native" ;;
        *x86_64*|*arm64*) echo "foreign" ;;
        *) echo "unknown" ;;
    esac
}

# Pick a Python 3.11+ interpreter. Order: explicit flag, KIPILOT_PYTHON env,
# then common macOS install locations. Native-architecture interpreters are
# preferred over cross-architecture ones (for example, an x86_64 python on an
# Apple Silicon machine) because pip wheels and native builds behave best when
# the interpreter matches the host architecture.
find_python() {
    local native_arch candidate arch_class
    native_arch="$(uname -m)"

    # An explicit interpreter choice wins (arch warning applies on macOS).
    for candidate in "$python_override" "${KIPILOT_PYTHON:-}"; do
        [[ -z "$candidate" ]] && continue
        if command -v "$candidate" >/dev/null 2>&1 \
            && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
            arch_class="$(python_arch_class "$candidate" "$native_arch")"
            if [[ "$arch_class" != "native" ]]; then
                write_status "Note: requested interpreter '$candidate' is not native for host arch $native_arch; continuing anyway."
            fi
            echo "$candidate"
            return 0
        fi
        write_status "Note: requested interpreter '$candidate' was not found or is below Python 3.11."
    done

    # Pass 1: native-arch or universal interpreters, newest first
    # (on Linux this is simply "newest Python 3.11+ on PATH").
    for candidate in python3.13 python3.12 python3.11 python3; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null || continue
        if [[ "$(python_arch_class "$candidate" "$native_arch")" == "native" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Pass 2: fall back to any 3.11+ interpreter, with a warning.
    for candidate in python3.13 python3.12 python3.11 python3; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
            write_status "Note: using '$candidate' ($(command -v "$candidate")) which does not match the host arch ($native_arch)."
            write_status "      If native builds fail, install a native Python 3.11+ for your platform."
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

create_venv() {
    local py
    if py="$(find_python)"; then
        write_status "Creating .venv with $(command -v "$py") ($("$py" --version 2>&1))..."
    else
        py="python3"
        write_status "No Python 3.11+ found on PATH; falling back to 'python3'."
    fi

    if ! "$py" -m venv "$venv_path"; then
        write_status "Error: failed to create $venv_path."
        write_status "Install Python 3.11+ and rerun (macOS: brew install python@3.12;"
        write_status "Debian/Ubuntu: sudo apt install python3.12 python3.12-venv; Fedora: sudo dnf install python3.12)."
        exit 1
    fi
}

runtime_installed() {
    [[ -x "$venv_python" ]] || return 1
    "$venv_python" -c "import kipy, mcp, kipilot_mcp" >/dev/null 2>&1
}

install_runtime() {
    write_status "Installing KiPilot MCP runtime dependencies into .venv..."
    "$venv_python" -m pip install --upgrade pip >/dev/null
    "$venv_python" -m pip install -e .
}

# Apply conservative defaults without overriding explicit user settings.
set_default_env() {
    local name value
    for pair in \
        "KIPILOT_KICAD_CLIENT_NAME=kipilot-mcp" \
        "KIPILOT_KICAD_TIMEOUT_MS=60000" \
        "KIPILOT_ENABLE_MUTATIONS=0" \
        "KIPILOT_COMMIT_MESSAGE_PREFIX=KiPilot MCP" \
        "KIPILOT_LOG_LEVEL=INFO" \
        "KIPILOT_LOG_FILE=$repo_root/.logs/kipilot-mcp.log"; do
        name="${pair%%=*}"
        value="${pair#*=}"
        if [[ -z "${!name:-}" ]]; then
            export "$name=$value"
        fi
    done

    local log_dir
    log_dir="$(dirname "$KIPILOT_LOG_FILE")"
    [[ -n "$log_dir" && "$log_dir" != "." ]] && mkdir -p "$log_dir"
}

# The KiCad IPC socket is created by KiCad in the temp directory when it
# launches (default: /tmp/kicad/api.sock on macOS and Linux; Flatpak builds
# use ~/.var/app/org.kicad.KiCad/cache/tmp/kicad/api.sock). With multiple
# KiCad instances running, KiCad appends the PID to the socket name.
report_kicad_socket() {
    local socket_root="/tmp/kicad"
    local flatpak_socket="${HOME}/.var/app/org.kicad.KiCad/cache/tmp/kicad/api.sock"
    if [[ -n "${KICAD_API_SOCKET:-}" ]]; then
        write_status "KiCad IPC endpoint (from KICAD_API_SOCKET): $KICAD_API_SOCKET"
        return 0
    fi
    if [[ -e "$flatpak_socket" ]]; then
        write_status "KiCad (Flatpak) IPC socket found: $flatpak_socket"
        return 0
    fi
    local sockets count
    sockets="$(ls "$socket_root"/api.sock* 2>/dev/null | tr '\n' ' ')"
    if [[ -n "$sockets" ]]; then
        write_status "KiCad IPC socket found: ${sockets% }"
        count="$(ls "$socket_root"/api.sock* 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$count" -gt 1 ]]; then
            write_status "Note: $count KiCad instances are running (socket names are PID-suffixed)."
            write_status "Set KICAD_API_SOCKET to reach a specific instance."
        fi
    else
        write_status "Warning: no KiCad IPC socket found under $socket_root."
        write_status "Start KiCad, open the target project in the PCB Editor, and retry."
        write_status "(If several KiCad instances are running, the socket name gets a PID suffix.)"
        return 1
    fi
    return 0
}

check_kicad_connection() {
    write_status "Probing the KiCad IPC API through the installed kipy binding..."
    if ! "$venv_python" - <<'PYEOF'
import asyncio
import json

from kipilot_mcp.config import KiCadIpcConfig
from kipilot_mcp.ipc_client import KiCadIpcClient


async def main() -> None:
    client = KiCadIpcClient(KiCadIpcConfig.from_env())
    result = await client.check_connection()
    print(json.dumps(result, indent=2, default=str))


asyncio.run(main())
PYEOF
    then
        write_status "KiCad IPC connection check FAILED (see JSON above)."
        exit 1
    fi
}

print_mcp_config() {
    # Emits a ready-to-paste entry for an MCP host. Hosts launch this venv
    # python directly, so no wrapper script is needed.
    local host="$1"
    case "$host" in
        vscode)
            # VS Code uses "servers" (not "mcpServers") and an explicit type.
            cat <<EOF
{
  "servers": {
    "kipilot-mcp": {
      "type": "stdio",
      "command": "$venv_python",
      "args": ["-m", "kipilot_mcp.server"],
      "env": {
        "KIPILOT_KICAD_CLIENT_NAME": "${KIPILOT_KICAD_CLIENT_NAME:-kipilot-mcp}",
        "KIPILOT_KICAD_TIMEOUT_MS": "${KIPILOT_KICAD_TIMEOUT_MS:-60000}",
        "KIPILOT_ENABLE_MUTATIONS": "${KIPILOT_ENABLE_MUTATIONS:-0}",
        "KIPILOT_COMMIT_MESSAGE_PREFIX": "${KIPILOT_COMMIT_MESSAGE_PREFIX:-KiPilot MCP}",
        "KIPILOT_LOG_LEVEL": "${KIPILOT_LOG_LEVEL:-INFO}",
        "KIPILOT_LOG_FILE": "${KIPILOT_LOG_FILE:-$repo_root/.logs/kipilot-mcp.log}"
      }
    }
  }
}
EOF
            ;;
        *)
            # "mcpServers" style: Bionic, Claude Desktop, and most other hosts.
            # Bionic additionally honors "cwd" and "timeout".
            cat <<EOF
{
  "mcpServers": {
    "kipilot-mcp": {
      "command": "$venv_python",
      "args": ["-m", "kipilot_mcp.server"],
      "cwd": "$repo_root",
      "env": {
        "KIPILOT_KICAD_CLIENT_NAME": "${KIPILOT_KICAD_CLIENT_NAME:-kipilot-mcp}",
        "KIPILOT_KICAD_TIMEOUT_MS": "${KIPILOT_KICAD_TIMEOUT_MS:-60000}",
        "KIPILOT_ENABLE_MUTATIONS": "${KIPILOT_ENABLE_MUTATIONS:-0}",
        "KIPILOT_COMMIT_MESSAGE_PREFIX": "${KIPILOT_COMMIT_MESSAGE_PREFIX:-KiPilot MCP}",
        "KIPILOT_LOG_LEVEL": "${KIPILOT_LOG_LEVEL:-INFO}",
        "KIPILOT_LOG_FILE": "${KIPILOT_LOG_FILE:-$repo_root/.logs/kipilot-mcp.log}"
      },
      "timeout": 60000
    }
  }
}
EOF
            ;;
    esac
}

pushd "$repo_root" >/dev/null

if [[ ! -x "$venv_python" ]]; then
    create_venv
fi

if [[ "$force_install" -eq 1 ]] || ! runtime_installed; then
    install_runtime
fi

set_default_env

if [[ -n "$mcp_host" ]]; then
    write_status "MCP host entry for this checkout (host='$mcp_host'; JSON on stdout):"
    print_mcp_config "$mcp_host"
    popd >/dev/null
    exit 0
fi

if [[ "$do_check" -eq 1 ]]; then
    report_kicad_socket || true
    check_kicad_connection
    write_status "KiCad IPC connection check complete."
    popd >/dev/null
    exit 0
fi

if [[ "$skip_run" -eq 1 ]]; then
    write_status "KiPilot MCP environment is ready. Launch skipped because --skip-run was specified."
    report_kicad_socket || true
    popd >/dev/null
    exit 0
fi

write_status "Starting KiPilot MCP server..."
write_status "Tip: make sure KiCad is running with the target project open (PCB Editor)."
report_kicad_socket || true
exec "$venv_python" -m kipilot_mcp.server
