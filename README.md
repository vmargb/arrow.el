# arrow.el

arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

## What problem this solves
Every editor should have three layers of bookmarks, global(built-in), project-scoped(harpoon-style), and buffer-scoped -> arrow.el.
This lets you set marks inside of a buffer and jump to them with a single keypress. Vim/Evil registers and Emacs registers can do this but they are not isolated per buffer. And this gives you more QOL features such as:
- **File-scoped marks:** Unlike Emacs registers (or vim/evil registers), marks created with arrow.el are isolated to each file.
- **Quick navigation:** Jump to a mark in one keypress with transient menu showing each mark and its line contents.
- **Visual selector:** Compact UI which shows each mark in a visual window as well as fringe marks in the buffer.

---

## Installation

Add to your load path and require:

```elisp
(add-to-list 'load-path "/path/to/arrow")
(require 'arrow)
```

Or use `use-package`:

```elisp
(use-package arrow
  :load-path "/path/to/arrow")
  :config
  (define-key arrow-mode-map (kbd "C-c b a") #'arrow-add)
  (define-key arrow-mode-map (kbd "C-c b l") #'arrow-show)
  (define-key arrow-mode-map (kbd "C-c b d") #'arrow-delete))
```

### Configuration (defaults)

```elisp
(setq arrow-persist t) ;; persists bookmark in memory
(setq arrow-auto-promote nil) ;; auto rearranges list when key added or used
```


## Commands

| Command | Description |
|-------------|---------|
| `arrow-add` | Create or overwrite a bookmark at point. Prompts for a single character (a-z or 0-9). |
| `arrow-show` | Display popup of all bookmarks for this file. Press any bookmark key to jump, `q` or `C-g` to cancel. |
| `arrow-delete` | Remove a specific bookmark by its character key. |
| `arrow-clear-all` | Delete all bookmarks for the current file. |
| `arrow-promote-bookmark` | Manually promote a bookmark to the top of the list. |
| `arrow-project-add` | Add file to project bookmarks |
| `arrow-project-show` | Show project bookmarks |
| `arrow-project-delete` | Delete bookmark for this project |

## Screenshot
![bookmark screenshot](screenshots/buffer-bookmarks.png)
*Example using my init.el: d->dired, o->org, g->general, t->themes, m->magit*

![project screenshot](screenshots/arrow-project.png)
*Example using user emacs directory as project*


## Todo

- fringe marker on line
- Project-scoped transient menu
