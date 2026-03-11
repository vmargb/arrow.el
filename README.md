# arrow.el

arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

## What problem this solves
Editors need three distinct bookmark layers to stay organized and predictable:
- **Global** (built-in)
- **Project-isolated** (arrow.el)
- **Buffer-isolated** (arrow.el)

This provides both harpoon-style quick access to frequently used files and per-buffer marks for specific line numbers. Emacs and Vim/Evil registers *can* approximate this, but they aren’t properly isolated by buffer or project and are vulnerable to clipboard actions (yanks, deletes), which can cause unwanted behavior. arrow.el also adds quality-of-life features such as visual line markers, and at most two keypresses to jump to any bookmark(delegating all search activity to project or consult instead)

---

## Installation

### `package-vc-install` (Emacs 29+)

```elisp
(package-vc-install "https://github.com/vmargb/arrow.el.git")
```

### Using `use-package` + `:vc` (Emacs 29+)

```elisp
(use-package arrow
  :vc (:fetcher "github" :repo "vmargb/arrow.el"))
```

### Straight
```elisp
(use-package arrow
  :straight (arrow :type git :host github :repo "vmargb/arrow.el"))
```

### Elpaca
Ensure you have `(elpaca-use-package-mode)`

```elisp
(use-package arrow
  :elpaca (arrow :host github :repo "vmargb/arrow.el"))
```


### Configuration (defaults)

```elisp
(setq arrow-persist t) ;; persists bookmark in memory
(setq arrow-auto-promote nil) ;; auto rearranges list when key added or used
(setq arrow-visual-marker t) ;; displays visual marker on line number
```


## Commands

| Command | Description |
|-------------|---------|
| `arrow-add` | Create or overwrite a bookmark at point. Prompts for a single character (a-z or 1-9). |
| `arrow-show` | Display popup of all bookmarks for this file. Press any bookmark key to jump, `q` or `C-g` to cancel. |
| `arrow-delete` | Remove a specific bookmark by its character key. |
| `arrow-clear-all` | Delete all bookmarks for the current file. |
| `arrow-promote-bookmark` | Manually promote a bookmark to the top of the list. |
| `arrow-project-add` | Add file to project bookmarks |
| `arrow-project-show` | Show project bookmarks |
| `arrow-project-delete` | Delete bookmark for this project |


### Unified workflow (No UI)
Use these when you've confidently memorized your keybindings.

| Command | Description |
|-------------|---------|
| `arrow-jump-buffer` | Instantly jump to buffer line without popup menu. |
| `arrow-jump-project` | Instantly jump to project file without popup menu. |
| `arrow-jump` | Unified command for the above two options. |


## Screenshot
![bookmark screenshot](screenshots/buffer-bookmarks.png)
*Example using my init.el: d->dired, o->org, g->general, t->themes, m->magit*

![project screenshot](screenshots/arrow-project.png)
*Example using one of my projects*


## Todo

- arrow-jump repeat style feature to allow fast cycling without repetition
- Unified hydra-like menu that shows buffer-local + project bookmarks together