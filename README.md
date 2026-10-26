# llm-review.el

A Emacs package providing a Magit-style interactive code review UI for LLM-generated code analysis findings.

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

### 1. Ingesting Findings from CLI Tools

Load any JSON file containing findings:
```elisp
M-x llm-review-load-file RET /path/to/findings.json RET /path/to/repo/ RET
```

Or trigger directly from a shell script or agent using `emacsclient`:
```bash
emacsclient -n -e '(llm-review-load-file "/tmp/llm-review.json" "$(pwd)/")'
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
    "action": "delete"
  },
  {
    "file": "src/auth.py",
    "start_line": 105,
    "end_line": 118,
    "title": "Redundant token validation block",
    "reason": "Token is already validated in the outer middleware.",
    "action": "refactor"
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
| `F` | `llm-review-clear-filter` | Clear active action filter and show all findings |
| `n` | `llm-review-next-finding` | Move to next finding |
| `p` | `llm-review-previous-finding` | Move to previous finding |
| `g` | `llm-review-refresh` | Re-render UI with dynamic line numbers |
| `q` | `quit-window` | Bury/close review buffer |
| `C-c C-k` | `llm-review-clear` | Clear all findings and detach all markers |

---

## Agent Skill (`emacs-review`)

This repository includes a model-agnostic skill definition at `skills/emacs-review/SKILL.md` designed for AI coding agents.

When invoked, the agent:
1. Analyzes code based on your prompt (e.g. searching for dead code or refactoring opportunities).
2. Verifies exact 1-indexed line numbers enclosing complete syntactic blocks.
3. Writes findings to `/tmp/llm-review.json`.
4. Triggers `llm-review-load-file` in Emacs via `emacsclient`.

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
