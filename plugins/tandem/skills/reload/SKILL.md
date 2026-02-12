---
description: "Use when the user wants to sync their local Tandem source with the plugin cache, or when plugin changes aren't taking effect mid-session."
---

# Reload Tandem Plugin Cache

Sync the local Tandem source directory into Claude Code's plugin cache so that script, skill, and rule changes take effect immediately.

## Steps

1. Read `~/.claude/plugins/known_marketplaces.json` to find the `tandem-marketplace` entry and its `path` (the source directory).
2. Read `~/.claude/plugins/installed_plugins.json` to find the cache `install_path` for the tandem plugin.
3. Check if the cache path is already a symlink pointing to the correct source plugin directory (`<marketplace_path>/plugins/tandem`).
   - If yes: report "Already synced. Cache is a symlink to source."
   - If no: run `rm -rf <cache_path> && ln -s <source_plugin_dir> <cache_path>` (confirm with user first).
4. Report what changed.

**Note:** Script, skill, and rule changes are live immediately after sync. Changes to `hooks/hooks.json` require a session restart (hooks are snapshotted at startup).

If the marketplace or plugin entries aren't found, explain that this skill requires a local directory marketplace setup (see CONFIGURATION.md).
