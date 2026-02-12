<!-- tandem v1.3.0 -->
# Tandem Commit

Git is the only permanent record. Progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

Every commit body is a context restoration point. When a future LLM session reads `git log`, the commit bodies are all it has. They must be rich enough to reconstruct intent, decisions, and reasoning without any other source.

**Subject:** Conventional Commits. `<type>(<scope>): <description>`, lowercase, imperative, no period.
Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.

**Body:** The diff shows what changed. The body must capture everything the diff cannot:

- **Why does this change exist?** What process led here? What request, bug, or goal triggered this work?
- **What was considered?** Were there other approaches? Why did this one win? What tradeoffs were accepted?
- **What constraints or unknowns shaped this?** What did we know at the time? What didn't we know? What assumptions were we working from? What knowledge and pretense were we operating under?
- **Where does this sit?** Is this part of a larger effort? What came before, what comes next?

Write for machine comprehension. Be explicit about intent, reasoning, and epistemic state. Capture the developer's thinking at the moment of implementation. Don't summarise the diff, the diff describes itself. Describe what the diff cannot: the why, the what-else, the what-next.

This is not bureaucracy. This is the permanent record. When someone asks "why is this code the way it is?" six months from now, the commit body is the answer. Write it so an LLM can reconstruct the full context of this session from the commit message alone.

Co-Authored-By and Signed-off-by lines are not body.
