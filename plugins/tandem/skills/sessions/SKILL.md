---
description: "Use when the user wants to see active Tandem sessions, inspect session details, clean orphaned sessions, or understand which sessions share a project."
---

# Tandem Sessions

Inspect the session registry at `~/.tandem/sessions/`.

## Steps

1. **List all session directories** under `~/.tandem/sessions/`. For each, read `state.json` and display:
   - Session ID
   - Project (basename of project path)
   - Branch
   - Status (active/ended)
   - Current task
   - Last heartbeat (and how long ago)
   - PID (and whether it's still alive: `kill -0 $pid`)

2. **Group by project** to show topology: which sessions share a project.

3. **Identify orphans**: sessions where the PID is dead or heartbeat is older than 5 minutes with a dead process. Offer to clean them up (delete the session directory) if found.

## Output format

```
Active Sessions:
  jonnyn-cv (2 sessions)
    abc123  main  "building session topology"  heartbeat: 30s ago  pid: 12345 ✓
    def456  main  "fixing CSS layout"          heartbeat: 2m ago   pid: 12346 ✓

  claude-tandem (1 session)
    ghi789  main  "adding frontmatter schema"  heartbeat: 1m ago   pid: 12347 ✓

Orphaned Sessions:
  jkl012  jonnyn-cv  pid: 99999 ✗ (dead)  last heartbeat: 15m ago
  → Clean up? (delete ~/.tandem/sessions/jkl012/)
```

## Arguments

- No arguments: show all sessions
- `clean`: force-clean all orphaned sessions without prompting
- `<session-id>`: show detailed state.json for a specific session

## Implementation

Use bash to read `~/.tandem/sessions/*/state.json` files. Check PIDs with `kill -0`. Calculate heartbeat age from the ISO timestamp. No external dependencies beyond jq.
