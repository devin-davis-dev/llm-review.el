# llm-review.el

An Emacs package providing a Magit-style interactive code review UI for LLM-generated code analysis findings.

---

## Design Philosophy: AI Proposes, Human Disposes

Autonomous code deletion and blind multi-file refactoring by AI coding assistants frequently introduce silent regressions, break dynamic reflection/dispatch, or eliminate intentionally preserved interfaces. 

`llm-review.el` is built on an unapologetic **Human-in-the-Loop (HITL)** architecture:
- **The AI is an analytical scout**: It combs through your repository, traces symbol references, assesses risk, and flags candidate findings.
- **The Human is the pilot and sole authority**: You rapidly triage proposals inside Emacs with single-key ergonomics (<kbd>TAB</kbd>, <kbd>RET</kbd>, <kbd>d</kbd>, <kbd>x</kbd>). You verify context, approve deletions, or dismiss false-positives with zero friction.
- **No autonomous modification**: AI agents using the `emacs-review` skill are strictly prohibited from directly editing source code—every change is authorized by you in Emacs.

---

## Overview

When coding assistants (like Google Antigravity, Claude, ChatGPT, etc.) or external static analysis CLI tools produce lists of code quality issues, dead code, or refactoring suggestions, reviewing them in markdown or raw JSON is cumbersome.

`llm-review.el` brings the familiar, battle-tested ergonomics of `magit-section` to code reviews:
- **Magit-style collapsible sections**: Inspect findings at a high level or press `TAB` to expand live code previews.
- **Drift-proof buffer markers**: Ingests line ranges (`start_line`, `end_line`) into live Emacs buffer markers (`make-marker` with insertion type `t`). When you delete or modify earlier blocks in a file, later findings automatically adjust their positions without drifting out of sync.
- **Single-key review actions**:
  - `TAB`: Toggle code snippet preview (`magit-section-toggle`)
  - `d`: Delete the target code block directly in the source buffer, clean up markers, and refresh the UI.
  - `x`: Dismiss the finding without touching the source file.
  - `RET`: Jump straight to the source location with pulse highlighting (`llm-review-visit`).
  - `n` / `p`: Navigate to next / previous finding.
  - `g`: Refresh the review UI with dynamic line numbers.
  - `q`: Quit / bury the review window.

---

## Installation

### Doom Emacs
In your `packages.el`:
```elisp
(package! llm-review
  :recipe (:host github :repo "devin-davis-dev/llm-review.el""))
```
Or for local development:
```elisp
(package! llm-review
  :recipe (:local-repo "~/Projects/llm-review.el"))
```

### Straight.el
```elisp
(straight-use-package
 '(llm-review :type git :host github :repo "devin-davis-dev/llm-review.el"))
```

### Manual / `use-package`
```elisp
(use-package llm-review
  :load-path "~/Projects/llm-review.el"
  :commands (llm-review-load-file))
```

---

## Usage

### 1. Ingesting Findings from CLI Tools or Agent Skills

Reviews are stored as timestamped JSON files in the project's `.llm-review/` folder (e.g., `.llm-review/review-20261026-104500.json`).

* **Open the latest project review:**
  ```elisp
  M-x llm-review
  ```
* **Browse and select from all past reviews:**
  ```elisp
  M-x llm-review-browse-reviews
  ```
* **Load any specific JSON file directly:**
  ```elisp
  M-x llm-review-load-file RET .llm-review/review-20261026-104500.json RET
  ```

Or trigger directly from a shell script or coding agent using `emacsclient`:
```bash
emacsclient -n -e '(llm-review "$(pwd)/")'
```

### 2. JSON Schema Format

The input JSON should be an array of objects matching the following schema:

```json
[
  {
    "file": "src/utils.py",
    "start_line": 42,
    "end_line": 56,
    "title": "Unused helper function `calc_score`",
    "reason": "Superseded by `score_v2`; no longer referenced anywhere in the repository.",
    "action": "delete",
    "risk": "low",
    "confidence": "high",
    "verification_note": "Verify external plugins do not call this helper dynamically."
  },
  {
    "file": "src/auth.py",
    "start_line": 105,
    "end_line": 118,
    "title": "Redundant token validation block",
    "reason": "Token is already validated in the outer middleware.",
    "action": "refactor",
    "risk": "medium",
    "confidence": "high",
    "verification_note": "Check that sub-methods do not rely on local token mutation."
  }
]
```

---

## Keybindings Reference

Inside `llm-review-mode` (`*llm-review*`):

| Key | Command | Description |
| :--- | :--- | :--- |
| `TAB` | `magit-section-toggle` | Toggle collapsible code snippet preview |
| `d` | `llm-review-delete` | Delete target code block in source buffer & refresh UI |
| `x` | `llm-review-dismiss` | Dismiss finding without touching source file |
| `RET` | `llm-review-visit` | Jump to source location (pulsing region) |
| `f` | `llm-review-filter-by-action` | Filter findings by action (e.g. `delete`, `refactor`) |
| `r` | `llm-review-filter-by-risk` | Filter findings by risk level (`low`, `medium`, `high`) |
| `F` | `llm-review-clear-filter` | Clear active action & risk filters and show all findings |
| `b` | `llm-review-browse-reviews` | Browse and load past review runs from `.llm-review/` |
| `n` | `llm-review-next-finding` | Move to next finding |
| `p` | `llm-review-previous-finding` | Move to previous finding |
| `g` | `llm-review-refresh` | Re-render UI with dynamic line numbers |
| `q` | `quit-window` | Bury/close review buffer |
| `C-c C-k` | `llm-review-clear` | Clear all findings and detach all markers |

---

## Configuration

Customize `llm-review` options via `M-x customize-group RET llm-review`:

| Option | Default | Description |
| :--- | :--- | :--- |
| `llm-review-save-buffer-on-delete` | `t` | Automatically save source buffer to disk after deleting a block |
| `llm-review-inhibit-formatters-on-save` | `t` | Suppress auto-formatters (`before-save-hook`, `after-save-hook`, `apheleia`) during deletions |
| `llm-review-confirm-delete` | `nil` | Prompt for confirmation before deleting code blocks |
| `llm-review-highlight-source-on-visit` | `t` | Pulse/highlight target region when visited with `RET` |
| `llm-review-directory` | `".llm-review"` | Directory name in project root for storing review JSON files |

---

## Agent Skill (`emacs-review`)

This repository includes a model-agnostic skill definition at `skills/emacs-review/SKILL.md` designed for AI coding agents.

When invoked, the agent:
1. Analyzes code based on your prompt (e.g. searching for dead code or refactoring opportunities).
2. Verifies exact 1-indexed line numbers enclosing complete syntactic blocks.
3. Creates a `.llm-review/` directory in the project root if needed.
4. Writes a fresh timestamped file (e.g. `.llm-review/review-20261026-104500.json`), preserving review history.
5. Triggers `llm-review` in Emacs via `emacsclient`.

---

## Development & Testing

Run tests and byte-compile using GNU `make`:

```bash
make compile  # Byte-compilation with warnings treated as errors
make test     # Run ERT test suite in batch mode
make clean    # Remove compiled .elc and temporary artifacts
```

---

## License

GPL-3.0-or-later
# llm-review.el
