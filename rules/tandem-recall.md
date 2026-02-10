<!-- tandem v1.0.0 -->
# Tandem Recall

For non-trivial sessions, maintain progress.md in your auto-memory directory (alongside MEMORY.md) as a running log of what's been done, key decisions, and anything that should survive context compaction. The Tandem SessionEnd hook reads this file.

When discovering user or codebase patterns worth persisting, write them to MEMORY.md. The SessionEnd hook will compact MEMORY.md to stay under 200 lines — so write freely, knowing stale details will decay naturally.
