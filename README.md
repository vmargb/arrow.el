# arrow.el

## What problem this solves

arrow.el is heavily inspired by the neovim plugin arrow.nvim. This is a lightweight bookmarking system that keeps navigation marks scoped strictly to individual files. Arrow lets you drop single-character marks (a-z, 0-9) at specific lines using a single keypress, then jump back to them instantly through a transient menu. The bookmarks are isolated per-file and survive across Emacs restarts without requiring any manual save/load actions, making them immediately accessible.

---

## Installation

Add to your load path and require:

```elisp
(add-to-list 'load-path "/path/to/arrow")
(require 'arrow)

(add-hook 'prog-mode-hook #'arrow-mode)
(add-hook 'text-mode-hook #'arrow-mode)
```

Or use `use-package`:

```elisp
(use-package arrow
  :load-path "/path/to/arrow")
```

## Commands

| Key Binding | Command | Description |
|-------------|---------|-------------|
| `C-c b a` | `local-bm-add` | Create or overwrite a bookmark at point. Prompts for a single character (a-z or 0-9). |
| `C-c b l` | `local-bm-show` | Display popup of all bookmarks for this file. Press any bookmark key to jump, `q` or `C-g` to cancel. |
| `C-c b d` | `local-bm-delete` | Remove a specific bookmark by its character key. |
| `C-c b C` | `local-bm-clear-all` | Delete all bookmarks for the current file and remove its storage file. |

## Todo

- automatic bookmark-naming
- reorder bookmark file
- Project-scoped transient menu
