# arrow.el

arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

## What problem this solves
Every editor should have three layers of bookmarks, global(built-in) and project-scoped + buffer-scoped bookmarks -> arrow.el.
This lets you set marks to a specific line number inside of a buffer and jump to them with a single keypress. Vim/Evil registers and Emacs can do this but they are not properly isolated per buffer or per project. And arrow gives you more QOL features such as visual line indicators(using left or right fringe), as well as a useful floating menu like in arrow.nvim.

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
  (define-key arrow-mode-map (kbd "C-c b j") #'arrow-jump-buffer))
  (define-key arrow-mode-map (kbd "C-c p a") #'arrow-project-add)
  (define-key arrow-mode-map (kbd "C-c p l") #'arrow-project-show)
  (define-key arrow-mode-map (kbd "C-c p d") #'arrow-project-delete))
  (define-key arrow-mode-map (kbd "C-c p j") #'arrow-jump-project))
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
| `arrow-add` | Create or overwrite a bookmark at point. Prompts for a single character (a-z or 0-9). |
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
*Example using user emacs directory as project*


## Todo

- arrow-jump repeat style feature to allow fast cycling without repetition
- Unified hydra-like menu that shows buffer-local + project bookmarks together