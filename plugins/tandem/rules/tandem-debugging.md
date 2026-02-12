<!-- tandem v1.2.1 -->
# Tandem Debugging

When Tandem appears to be in a broken or confused state, check the logs before guessing.

**Symptoms that warrant log inspection:**
- Missing or corrupted files (progress.md, MEMORY.md, stats.json, profile files)
- Session count, streaks, or stats looking wrong
- SessionEnd not compacting memory or extracting learnings
- Hooks not firing or producing unexpected output
- Any "issue(s) logged" message from the session startup display

**How to check:**
- Read `~/.tandem/logs/tandem.log` directly (the `/tandem:logs` skill also surfaces this)
- Log format: `date [LEVEL] [VERSION] [SCRIPT] message`
- Look for `[ERROR]` and `[WARN ]` entries first
- The `[SCRIPT]` field identifies which hook script generated the entry

**Do not load logs into context routinely.** Only read them when diagnosing a specific problem. The log file can grow large and most entries are informational.
