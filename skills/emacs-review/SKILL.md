---
name: emacs-review
description: Analyze the codebase for improvements, dead code, bugs, or refactorings and send structured findings directly to Emacs via llm-review.el.
---

# Emacs Review Skill (`emacs-review`)

This skill inspects your codebase according to your review prompt or target files, extracts actionable code quality findings, and transmits them directly into an interactive Magit-style review buffer in GNU Emacs powered by `llm-review.el`.

> [!IMPORTANT]
> **Core Philosophy: AI Proposes, Human Disposes.**
> Autonomous code deletion and blind refactoring are fundamentally unsafe for non-trivial codebases. This skill operates under an uncompromising **Human-in-the-Loop (HITL)** architecture: the AI agent functions exclusively as an analytical scout, while the human developer retains sole authority, decision-making, and code ownership.
>
> **Strict Agent Boundary:**
> When invoked via `/emacs-review`, the AI agent is **strictly prohibited from directly editing, refactoring, or deleting any project files**. The agent's work concludes once structured findings are ingested into Emacs. Every code modification must be explicitly authorized by the human developer.

Within Emacs, each finding is rendered as a collapsible section with live buffer markers, letting you preview, navigate, dismiss (`x`), visit (`RET`), or cleanly delete the target code block (`d`) without line drift.

---

## When to Use

Invoke this skill whenever you want to:
- Review code quality, unused functions, or dead imports across the repository.
- Perform targeted refactoring or cleanup on specific files or git diffs.
- Inspect and delete deprecated APIs or legacy blocks interactively inside Emacs with human verification.

---

## Workflow Instructions

### Step 1: Analyze Codebase & Enclose Complete Syntactic Blocks

1. Examine `$ARGUMENTS` to determine the review scope:
   - Specific files or paths (e.g., `src/core/`, `lib/auth.py`).
   - Git diffs or branch comparisons (e.g., `git diff main`).
   - Thematic focus: dead code, anti-patterns, security, performance, or styling.
   - If `$ARGUMENTS` is empty or general, inspect recently modified files or core source trees.

2. Inspect the source files using file reading or code search tools.
   > [!IMPORTANT]
   > **Line Number Accuracy & Syntactic Enclosure:**
   > - You MUST verify exact 1-indexed line numbers by inspecting actual file contents. Never hallucinate or estimate line numbers.
   > - Line ranges (`start_line` to `end_line`) MUST enclose **complete syntactic blocks** (e.g., the entire function including decorators/docstrings, complete class definitions, whole conditional branches, or complete import statements).
   > - This is critical because pressing `d` in `llm-review` deletes the entire designated block. If line bounds cut across expressions or leave orphaned braces/indentation, the source file will be broken.

3. **Mandatory Counter-Evidence & Risk Assessment:**
   Before recommending an action (especially `"delete"`), actively search for reasons **not** to remove the block:
   - Check dynamic dispatch, string lookups, reflection, or `getattr` calls.
   - Check if the symbol is an interface implementation, hook, or exported public API.
   - Assign an honest `risk` (`"low"`, `"medium"`, `"high"`) and `confidence` (`"high"`, `"medium"`, `"low"`).
   - In `verification_note`, supply a crisp check for the human engineer (e.g. *"Verify whether `render_token` is called dynamically in serializers.py"*).

### Step 2: Create Project `.llm-review/` Directory & Write Fresh Review File

1. Ensure the `.llm-review/` directory exists inside the project directory:
   ```bash
   mkdir -p .llm-review
   ```

2. Generate a new timestamped filename for the fresh run:
   ```text
   .llm-review/review-YYYYMMDD-HHMMSS.json
   ```
   (e.g., `.llm-review/review-20261026-104500.json`).
   *Every time this skill is run, create a brand new file in `.llm-review/` with the current timestamp so that prior reviews remain preserved in the project history.*

3. Structure your analysis as a JSON array of objects matching the schema below and write it to the new file.

