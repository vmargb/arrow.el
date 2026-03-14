# arrow.el

arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

## About
Editors need three distinct bookmark layers to stay organized:
- **Global**
- **Project**
- **Buffer**

This provides both per-project bookmarks to frequently used files and per-buffer bookmarks to specific line numbers. Emacs and Vim/Evil registers *can* do this, but they aren’t properly isolated by buffer or project and Evil is vulnerable to clipboard actions (yanks, deletes), which can cause unwanted behaviour. arrow.el also adds QOL features such as visual fringe markers, a floating hover menu, and at most two keybinds to jump to any bookmark(delegating all search activity to project instead)

---

## Installation

### Using `use-package` + `package-vc-install` (Emacs 29+)

```elisp
(use-package arrow
  :vc (:fetcher "github" :repo "vmargb/arrow.el")
  :config
  (arrow-mode 1))
```

### Straight
```elisp
(use-package arrow
  :straight (arrow :type git :host github :repo "vmargb/arrow.el")
  :config
  (arrow-mode 1))
```

### Elpaca
Ensure you have `(elpaca-use-package-mode)`

```elisp
(use-package arrow
  :elpaca (arrow :host github :repo "vmargb/arrow.el")
  :config
  (arrow-mode 1))
```


### Configuration (defaults)

```elisp
(setq arrow-persist t) ;; persists bookmark on disk
(setq arrow-auto-promote nil) ;; auto rearranges list when key added or used
(setq arrow-visual-marker t) ;; displays visual marker on line number
(setq arrow-visual-marker-position 'left) ;; marker position(left or right)
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
Use these when you've confidently memorized your marks.

| Command | Description |
|-------------|---------|
| `arrow-jump-buffer` | Instantly jump to buffer line without popup menu. |
| `arrow-jump-project` | Instantly jump to project file without popup menu. |
| `arrow-jump` | Unified command for the above two options. |


#### Example keybinds
```elisp
;; Buffer
(define-key arrow-mode-map (kbd "C-c b a") #'arrow-add) ;; add line number mark
(define-key arrow-mode-map (kbd "C-c b l") #'arrow-show) ;; show lines numbers
(define-key arrow-mode-map (kbd "C-c b d") #'arrow-delete) ;; delete line number
(define-key arrow-mode-map (kbd "C-c b j") #'arrow-jump-buffer) ;; jump to line (no UI)
(define-key arrow-mode-map (kbd "C-c b n") #'arrow-next-line) ;; next line
(define-key arrow-mode-map (kbd "C-c b p") #'arrow-prev-line) ;; previous line

;; Project
(define-key arrow-mode-map (kbd "C-c p a") #'arrow-project-add) ;; add project file mark
(define-key arrow-mode-map (kbd "C-c p l") #'arrow-project-show) ;; show all files
(define-key arrow-mode-map (kbd "C-c p d") #'arrow-project-delete) ;; delete file
(define-key arrow-mode-map (kbd "C-c p j") #'arrow-jump-project) ;; jump to file (no UI)
(define-key arrow-mode-map (kbd "C-c p n") #'arrow-project-next) ;; next file
(define-key arrow-mode-map (kbd "C-c p p") #'arrow-project-prev) ;; previous file
```


## Screenshot
![bookmark screenshot](screenshots/buffer-bookmarks.png)
*Example using my init.el: d->dired, o->org, l->langs, t->themes, m->magit*

![project screenshot](screenshots/arrow-project.png)
*Example using user emacs directory*


## Todo

- arrow-jump repeat style feature to allow fast cycling without repetition
- Unified hydra-like menu that shows buffer-local + project bookmarks together