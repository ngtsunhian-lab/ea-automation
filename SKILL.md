---
name: ea-automation
description: Read and write a running Enterprise Architect (Sparx EA) model through its COM Automation Interface — query packages, diagrams and elements; create elements and connectors; place or move them on diagrams. Use when the user wants to programmatically edit an EA model or architecture diagrams (e.g. "add a component to the EA diagram", "connect these elements in EA", "move this box in the EA model", "edit the architecture diagram in Enterprise Architect"). The official Sparx MCP server is read-only; this skill is the write path.
---

# EA Automation (COM) CLI

`scripts/ea.ps1` drives a **running** EA instance through its COM Automation Interface (the same API EA add-ins use). Full read/write, no admin rights needed.

## Requirements

- Windows, EA running with the project open (a diagram window open is best).
- Works under both pwsh 7 and Windows PowerShell 5.1:

```
& "<skill dir>\scripts\ea.ps1" -Command <cmd> [args]
```

All commands print JSON on stdout. On failure: `{"error": "..."}` and exit code 1.

## Commands

| Command | Arguments | What it does |
|---|---|---|
| `status` | — | Every running EA instance: project name, package tree with element IDs and diagram IDs |
| `diagram` | `-DiagramID N` | Elements (with positions) and connectors shown on that diagram |
| `find` | `-Name substr` | Substring search of element names across all packages |
| `element` | `-ElementID N` | One element: stereotype, notes, attributes, operations, its connectors |
| `add-element` | `-Name X -PackageID N [-Type Component]` | Create an element in a package (idempotent: if the name exists, returns the existing ID) |
| `place` | `-ElementID N -DiagramID N -X -Y -Width -Height` | Put the element on the diagram at a position; if already on it, **moves** it |
| `connect` | `-ClientID N -SupplierID N [-ConnectorType Dependency] [-DiagramID N]` | Create a connector between two elements; with `-DiagramID` it is also drawn on that diagram |
| `reload` | `-DiagramID N` | Refresh the diagram inside EA (place/connect do this automatically) |

## Typical workflow — add a component and wire it up

```powershell
$ea = "C:\Users\<user>\.claude\skills\ea-automation\scripts\ea.ps1"
# 1. Discover IDs (package, diagram, existing elements)
& $ea -Command status
# 2. Create the element (note the returned elementID)
& $ea -Command add-element -Name XxxService -Type Component -PackageID 2
# 3. Place it on the diagram
& $ea -Command place -ElementID 152 -DiagramID 1 -X 250 -Y 309 -Width 117 -Height 70
# 4. Connect it (arrow points client -> supplier)
& $ea -Command connect -ClientID 6 -SupplierID 152 -ConnectorType Dependency -DiagramID 1
```

EA refreshes the open diagram automatically after `place`/`connect`/`reload`.

## Companion: ea-mcp MCP server (read-only)

The `ea-mcp` MCP server (Sparx official, registered user-scope in `~/.claude.json`) may also be loaded in the session. It is read-only but adds a few things this CLI cannot do:

| MCP tool | Use for |
|---|---|
| `get_current_diagram` / `get_diagrams_information` | Rich view of a diagram (MDG types, stereotypes, connector routing) — good for verification after writes |
| `get_diagram_image` | Export the diagram as a PNG to show the user (only on explicit request) |
| `open_diagrams` / `select_element_in_diagram` / `select_element_in_browser` | Drive the EA UI (open a diagram, highlight an element for the user) |
| `find_element_in_diagrams` | Which diagrams an element appears on |
| `export_element_linked_documents` | Export linked documents as RTF |

Division of labor: **CLI = write + basic read; ea-mcp = verification, images, UI control.** If ea-mcp is not loaded in the current session, the CLI's `status` / `diagram` / `find` / `element` commands cover the read side on their own.

## Gotchas

- **Multiple EA windows open**: write commands auto-select the instance that owns the given IDs. Always run `status` first and use real IDs from its output — never assume IDs.
- **Connector direction**: `ClientID` = the depending element, `SupplierID` = the element being depended on; the arrow renders client → supplier.
- **Coordinates**: `diagram` output and `place` input both use x-right/y-down pixels (EA's raw `Top` property is inverted; the CLI normalizes it).
- `diagram` skips dangling diagram objects (ElementID 0 — XMI import artifacts); unresolvable elements are returned with an `error` field.
- No delete commands in v1 — destructive operations stay manual in the EA UI.
- If `status` finds no instance, EA is not running or no project is open.
