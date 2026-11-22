# RLS Companion Mod Skills

A field-tested knowledge base for building **companion mods for RLS Career Overhaul**
(v2.8.x, BeamNG.drive 0.40.x) without editing `rls_career_overhaul.zip`. Every pattern here
shipped in rls_auto_restock and survived live debugging.

| Skill | What it covers |
| --- | --- |
| [RLS mod architecture](rls-mod-architecture.md) | The `overhaul` namespace, manifest-driven loading, hooks, where store state lives |
| [Extension development](rls-extension-development.md) | modScript pattern, upvalue anchors into RLS state, persistence, economy, timers |
| [UI integration](rls-ui-integration.md) | Business-computer tabs, component resolution chain, the three traps that blank tabs |
| [Debugging](rls-debugging.md) | The layered diagnostic playbook, log locations, console quirks, hot-reload damage |
| [Pitfalls & revelations](rls-pitfalls.md) | The gotchas list — empty-array round-trips, bridge namespaces, VFS priority |
| [Quickstart & quick wins](rls-quickstart.md) | Copy-paste skeletons, console cheat sheet, release discipline |

## The three traps in one paragraph

If you only read one page: [ui-integration.md](rls-ui-integration.md). An RLS business-computer
tab from an add-on mod must survive (1) RLS's strict manifest validation (namespace-prefixed
ids), (2) the Lua→UI JSON round-trip turning RLS's empty `views` arrays into broken objects
that crash the component resolver, and (3) RLS's patched `lua` bridge, which hides extensions
it doesn't know about. Each has a runtime fix that works without touching RLS's files.

## Getting started

Read [architecture](rls-mod-architecture.md), then scaffold with
[quickstart](rls-quickstart.md). When something misbehaves,
[debugging](rls-debugging.md) tells you which layer lied to you.
