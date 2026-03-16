# arrow.el

arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

## About
Arrow introduces three layers of bookmarks to help you stay organized:
- **Global** - cross-project bookmarks
- **Project** - per-project file boookmarks
- **Buffer** - per-file line number bookmarks

arrow.el provides seamless navigation across all three layers with a unified interface. Unlike Emacs registers or Vim/Evil marks, these are properly isolated per layer and immune to clipboard pollution (yanks/deletes won't litter your bookmarks). QOL features include visual fringe markers, a floating hover menu, and at most two keybinds to jump to any bookmark.

### Org integration
The Org layer extends Arrow further by dynamically linking your code to living documentation. Each project automatically gets its own Org file, allowing every source file to connect back to it. Additionally, every file in a project has its own unique org file.
---

## Installation

### Using `use-package` + `package-vc-install` (Emacs 29+)

```elisp
(use-package arrow
  :vc (:fetcher "github" :repo "vmargb/arrow.el")
  :config
  (require 'arrow-org) ; optional org bookmarks
  (setq arrow-org-directory "~/org/arrow-notes/"))
```

### Straight
```elisp
(use-package arrow
  :straight (arrow :type git :host github :repo "vmargb/arrow.el")
  :config
  (require 'arrow-org) ; optional org bookmarks
  (setq arrow-org-directory "~/org/arrow-notes/"))
```

### Elpaca
Ensure you have `(elpaca-use-package-mode)`

```elisp
(use-package arrow
  :elpaca (arrow :host github :repo "vmargb/arrow.el")
  :config
  (require 'arrow-org) ; optional org bookmarks
  (setq arrow-org-directory "~/org/arrow-notes/"))
```


### Configuration (defaults)

```elisp
(setq arrow-persist t) ;; persists bookmark on disk
(setq arrow-auto-promote nil) ;; auto rearranges list when key added or used
(setq arrow-visual-marker t) ;; displays visual marker on line number
(setq arrow-visual-marker-position 'left) ;; marker position(left or right)
;; Org layer settings
(setq arrow-org-window-behavior 'same-window) ;; 'same-window, 'other-window, 'other-frame
```

## Commands

### Buffer bookmarks (line numbers)

| Command                  | Description                               |
| ------------------------ | ----------------------------------------- |
| `arrow-add`              | Create bookmark at point (keys: a-z, 1-9) |
| `arrow-show`             | Popup menu of buffer bookmarks            |
| `arrow-delete`           | Remove specific bookmark                  |
| `arrow-clear-all`        | Delete all buffer bookmarks               |
| `arrow-promote-bookmark` | Move bookmark to top of list              |
| `arrow-next-line` / `arrow-prev-line` | Cycle bookmarks                       |

### Project bookmarks (files)
| Command                                     | Description                           |
| ------------------------------------------- | ------------------------------------- |
| `arrow-project-add`                         | Add current file to project bookmarks |
| `arrow-project-show`                        | Show project bookmark menu            |
| `arrow-project-delete`                      | Remove project bookmark               |
| `arrow-project-next` / `arrow-project-prev` | Cycle bookmarks                       |

### Unified workflow (No UI)
Use these when you've confidently memorized your marks.

| Command | Description |
|-------------|---------|
| `arrow-jump-buffer` | Instantly jump to buffer line without popup menu. |
| `arrow-jump-project` | Instantly jump to project file without popup menu. |
| `arrow-jump` | Unified command for the above two options. |

### Org bookmarks
| Command                        | Description                              |
| ------------------------------ | ---------------------------------------- |
| `arrow-org-open-project`       | Toggle project notes ↔ source file       |
| `arrow-org-open-file`          | Toggle file-specific notes ↔ source file |
| `arrow-org-quick-capture`      | Capture note without leaving buffer      |
| `arrow-org-list-project-notes` | Browse all project notes                 |

**Smart return**: `arrow-org-open-project` and `open-file` remembers exactly which file you came from even across different files in the same project and restores your cursor position.


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

;; Org
(define-key arrow-mode-map (kbd "C-c o o") #'arrow-org-open-project)  ; project notes
(define-key arrow-mode-map (kbd "C-c o f") #'arrow-org-open-file)     ; file notes  
(define-key arrow-mode-map (kbd "C-c o c") #'arrow-org-quick-capture) ; capture without leaving
(define-key arrow-mode-map (kbd "C-c o l") #'arrow-org-list-project-notes)
```


## Screenshot
![bookmark screenshot](screenshots/buffer-bookmarks.png)
*Example using my init.el: d->dired, o->org, l->langs, t->themes, m->magit*

![project screenshot](screenshots/arrow-project.png)
*Example using user emacs directory*


## Todo

- arrow-jump repeat style feature to allow fast cycling without repetition
- Unified hydra-like menu that shows buffer-local + project bookmarks together
- Org bookmark integration with org-capture templates