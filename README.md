<p align="center">
	<img src="KiPilot.svg" alt="KiPilot MCP">
</p>

# KiPilot MCP

KiPilot is a Python-based Model Context Protocol (MCP) server that connects MCP-aware clients, such as GitHub Copilot in VS Code, to a user-controlled KiCad 10.x GUI session through the official `kicad-python` IPC binding.

The server runs over `stdio`, exposes PCB-first MCP tools plus a build-gated schematic subset, and is designed for live KiCad workflows where the user keeps full control of the GUI session.

## Usage Videos

Usage videos are available at [kipilot.org/galery.html](https://kipilot.org/galery.html).

## Documentation

Public project documentation is available at [kipilot.org/docs.html](https://kipilot.org/docs.html).

## Overview

KiPilot exists to let an MCP client inspect and manipulate KiCad documents that are already open in the user-controlled GUI session, with PCB workflows as the primary baseline.

- Uses the official KiCad IPC path through `kicad-python`
- Runs as a `stdio` MCP server for VS Code and similar hosts
- Supports read-heavy PCB workflows plus guarded mutation tools
- Adds a source-build-gated schematic surface for hierarchy, hit-testing, metadata mutation, and export workflows where the running KiCad build exposes the newer schematic IPC handlers
- Adds selected higher-level MCP helpers on top of raw IPC primitives, such as a real footprint side-flip workflow that mirrors child artwork and swaps paired layers
- Keeps KiCad as a separate, user-launched GUI application

This repository targets the KiCad 10 PCB-first baseline. It does not aim to be a 1:1 wrapper over every public method exposed by the KiCad Python binding.

Where the raw IPC surface does not expose a single native operation but the underlying board objects are still mutable, KiPilot may provide a higher-level MCP tool that composes those lower-level capabilities into one agent-friendly action. The current example is `kicad_flip_footprint`, which performs a real mirrored side flip even though the KiCad binding does not expose one direct footprint-flip call.

## Current Scope

Implemented MCP surface includes:

- MCP stdio server entry point
- Async-friendly KiCad IPC client wrapper around `kipy.KiCad`
- Connectivity and version checks such as `ping_kicad` and `get_kicad_version`
- Board and document inspection tools for open documents, outlines, stackup, footprints, nets, pads, tracks, vias, zones, graphics, dimensions, groups, reference images, barcodes, text, text geometry, project text variables, project net classes, origins, title blocks, selection state, and connectivity
- Filtered lookup tools for footprints, footprint-scoped pads, nets, net classes, and connected items
- Guarded mutation tools for visible layers, active layer, enabled layers, footprint move/rotate/flip, footprint pad net reassignment, origins, title block fields, board text, track creation, via creation, item updates, track geometry, zone outlines, item deletion, zone refill, board revert, and board save
- Schematic hierarchy, netlist, hit-testing, page-settings, title-block, metadata-mutation, and export tools when the active KiCad runtime exposes schematic IPC support
- Unit tests for IPC connection and error-handling behavior

Committed baseline:

- GUI IPC only
- PCB editor first
- Initial schematic inspection, hit-testing, metadata mutation, and export workflows are supported only when the running KiCad build exposes the newer schematic IPC surface
- Read-heavy workflows first, validated mutation workflows second
- No committed headless automation scope

## Schematic MCP Surface

The schematic surface is intentionally smaller and more runtime-dependent than the PCB surface.

Available schematic tools:

- Inspection: `kicad_sch_get_hierarchy`, `kicad_sch_get_netlist`, `kicad_sch_get_page_settings`, and `kicad_sch_get_title_block`
- Inspection geometry: `kicad_sch_hit_test`
- Guarded metadata mutation: `kicad_sch_set_page_settings` and `kicad_sch_set_title_block`
- Plot export: `kicad_sch_export_svg`, `kicad_sch_export_dxf`, `kicad_sch_export_pdf`, and `kicad_sch_export_ps`
- File export: `kicad_sch_export_netlist` and `kicad_sch_export_bom`

Important export semantics:

- `kicad_sch_export_svg`, `kicad_sch_export_dxf`, and `kicad_sch_export_ps` take `output_dir` because KiCad writes one file per plotted sheet into a directory.
- `kicad_sch_export_pdf` takes `output_file` because KiCad writes one PDF file to a file path.
- `kicad_sch_export_netlist` and `kicad_sch_export_bom` also take `output_file` because they produce single file outputs.
- When you want a full schematic export, `plot_all=true` with omitted `plot_pages` is the safest default unless you already know the exact sheet-instance paths to filter.
- In this environment, live end-to-end schematic MCP validation succeeded against a locally built `kicad-master` `eeschema` snapshot. The installed official KiCad 10.0.1 build did not expose the same reliable external schematic IPC behavior, so treat the schematic surface as source-build-gated rather than universally available across all KiCad 10 installations.

## Requirements

- KiCad 10.x installed locally
- A running KiCad GUI instance with IPC API support
- Python 3.11+ for source installs and local ZIP builds
- Git for source installs

No compiler or Rust toolchain is required on mainstream platforms: all dependencies ship binary wheels for Windows x64, macOS (arm64 and x86_64), and Linux (x86_64 and aarch64).

Use a stable CPython release such as 3.11, 3.12, or 3.13. Avoid preview or alpha Python interpreters because the native dependency chain may not publish wheels for them yet.

The Windows ZIP release bundles its own Python runtime for the server process, so local Python is not required when you install from the downloadable Windows artifact.

## Quick Start

The supported installation path is a **source install**, and it works the same on macOS, Linux, and Windows. It takes three steps: clone, install into a virtual environment with the included helper script, and point your MCP host at the venv's Python.

### Step 1 — Clone the repository

```bash
git clone https://github.com/beforeyouknowit/kipilot-mcp.git
cd kipilot-mcp
```

### Step 2 — Create the environment and install

One helper script per platform family creates `.venv` when needed, installs the runtime package, and applies conservative default environment variables:

macOS and Linux (Bash):

```bash
./start-kipilot-mcp.sh --skip-run
```

On macOS the script prefers a Python 3.11+ interpreter that matches your machine's architecture (native arm64 on Apple Silicon, native x86_64 on Intel). On Linux it simply picks the newest Python 3.11+ on your `PATH`.

Windows (PowerShell):

```powershell
.\start-kipilot-mcp.ps1 -SkipRun
```

Verify that the environment can reach a running KiCad instance (macOS/Linux):

```bash
./start-kipilot-mcp.sh --check
```

Run the helper without `--skip-run` (or without `-SkipRun` on Windows) to start the server process directly from a terminal for manual checks. For MCP hosts, prefer configuring the host to launch `python -m kipilot_mcp.server` directly from the prepared environment (next step). That keeps the stdio server command explicit and easy to audit.

### Step 3 — Point your MCP host at the server

The server is a stdio process. Your MCP host should start it with the venv's Python so the host owns process startup:

| Platform | Command | Args |
| --- | --- | --- |
| macOS / Linux | `<checkout>/.venv/bin/python` | `-m kipilot_mcp.server` |
| Windows | `<checkout>\.venv\Scripts\python.exe` | `-m kipilot_mcp.server` |

Add the `KIPILOT_*` environment variables from the [Configuration](#configuration) section to the host entry.

Prefer not to type the entry by hand? The Unix helper prints a ready-to-paste JSON entry for this checkout: `./start-kipilot-mcp.sh --mcp-json` (Bionic, Claude Desktop, and most `mcpServers`-style hosts) or `./start-kipilot-mcp.sh --vscode-json` (VS Code). `--bionic` is a shortcut for `--mcp-json`.

#### LM Studio Bionic (macOS)

LM Studio Bionic loads MCP servers from its local `mcp.json`. On macOS that file lives at `~/.lmstudio/apps/bionic/mcp.json` (Bionic can also reveal the file from its MCP settings). Any local or remote model loaded into Bionic can then call KiPilot's tools against the running KiCad GUI.

Print a ready-to-paste entry for this checkout:

```bash
./start-kipilot-mcp.sh --bionic
```

Or start from `bionic/mcp.example.json` and replace the placeholder paths with your checkout location:

```json
{
  "mcpServers": {
    "kipilot-mcp": {
      "command": "/ABSOLUTE/PATH/TO/kipilot-mcp/.venv/bin/python",
      "args": ["-m", "kipilot_mcp.server"],
      "cwd": "/ABSOLUTE/PATH/TO/kipilot-mcp",
      "env": {
        "KIPILOT_KICAD_CLIENT_NAME": "kipilot-mcp",
        "KIPILOT_KICAD_TIMEOUT_MS": "60000",
        "KIPILOT_ENABLE_MUTATIONS": "0",
        "KIPILOT_COMMIT_MESSAGE_PREFIX": "KiPilot MCP",
        "KIPILOT_LOG_LEVEL": "INFO",
        "KIPILOT_LOG_FILE": "/ABSOLUTE/PATH/TO/kipilot-mcp/.logs/kipilot-mcp.log"
      },
      "timeout": 60000
    }
  }
}
```

Bionic starts the server process itself, so keep `command` pointed at the venv Python rather than a wrapper script.

#### VS Code and other hosts (source install)

Example VS Code MCP configuration using the venv created above:

```json
{
	"servers": {
		"kipilot-mcp": {
			"type": "stdio",
			"command": "${workspaceFolder}\\.venv\\Scripts\\python.exe",
			"args": ["-m", "kipilot_mcp.server"],
			"env": {
				"KIPILOT_KICAD_CLIENT_NAME": "kipilot-mcp",
				"KIPILOT_KICAD_TIMEOUT_MS": "60000",
				"KIPILOT_LOG_LEVEL": "INFO",
				"KIPILOT_LOG_FILE": ".logs/kipilot-mcp.log"
			}
		}
	}
}
```

(On macOS/Linux use `<checkout>/.venv/bin/python` as the command instead.)

### Manual install (without the helper script)

A virtual environment is recommended for dependency isolation, but it is not a KiPilot-specific requirement. If you already manage Python environments another way, point your MCP host at that interpreter instead.

macOS / Linux:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install .
```

Windows (PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install .
```

For development and tests, install in editable mode with development dependencies:

```bash
python -m pip install -e ".[dev]"
```

Start KiCad yourself, open the target hardware project, and open the PCB Editor before using board-aware MCP tools.

### Windows ZIP release (no local Python required)

If you do not want to manage Python at all on Windows, the upstream project publishes a ready-to-run ZIP that bundles its own Python runtime. Download the latest Windows release ZIP from GitHub Releases, extract it, and point your MCP host at `kipilot-mcp.exe`.

- Latest release: https://github.com/belaszalontai/kipilot-mcp/releases/latest
- Artifact name pattern: `kipilot-mcp-<version>-windows-x64.zip`
- The ZIP contains the stdio server executable plus its bundled runtime

Do not double-click the executable for normal use. Let your MCP host start it so stdio stays attached to the host.

### Linux

The venv install above is the supported path on Linux — this fork does not publish prebuilt Linux binaries, and nothing needs to be compiled: `./start-kipilot-mcp.sh --skip-run` is the whole setup (it works unchanged on macOS and Linux).

- **KiCad 10 on Ubuntu/Debian:** use KiCad's official per-release PPA (listed in the Linux section of the [kicad.org downloads page](https://www.kicad.org/downloads/)), the KiCad Flatpak from Flathub, or your distribution's package if it ships KiCad 10. Other distros: any KiCad 10.x that exposes the IPC API works the same way.
- **IPC socket:** KiCad creates it in the user's temp directory at launch — `/tmp/kicad/api.sock` for native installs and `~/.var/app/org.kicad.KiCad/cache/tmp/kicad/api.sock` for Flatpak. `kicad-python` resolves both defaults automatically. With several KiCad instances running, the socket name gets a PID suffix (`api.sock.12345`); the launcher warns about this, and `KICAD_API_SOCKET` targets a specific instance (see [Configuration](#configuration)).
- **MCP host config:** the JSON helpers above (`--mcp-json`, `--vscode-json`) work on Linux exactly as on macOS.

## Configuration

The IPC connection uses KiCad's official API endpoint. On macOS and Linux it is a Unix domain socket; on Windows it lives under the user temp directory. When KiCad launches an API plugin it provides these environment variables:

```powershell
$env:KICAD_API_SOCKET = "..."
$env:KICAD_API_TOKEN = "..."
```

When the server is launched from an MCP host rather than from KiCad, those variables may not be present. In that case `kicad-python` falls back to the default platform-dependent IPC endpoint, which is easiest to work with when only one KiCad instance is open:

- macOS and Linux: `ipc:///tmp/kicad/api.sock` (KiCad creates the socket in its temp directory at launch)
- Linux Flatpak KiCad: `ipc://$HOME/.var/app/org.kicad.KiCad/cache/tmp/kicad/api.sock`
- Windows: `ipc://%TEMP%\kicad\api.sock`

With several KiCad instances running, KiCad appends the PID to the socket name, so set `KICAD_API_SOCKET` explicitly to reach a specific instance.

KiPilot-specific settings:

```powershell
$env:KIPILOT_KICAD_CLIENT_NAME = "kipilot-mcp"
$env:KIPILOT_KICAD_TIMEOUT_MS = "60000"
$env:KIPILOT_ENABLE_MUTATIONS = "0"
$env:KIPILOT_COMMIT_MESSAGE_PREFIX = "KiPilot MCP"
$env:KIPILOT_LOG_LEVEL = "INFO"
$env:KIPILOT_LOG_FILE = ".logs/kipilot-mcp.log"
```

Operational notes:

- `KIPILOT_ENABLE_MUTATIONS=0` keeps live board writes disabled by default
- `dry_run=true` previews remain available even when writes are disabled
- destructive tools such as revert and delete still require `force=true`
- logs go to `stderr` by default so `stdout` stays clean for MCP traffic

## Running The Server

After a source installation, run the server in a terminal for manual checks:

```bash
python -m kipilot_mcp.server
```

(or the `kipilot-mcp` console script installed into the venv.)

For normal use, let your MCP host start the server — see [Step 3](#step-3--point-your-mcp-host-at-the-server) for ready-to-paste host configurations. If your KiCad setup requires an explicit API socket or token, add `KICAD_API_SOCKET` and `KICAD_API_TOKEN` to the same `env` block.

## Development

Install development dependencies:

```powershell
python -m pip install -e ".[dev]"
```

Run tests:

```powershell
python -m pytest
```

Run linting:

```powershell
python -m ruff check .
```

Optionally, package a self-contained ZIP locally (bundles a Python runtime via PyInstaller; no CI is involved). Build on the OS/architecture you want to ship:

Windows (PowerShell):

```powershell
.\build-windows-zip.ps1 -ForceInstall -Clean
```

Creates `artifacts/kipilot-mcp-<version>-windows-x64.zip`.

macOS (Bash; the script refuses to run on other operating systems):

```bash
./build-macos-zip.sh --force-install --clean
```

Creates `artifacts/kipilot-mcp-<version>-macos-<arch>.zip` (where `arch` is `arm64` or `x64`, taken from the build machine). Both archives include `README.md` and `LICENSE`. Linux has no packaging script on purpose — the venv install is the supported path there. To share a build, upload the ZIP to a GitHub release manually — see `RELEASE-CHECKLIST.md`.

## Repository Layout

```text
.
|-- agent-test/
|   |-- .github/
|   |-- .logs/
|   |-- .vscode/
|   `-- README.md
|-- bionic/
|   `-- mcp.example.json
|-- src/
|   `-- kipilot_mcp/
|       |-- __init__.py
|       |-- config.py
|       |-- errors.py
|       |-- ipc_client.py
|       |-- ipc_client_core.py
|       |-- ipc_client_pcb.py
|       |-- ipc_client_sch.py
|       |-- lookups.py
|       |-- serializers.py
|       `-- server.py
|-- tests/
|   `-- test_ipc_client.py
|-- KiPilot.svg
|-- build-macos-zip.sh
|-- build-windows-zip.ps1
|-- pyproject.toml
|-- pyinstaller_entry.py
|-- README.md
|-- start-kipilot-mcp.ps1
`-- start-kipilot-mcp.sh
```

## The `agent-test/` Folder

The `agent-test/` directory is a small standalone VS Code test workspace for validating the MCP server from the perspective of a real Copilot agent setup.

Its purpose is to provide:

- a clean workspace separate from the main source tree
- a ready-made `.vscode/mcp.json` configuration that points to the sibling KiPilot server
- custom Copilot agent and instruction files for KiCad-focused testing
- a controlled workspace for end-to-end MCP validation

Open `agent-test/` in a separate VS Code window when you want to test the full agent workflow end to end without mixing that setup into the main development workspace.

## References

- [kicad-python documentation](https://docs.kicad.org/kicad-python-main/)
- [KiCad IPC API for add-on developers](https://dev-docs.kicad.org/en/apis-and-binding/ipc-api/for-addon-developers/index.html)

## Capability Mapping

The current capability map for the server target is documented in `.github/kicad-api-capabilities.md`. Use that file as the source of truth for deciding which MCP tools belong in the KiCad 10 baseline, which ones need stronger validation, and which ones are version-gated for future KiCad releases.