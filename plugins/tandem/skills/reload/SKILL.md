---
description: "Use when the user wants to sync their local Tandem source with the plugin cache, or when plugin changes aren't taking effect mid-session."
---

# Reload Tandem Plugin Cache

Sync the local Tandem source directory into Claude Code's plugin cache so that script, skill, and rule changes take effect immediately.

## Steps

1. Read `~/.claude/plugins/known_marketplaces.json` to find the `tandem-marketplace` entry. The source directory is at `source.path` (or `installLocation`).
2. Read `~/.claude/plugins/installed_plugins.json` to find the `tandem@tandem-marketplace` entry and its `installPath` (the cache path).
3. Run `readlink <cache_path>` to check if it's already a symlink.
   - If it resolves to `<source_dir>/plugins/tandem`: report "Already synced. Cache is a symlink to source."
   - Otherwise: run `rm -rf <cache_path> && ln -s <source_dir>/plugins/tandem <cache_path>` and report what changed. No confirmation needed, this is a safe, reversible operation.

**Note:** Script, skill, and rule changes are live immediately after sync. Changes to `hooks/hooks.json` require a session restart (hooks are snapshotted at startup).

If the marketplace or plugin entries aren't found, explain that this skill requires a local directory marketplace setup (see CONFIGURATION.md).
