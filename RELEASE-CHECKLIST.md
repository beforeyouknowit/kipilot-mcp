# KiPilot ZIP Release Checklist

Use this checklist when publishing self-contained Windows or macOS ZIP releases. This fork does not run CI: ZIPs are built locally on a machine matching the target OS/architecture and uploaded to GitHub Releases by hand. (Source installs remain the primary supported path — see the README.)

## Before Packaging

- Confirm the intended version in `src/kipilot_mcp/__init__.py` and `pyproject.toml`.
- Review README and public site install text for consistency.
- Run tests and lint for the touched slice.

## Windows ZIP

- Run `.\build-windows-zip.ps1 -ForceInstall -Clean` from the repository root on a Windows x64 machine.
- Confirm the generated archive path under `artifacts/kipilot-mcp-<version>-windows-x64.zip`.
- Verify the ZIP includes `kipilot-mcp.exe`, `README.md`, and `LICENSE`.
- Smoke-test the extracted executable through an MCP host configuration, not by double-clicking it.

## macOS ZIP

- Run `./build-macos-zip.sh --force-install --clean` on the target Mac (Apple Silicon for `arm64`, Intel for `x64`). The archive name reflects the build machine's architecture.
- Confirm the generated archive path under `artifacts/kipilot-mcp-<version>-macos-<arch>.zip`.
- Verify the ZIP includes the server bundle plus `README.md` and `LICENSE`.
- Smoke-test the extracted binary through an MCP host configuration.

## Release Publication

- Merge the release changes into `main` and push.
- Create or update the GitHub release/tag for the target version.
- Upload the ZIP artifact(s) manually, e.g.:

```bash
gh release upload <version> artifacts/kipilot-mcp-<version>-<platform>.zip \
  --repo beforeyouknowit/kipilot-mcp
```

- Confirm the release page contains the uploaded ZIP artifact(s).

## Post-Release Verification

- Download the published ZIP from GitHub Releases.
- Extract it on a clean machine of the matching architecture.
- Start KiCad, point an MCP host at the server, and run `ping_kicad`.
- Verify logs still go to `stderr` or the configured log file, never to `stdout`.
