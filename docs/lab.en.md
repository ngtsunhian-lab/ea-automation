# Hands-On Lab: Claude Code Skills in Practice

**Based on the [ea-automation](https://github.com/ngtsunhian-lab/ea-automation) skill**

> A 60-minute interactive lab: download a real skill, make it work, then roll up your sleeves and improve it.

---

## Objectives

- Understand the anatomy of a Claude Code skill: a folder + `SKILL.md` + optional scripts
- Learn to install, trigger, and verify a skill
- Experience the full chain of "natural language → tool invocation"
- Master the principles of skill optimization and improve a real skill hands-on

## Prerequisites

| Item | Requirement |
|---|---|
| OS | Windows (the EA COM interface is Windows-only) |
| Claude Code | installed and working |
| Enterprise Architect | installed with a project open (trial is fine) |
| Network | GitHub access |

**Time plan:** Part 1 ≈ 15 min · Part 2 ≈ 25 min · Part 3 ≈ 20 min

---

## Part 1 — Download & Load the Skill (15 min)

### 1.1 Understand the anatomy

A skill is just a folder under `~/.claude/skills/`, with at least one `SKILL.md`:

```
~/.claude/skills/ea-automation/
├── SKILL.md          ← the manual: name, trigger conditions, usage (for Claude to read)
└── scripts/
    └── ea.ps1        ← the worker script (for the OS to execute)
```

The frontmatter at the top of `SKILL.md` is the key — its `description` decides **when** Claude recalls this skill:

```markdown
---
name: ea-automation
description: Read and write a running Enterprise Architect model ...
  Use when the user wants to programmatically edit an EA model
  (e.g. "add a component to the EA diagram", "connect these elements in EA") ...
---
```

Note the trigger phrases in parentheses: they teach Claude, "when the user says something like this, use me."

### 1.2 Hands-on: install

Open PowerShell:

```powershell
# 1. Clone the repo
git clone https://github.com/ngtsunhian-lab/ea-automation.git "$env:TEMP\ea-automation"

# 2. Copy it into Claude Code's skills directory
Copy-Item -Recurse "$env:TEMP\ea-automation" "$env:USERPROFILE\.claude\skills\ea-automation"

# 3. Verify all three files are there
dir "$env:USERPROFILE\.claude\skills\ea-automation"
```

### 1.3 Checkpoint ✅

Start a fresh Claude Code session (or restart the current one) and ask:

> What skills do you have? What does ea-automation do?

Claude should be able to describe it. **Note:** the skill list is loaded at session start — you must restart the session after installing.

**Discussion question:** Why does the `description` include trigger phrases (like "add a component to the EA diagram")? What happens without them?

---

## Part 2 — Get It Running (25 min)

### 2.1 Set the stage

1. Open Enterprise Architect with any project (a new one is fine)
2. Open or create a diagram (component or class diagram)
3. Keep EA running — the skill drives the **running** EA instance through its COM interface

### 2.2 Drive it with natural language

In Claude Code, just say (don't type the commands yourself!):

> Look at the diagram currently open in EA, add a component called DemoService to it,
> and connect it to any existing element on the diagram.

Then watch what Claude does. It should:

1. Run the skill's `ea.ps1 -Command status` to get the project structure and real IDs
2. `add-element` to create the element → capture the new element ID
3. `place` to put the element on the diagram
4. `connect` to create the connector
5. The diagram in EA **refreshes automatically** — the new component appears

### 2.3 Under the hood

Every step Claude took was a call to the skill's CLI:

```powershell
$ea = "$env:USERPROFILE\.claude\skills\ea-automation\scripts\ea.ps1"

& $ea -Command status                          # 1. Survey the environment: instances, packages, diagrams, element IDs
& $ea -Command add-element -Name DemoService -PackageID 2
& $ea -Command place -ElementID 999 -DiagramID 1 -X 250 -Y 300 -Width 117 -Height 70
& $ea -Command connect -ClientID 6 -SupplierID 999 -ConnectorType Dependency -DiagramID 1
```

All commands print JSON; failures return `{"error": "..."}` with exit code 1.

**This is the essence of a skill: packaging a complex workflow into an interface Claude can drive reliably.**

### 2.4 Hands-on: run it manually

Run the 4 commands above yourself in PowerShell (replace the example IDs with real ones from the `status` output). Appreciate what Claude normally does for you: read the JSON, extract the IDs, fill in the next command.

### 2.5 Checkpoint ✅

| Check | How |
|---|---|
| Element created | `& $ea -Command find -Name DemoService` returns an ID |
| Placed on diagram | Visible in EA |
| Connected | `& $ea -Command element -ElementID <id>` lists connectors |

**Troubleshooting:**

| Symptom | Cause | Fix |
|---|---|---|
| `No running EA instance found` | EA not running or no project open | Open EA + a project |
| ID not found | Multiple EA instances; the ID belongs to another one | Run `status` first, use real IDs |
| Diagram stale | EA window inactive | `& $ea -Command reload -DiagramID <id>` |

---

## Part 3 — Optimize the Skill (20 min)

Optimizing a skill happens at three levels, from most to least important:

| Level | What you optimize | Why |
|---|---|---|
| ① Trigger quality | Is the `description` accurate? | A bad description means Claude never uses it |
| ② Safety | Do dangerous operations have guardrails? | Skills have real side effects |
| ③ Capability | New commands, better output | Add on demand; avoid over-engineering |

### 3.1 Exercise A: improve the trigger

Open `SKILL.md` and edit only the frontmatter `description` so more phrasings trigger it. For example, users might say:

- "add a service to the architecture diagram"
- "wire up the components in EA"
- "help me draw a component diagram"

Restart the session after each edit and test whether the new phrasing triggers it. **Record:** which phrasings trigger it, and which don't?

### 3.2 Exercise B: add a safety guardrail

The `connect` command currently allows connecting **any** two elements — including note-to-note. Add a guardrail: refuse to connect when either side is a `Text`/`Note` element.

Hint (in the `connect` branch, right after you obtain `$client`):

```powershell
foreach ($side in @($client, $rep.GetElementByID($SupplierID))) {
  if ($side.Type -in @("Text", "Note")) {
    Fail ("Refusing to connect a " + $side.Type + " element (safety guardrail)")
  }
}
```

Then test: ① normal connects still succeed; ② connecting a Text element is refused with a JSON error.

### 3.3 Exercise C (optional): add a new command

Following the existing command pattern, add a `count` command to `ea.ps1` that tallies elements by type across all packages. Skeleton:

```powershell
elseif ($Command -eq "count") {
  # Walk all packages (reuse the stack pattern from the find command), group by $e.Type
  # Output @{ counts = @{ Component = 12; Class = 5; Text = 4 } }
}
```

Don't forget to update two more places: the "Unknown command" error message and the command table in `SKILL.md`.

### 3.4 Three principles of optimization

1. **Surgical changes** — touch only the lines your goal requires; never "tidy up" unrelated code along the way
2. **Test immediately** — run the affected command right after each edit
3. **YAGNI** — don't add features nobody asked for; this skill has no `delete` command *on purpose* (destructive operations stay manual in the EA UI)

---

## Appendix A — ea-automation Command Reference

| Command | Arguments | What it does |
|---|---|---|
| `status` | — | All running EA instances: project name, package tree, element/diagram IDs |
| `diagram` | `-DiagramID N` | Elements (with positions) and connectors on that diagram |
| `find` | `-Name substr` | Substring search of element names |
| `element` | `-ElementID N` | One element: stereotype, attributes, operations, connectors |
| `add-element` | `-Name X -PackageID N [-Type Component]` | Create an element (idempotent) |
| `place` | `-ElementID N -DiagramID N -X -Y -Width -Height` | Put on diagram / move position |
| `connect` | `-ClientID N -SupplierID N [-ConnectorType] [-DiagramID]` | Create a connector (arrow: client → supplier) |
| `reload` | `-DiagramID N` | Refresh the diagram inside EA |

## Appendix B — Knowledge Map

- **Skill mechanism**: folder + SKILL.md (frontmatter `description` = trigger) → loaded at session start
- **Encapsulation**: wrap "complex but reliable" operations (CLI/scripts) so the "flexible but less deterministic" party (Claude) handles understanding and orchestration
- **Safety design**: reads are open, writes are constrained, deletes are simply absent
- **Iteration method**: minimal change → verify immediately → extend on demand
