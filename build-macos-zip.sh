#!/usr/bin/env bash
#
# Build the KiPilot MCP macOS ZIP release artifact.
#
# macOS counterpart of build-windows-zip.ps1. It bootstraps the runtime venv
# (via start-kipilot-mcp.sh), freezes the stdio server with PyInstaller in
# --onedir --console mode, and stages a versioned ZIP that includes the
# executable, README.md, and LICENSE.
#
# Usage:
#   ./build-macos-zip.sh                  Build using the existing .venv
#   ./build-macos-zip.sh --force-install  Reinstall the runtime into .venv first
#   ./build-macos-zip.sh --clean          Remove build/, dist/, artifacts/ first
#
# Artifact (arch is arm64 on Apple Silicon, x64 on Intel):
#   artifacts/kipilot-mcp-<version>-macos-arm64.zip
#   artifacts/kipilot-mcp-<version>-macos-x64.zip
#
# Notes:
#   - Status and diagnostics go to stderr.
#   - The executable in the ZIP is a plain console binary. Let your MCP host
#     start it so stdio stays attached to the host; do not double-click it.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bootstrap_script="$repo_root/start-kipilot-mcp.sh"
venv_python="$repo_root/.venv/bin/python"
build_root="$repo_root/build"
dist_root="$repo_root/dist"
artifacts_root="$repo_root/artifacts"
pyinstaller_spec_root="$build_root/pyinstaller"

force_install=0
clean=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-install) force_install=1; shift ;;
        --clean) clean=1; shift ;;
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

if [[ "$(uname -s)" != "Darwin" ]]; then
    write_status "Error: this build helper only supports macOS."
    exit 1
fi

if [[ ! -x "$bootstrap_script" ]]; then
    write_status "Error: the bootstrap script start-kipilot-mcp.sh was not found or is not executable."
    exit 1
fi

pushd "$repo_root" >/dev/null

# 1. Bootstrap the runtime venv (creates .venv and installs the package).
bootstrap_args=(--skip-run)
if [[ "$force_install" -eq 1 ]]; then
    bootstrap_args+=(--force-install)
fi
"$bootstrap_script" "${bootstrap_args[@]}"

if [[ ! -x "$venv_python" ]]; then
    write_status "Error: expected Python executable was not found at $venv_python."
    exit 1
fi

# 2. Install PyInstaller into the venv.
write_status "Installing PyInstaller into .venv..."
"$venv_python" -m pip install "pyinstaller>=6.14.0" >/dev/null

# 3. Optional clean.
if [[ "$clean" -eq 1 ]]; then
    rm -rf "$build_root" "$dist_root" "$artifacts_root"
fi

# 4. Resolve the package version.
package_version="$("$venv_python" -c 'from kipilot_mcp import __version__; print(__version__)')"
if [[ -z "$package_version" ]]; then
    write_status "Error: unable to resolve the KiPilot package version."
    exit 1
fi

# Derive the artifact architecture from the venv interpreter, which is the
# interpreter PyInstaller actually bundles. Do NOT use uname -m: on Apple
# Silicon this script may be launched from a Rosetta (x86_64) shell, which
# would mislabel a native arm64 artifact.
venv_arch="$("$venv_python" -c 'import platform; print(platform.machine())')"
case "$venv_arch" in
    arm64) artifact_arch="arm64" ;;
    x86_64) artifact_arch="x64" ;;
    *)
        write_status "Error: unsupported venv architecture '$venv_arch'."
        exit 1
        ;;
esac

release_name="kipilot-mcp-$package_version-macos-$artifact_arch"
dist_package_root="$dist_root/kipilot-mcp"
staging_root="$artifacts_root/$release_name"
zip_path="$artifacts_root/$release_name.zip"

mkdir -p "$artifacts_root" "$pyinstaller_spec_root"
rm -rf "$staging_root"
rm -f "$zip_path"

# 5. Build the stdio server executable with PyInstaller.
write_status "Building KiPilot MCP macOS executable with PyInstaller..."
"$venv_python" -m PyInstaller \
    --noconfirm \
    --clean \
    --onedir \
    --console \
    --name kipilot-mcp \
    --specpath "$pyinstaller_spec_root" \
    --paths src \
    --collect-all kipy \
    --copy-metadata kipilot-mcp \
    --copy-metadata kicad-python \
    --copy-metadata mcp \
    pyinstaller_entry.py

if [[ ! -x "$dist_package_root/kipilot-mcp" ]]; then
    write_status "Error: expected executable was not created at $dist_package_root/kipilot-mcp."
    exit 1
fi

# 6. Stage the artifact and create the ZIP.
mkdir -p "$staging_root"
cp -R "$dist_package_root/." "$staging_root/"
cp "$repo_root/README.md" "$staging_root/"
cp "$repo_root/LICENSE" "$staging_root/"

(cd "$artifacts_root" && zip -qr "$release_name.zip" "$release_name")

# 7. Verify the required files made it into the ZIP (top-level leaf names,
# mirroring Test-ZipContainsRequiredFiles in build-windows-zip.ps1).
# Done with the venv python rather than 'unzip -l | grep -q' because grep -q
# can exit early, SIGPIPE unzip, and trip 'set -o pipefail' on false failures.
if ! "$venv_python" - "$zip_path" <<'PYEOF'
import sys
import zipfile

zip_path = sys.argv[1]
required = {"kipilot-mcp", "README.md", "LICENSE"}

with zipfile.ZipFile(zip_path) as archive:
    leaf_names = {name.rsplit("/", 1)[-1] for name in archive.namelist() if name}

missing = sorted(required - leaf_names)
if missing:
    print(f"Missing from ZIP artifact {zip_path}: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)
PYEOF
then
    write_status "Error: required files are missing from the ZIP artifact."
    rm -f "$zip_path"
    exit 1
fi

write_status "macOS ZIP artifact ready: $zip_path"
popd >/dev/null
