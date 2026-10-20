# ea-automation — Claude Code skill for Enterprise Architect

A [Claude Code](https://claude.com/claude-code) skill that reads **and writes** a running Sparx Enterprise Architect model through EA's COM Automation Interface — the same API EA add-ins use. No admin rights required.

**Why this exists:** the official Sparx Systems MCP server for EA is read-only (query tools only, no create/update). This skill is the write path: create elements and connectors, place or move them on diagrams, query the model — all driven by Claude through a small PowerShell CLI with JSON output.

## Classroom lab

A 60-minute hands-on lab based on this skill — download it, make it work, then improve it: [English](docs/lab.en.md) · [中文](docs/lab.zh.md)

## Install

Copy this folder to your Claude Code skills directory:

```
Windows: %USERPROFILE%\.claude\skills\ea-automation\
Linux/macOS: ~/.claude/skills/ea-automation/
```

Requirements: Windows, EA running with a project open (a diagram window open is best). Works under both pwsh 7 and Windows PowerShell 5.1.

## CLI commands (`scripts/ea.ps1`)

| Command | Arguments | What it does |
|---|---|---|
| `status` | — | Every running EA instance: project name, package tree with element IDs and diagram IDs |
| `diagram` | `-DiagramID N` | Elements (with positions) and connectors shown on that diagram |
| `find` | `-Name substr` | Substring search of element names across all packages |
| `element` | `-ElementID N` | One element: stereotype, notes, attributes, operations, its connectors |
| `add-element` | `-Name X -PackageID N [-Type Component]` | Create an element in a package (idempotent) |
| `place` | `-ElementID N -DiagramID N -X -Y -Width -Height` | Put the element on the diagram at a position; if already on it, moves it |
| `connect` | `-ClientID N -SupplierID N [-ConnectorType Dependency] [-DiagramID N]` | Create a connector; with `-DiagramID` it is also drawn on that diagram |
| `reload` | `-DiagramID N` | Refresh the diagram inside EA |

All commands print JSON on stdout; failures return `{"error": "..."}` with exit code 1.

## How it works

The CLI enumerates the Windows Running Object Table (ROT) to find running EA instances, picks the instance that owns the IDs you pass (so multiple EA windows are safe), and drives EA's COM Automation Interface (`Repository`, `Package.Elements`, `DiagramObjects`, `Connectors`, …). EA refreshes the open diagram automatically after write commands.

## Safety

- No delete commands — destructive operations stay manual in the EA UI.
- Write commands auto-select the EA instance that owns the given IDs; always run `status` first and use real IDs.
- The read-only Sparx MCP server is a good complement for verification, diagram PNG export, and driving the EA UI.

## License

MIT
