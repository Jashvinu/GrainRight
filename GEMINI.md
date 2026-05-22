<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.

## Mandatory Engineering Skills

This project follows strict engineering workflows from `agent-skills`. These are mandatory for all development tasks.

### 1. Spec-Driven Development
**When:** Starting any new feature or non-trivial change.
**Process:**
- Define **Objective** and **Success Criteria**.
- Surface **Assumptions** immediately.
- Create a `SPEC.md` and get human approval before coding.
- Break down into a plan and discrete tasks.

### 2. Test-Driven Development (TDD)
**When:** Implementing logic, fixing bugs, or changing behavior.
**Process:**
- **Red:** Write a failing test first.
- **Green:** Write minimal code to pass.
- **Refactor:** Clean up while keeping tests green.
- **Prove-It Pattern:** For bugs, always write a reproduction test first.

### 3. Code Review & Quality
**When:** Before merging any change.
**Process:**
- Review across 5 axes: **Correctness, Readability, Architecture, Security, Performance**.
- Target small changes (~100 lines).
- Use descriptive commit messages (Imperative mood, "Why" not just "What").
- Identify and remove dead code.

---
*To activate a specific workflow's detailed instructions, use `activate_skill` with the skill name (e.g., `spec-driven-development`).*