Each finding object should include the following keys:
- `file`: Path to the file (relative to repository root or absolute).
- `start_line`: 1-indexed starting line number (integer).
- `end_line`: 1-indexed ending line number (integer, inclusive).
- `title`: Concise title summarizing the finding.
- `reason`: Explanation of why this code should be removed, refactored, or fixed.
- `action`: Recommended action string (`"delete"`, `"refactor"`, `"fix"`, `"perf"`, `"security"`, `"style"`, or `"review"`).
- `risk`: Architectural risk rating (`"low"`, `"medium"`, or `"high"`).
- `confidence`: Confidence rating in the static analysis (`"high"`, `"medium"`, or `"low"`).
- `verification_note`: (Optional but strongly recommended) Specific instructions on what the human should double-check before approving.

#### JSON Schema Example:
```json
[
  {
    "file": "src/sample.py",
    "start_line": 42,
    "end_line": 56,
    "title": "Unused legacy helper `sample_old_calc`",
    "reason": "Superseded by `sample_calc_v2`; no static call sites found in repository.",
    "action": "delete",
    "risk": "low",
    "confidence": "high",
    "verification_note": "Verify that external plugins do not import this helper directly."
  },
  {
    "file": "src/sample.py",
    "start_line": 88,
    "end_line": 95,
    "title": "Redundant nil-check guard",
    "reason": "`when-let` already handles nil values; inner check is redundant.",
    "action": "refactor",
    "risk": "low",
    "confidence": "high",
    "verification_note": "Check that sub-expressions do not rely on side-effects of inner check."
  }
]
```

### Step 3: Trigger the Emacs Review Buffer

Execute the following command via `run_command` in the project root:

```bash
emacsclient -n -e "(llm-review-load-file \"$(pwd)/.llm-review/<GENERATED_FILENAME>.json\" \"$(pwd)/\"))"
```

Or to automatically open the latest review in the project:
```bash
emacsclient -n -e "(progn (require 'llm-review) (llm-review \"$(pwd)/\"))"
```

#### Troubleshooting & Fallbacks:
- **Emacs server not running:** If `emacsclient` reports "can't find socket; have you started the server?", notify the user to run `M-x server-start` inside Emacs or start Emacs with `emacs --daemon`.
- **Package not loaded:** If Emacs reports `void-function llm-review-load-file`, ensure `llm-review.el` is in Emacs's `load-path` or loaded via:
  ```bash
  emacsclient -n -e "(progn (load \"$(pwd)/llm-review.el\") (llm-review \"$(pwd)/\"))"
  ```

### Step 4: Present Review to User

Report findings to the user with a respectful, assistive posture. **Never state "I have deleted or cleaned up your code."** Instead, state:
> *"I have prepared X actionable proposals for your review in Emacs buffer `*llm-review*`. You have full control to inspect (`RET`), toggle preview (`TAB`), approve deletion (`d`), or dismiss (`x`)."*

---

## Emacs Review Keybindings Reference

| Key | Command | Description |
| :--- | :--- | :--- |
| `TAB` | `magit-section-toggle` | Toggle collapsible code snippet preview |
| `d` | `llm-review-delete` | Delete target code block in source buffer & refresh UI |
| `x` | `llm-review-dismiss` | Dismiss finding without touching source file |
| `RET` | `llm-review-visit` | Jump directly to target location in source buffer |
| `f` | `llm-review-filter-by-action` | Filter findings by action (e.g. `delete`, `refactor`) |
| `r` | `llm-review-filter-by-risk` | Filter findings by risk level (`low`, `medium`, `high`) |
| `F` | `llm-review-clear-filter` | Clear active filter and display all findings |
| `b` | `llm-review-browse-reviews` | Select and load any past review session from `.llm-review/` |
| `n` / `p` | `llm-review-next/prev` | Navigate to next / previous finding heading |
| `g` | `llm-review-refresh` | Re-render UI with dynamically updated line numbers |
| `q` | `quit-window` | Bury or close the `*llm-review*` window |
