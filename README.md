# arrow.el

<div align="center">

  <h3>Buffer-local marks</h3>
  <img src="screenshots/buffer-bookmarks.png" alt="Bookmark screenshot" width="600"/>
  <p><em>Example using my <code>init.el</code>: d → dired, o → org, l → langs, t → themes, m → magit</em></p>

  <br>

  <h3>Project marks</h3>
  <img src="screenshots/arrow-project.png" alt="Project screenshot" width="600"/>
  <p><em>Example using user Emacs directory</em></p>

</div>


---

> [!NOTE]
> arrow.el is heavily inspired by the neovim plugin [arrow.nvim](https://github.com/otavioschwanck/arrow.nvim)

<p>
<br>
</p>

## About
<div align="center">
  <img src="screenshots/options.png" alt="Bookmark screenshot" width="400"/>
  <br>
</div>

Arrow introduces four layers of bookmarks to help you stay organized:
- **Global** - cross-project bookmarks
- **Project** - per-project file boookmarks
- **Buffer** - per-file line number bookmarks
- **Org** - per-project & per-buffer org bookmarks

arrow.el provides seamless navigation across all layers with a unified interface. Unlike Emacs registers or Vim/Evil marks, these are properly isolated per layer and immune to clipboard pollution (yanks/deletes won't litter your bookmarks). QOL features include visual fringe markers, a floating hover menu, and at most two keybinds to jump to any bookmark.

### Org integration
The Org layer extends Arrow further by dynamically linking your code to living documentation. Each project automatically gets its own Org file, allowing every source file to connect back to it. Additionally, every file in a project has its own unique org note.

---

## Installation

### Using `use-package` + `package-vc-install` (Emacs 29+)

```elisp
(use-package arrow
  :vc (:fetcher "github" :repo "vmargb/arrow.el")
  :config
  (setq arrow-org-directory "~/org/arrow-notes/"))
```

### Straight
```elisp
(use-package arrow
  :straight (arrow :type git :host github :repo "vmargb/arrow.el")
  :config
  (setq arrow-org-directory "~/org/arrow-notes/"))
```

### Elpaca
Ensure you have `(elpaca-use-package-mode)`

```elisp
(use-package arrow
  :elpaca (arrow :host github :repo "vmargb/arrow.el")
  :config
  (setq arrow-org-directory "~/org/arrow-notes/"))
```


### Configuration (defaults)

```elisp
(setq arrow-persist t) ;; persists bookmark on disk
(setq arrow-auto-promote nil) ;; auto rearranges list when key added or used
(setq arrow-visual-marker t) ;; displays visual marker on line number
(setq arrow-visual-marker-position 'left) ;; marker position(left or right)
(setq arrow-project-modeline nil) ;; show modeline indicaor for arrow-project

;; Org layer settings
(setq arrow-org-window-behavior 'same-window) ;; 'same-window, 'other-window, 'other-frame
```

#### Doom-Modeline integration
Add this to your `init.el` after loading both doom-modeline & arrow:

```elisp
(with-eval-after-load 'doom-modeline
  (doom-modeline-def-segment arrow-project
    (arrow-project-modeline-string))
  (doom-modeline-add-segment 'arrow-project 'misc-info :after 'main))
```
ensure you have `(setq arrow-project-modeline t)` for this to work

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

### Org bookmarks
| Command                        | Description                              |
| ------------------------------ | ---------------------------------------- |
| `arrow-org-open-project`       | Toggle project notes ↔ source file       |
| `arrow-org-open-file`          | Toggle file-specific notes ↔ source file |
| `arrow-org-list-project-notes` | Browse all project notes                 |

**Smart return**: `arrow-org-open-project` and `open-file` remembers exactly which file you came from even across different files in the same project and restores your cursor position.


## Unified workflow (simpler)
If the above commands are too overwhelming `arrow-jump` has you covered.

| Command      | Description                     |
| ------------ | ------------------------------- |
| `arrow-jump` | Unified command for every layer |



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
(define-key arrow-mode-map (kbd "C-c o l") #'arrow-org-list-project-notes)
```

**General keybinds:**
These are my keybindings, feel free to copy them.
```elisp
;; Marks (arrow.el)
"m"  '(:ignore t :which-key "marks")
"mm" '(arrow-show         :which-key "show")
"ma" '(arrow-add          :which-key "add")
"md" '(arrow-delete       :which-key "delete")
"mc" '(arrow-clear-all    :which-key "clear all")
"mn" '(arrow-next-line    :which-key "next")
"mp" '(arrow-prev-line    :which-key "prev")
;; Project layer
"k"  '(:ignore t :which-key "project marks")
"kk" '(arrow-project-show   :which-key "show")
"ka" '(arrow-project-add    :which-key "add")
"kd" '(arrow-project-delete :which-key "delete")
"kn" '(arrow-project-next   :which-key "next")
"kp" '(arrow-project-prev   :which-key "prev")
;; Global layer
"i" '(:ignore t :which-key "global")
"ia" '(arrow-global-add    :which-key "add")
"ii" '(arrow-global-show   :which-key "show")
"id" '(arrow-global-delete :which-key "delete")
"ic" '(arrow-global-clear-all :which-key "clear all")
"in" '(arrow-global-next   :which-key "next")
"ip" '(arrow-global-prev   :which-key "prev")
;; Unified
"mj" '(arrow-jump :which-key "jump (auto)")
;; Arrow-Org
"oo" '(arrow-org-list-project-notes :which-key "org list notes")
"of" '(arrow-org-open-file          :which-key "org for this file")
"op" '(arrow-org-open-project       :which-key "org for this project")
```

## Todo

- Unified hydra-like menu that shows buffer-local + project bookmarks together