;;; arrow.el --- Buffer-local bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.1
;; Package-Requires: ((emacs "28.1"))
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; An implementation of arrow.nvim in Emacs.  A harpoon-like bookmarking system that
;; uses a floating menu with mnemonic keypresses to jump to marks quickly without
;; typing with visual hints.

;;; Code:

(require 'subr-x)
(require 'arrow-core)
(require 'arrow-global)
(require 'arrow-project)
(require 'arrow-org)

;; silence byte-compiler if nerd-icons isn't loaded at compile time
(declare-function nerd-icons-mdicon "nerd-icons" (icon &rest args))

(defgroup arrow nil
  "File-local bookmarks with transient-like popups."
  :group 'convenience)

;; custom options:

(defcustom arrow-persist t
  "If non-nil, save bookmarks to a storage file automatically."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-auto-promote nil
  "If non-nil, automatically move bookmarks to the top of the list when jumping."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-auto-sort nil
  "If non-nil, keep line bookmarks sorted by line number after every insertion."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-visual-marker t
  "If non-nil, displays fringe marker with the keybinding on the same line."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-visual-marker-position 'left
  "Position for the fringe marker.  Can be left or right."
  :type '(choice
          (const :tag "Left fringe" left)
          (const :tag "Right fringe" right))
  :group 'arrow)

(defvar-local arrow-alist nil
  "Alist of file-scoped bookmarks.  Format: ((string-key . marker) ...).")

(defcustom arrow-project-modeline nil
  "If non-nil, display the project bookmark key in the modeline."
  :type 'boolean
  :group 'arrow)

;; --------------------------------------------------------------
;; Nerd-Icons Modeline Integration
;; --------------------------------------------------------------
(defcustom arrow-modeline-use-nerd-icons t
  "If non-nil, use `nerd-icons' for the modeline indicator."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-modeline-nerd-icon-family "mdicon"
  "Nerd-icon family to use for the modeline glyph."
  :type 'string
  :group 'arrow)

(defcustom arrow-modeline-nerd-icon-name "nf-md-bow_arrow"
  "Nerd Icons glyph name for the modeline indicator.
\"nf-md-bow_arrow\"
\"nf-md-crossbow\"
\"nf-md-arrow_right_bold\"
\"nf-cod-arrow_right\"
\"nf-fa-bullseye\""
  :type 'string
  :group 'arrow)

(defun arrow--modeline-glyph ()
  "Return the modeline glyph, using `nerd-icons' if available and enabled.
Otherwise fallback to available glyphs."
  (if (and arrow-modeline-use-nerd-icons
           (featurep 'nerd-icons))
      (let ((icon-fn (intern (format "nerd-icons-%s" arrow-modeline-nerd-icon-family))))
        (if (fboundp icon-fn)
            (concat (funcall icon-fn arrow-modeline-nerd-icon-name :face 'arrow-bookmark-face) " ")
          "➶ "))
    "➶ "))

(defcustom arrow-preview-context 0
  "Number of context lines shown above and below each bookmark in the popup.
Set to 0 (default) for the classic single-line preview."
  :type 'natnum
  :group 'arrow)

;; Visual overlay

(defface arrow-bookmark-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face used for the margin glyph."
  :group 'arrow)

(defface arrow-bookmark-key-face
  '((t (:inherit line-number
        :height 0.85
        :slant normal
        :weight normal)))
  "Face used for the end-of-line key label.
Inherits from `line-number' since line numbers are a distinct hue from
comments in most themes, which is what actually separates it visually."
  :group 'arrow)

(defcustom arrow-visual-marker-glyph "▶"
  "Fixed-width glyph shown in the margin to flag a bookmarked line."
  :type 'string
  :group 'arrow)

(defvar-local arrow--overlays nil
  "Overlays used for visual bookmark indicators.")

(defun arrow--place-indicator (key marker)
  "Place a visual bookmark indicator for string KEY at MARKER."
  (when (and (marker-buffer marker)
             (eq (marker-buffer marker) (current-buffer)))
    (save-excursion
      (goto-char marker)
      (let* ((pos         (line-beginning-position))
             (eol         (line-end-position))
             (margin-side (if (eq arrow-visual-marker-position 'right)
                              'right-margin
                            'left-margin))
             (glyph-ov    (make-overlay pos pos))
             (key-ov      (make-overlay eol eol)))
        ;; fixed margin glyph just flags "bookmark is here"
        ;; so width never has to change no matter how long KEY is
        (overlay-put glyph-ov 'before-string
                     (propertize
                      " "
                      'display
                      `((margin ,margin-side)
                        ,(propertize arrow-visual-marker-glyph
                                     'face 'arrow-bookmark-face
                                     'help-echo (format "arrow: %s" key)))))
        ;; full key label at end-of-line, scales to any key length, costs no margin space
        (overlay-put key-ov 'after-string
                     (concat (propertize " " 'face 'default)
                             (propertize (format "[%s]" key)
                                         'face 'arrow-bookmark-key-face
                                         'display '(raise 0.15))))
        (push glyph-ov arrow--overlays)
        (push key-ov arrow--overlays)))))

(defun arrow--clear-indicators ()
  "Remove all bookmark indicators."
  (mapc #'delete-overlay arrow--overlays)
  (setq arrow--overlays nil))

(defun arrow--refresh-indicators ()
  "Recreate bookmark indicators."
  (arrow--clear-indicators)
  (dolist (entry arrow-alist)
    (arrow--place-indicator (car entry) (cdr entry))))

;;; buffer-local persistence

(defun arrow--save-to-file ()
  "Save markers as positions."
  (when-let* ((file (arrow--storage-file))
              (data (delq nil
                          (mapcar (lambda (x)
                                    (let ((pos (marker-position (cdr x))))
                                      (when pos (cons (car x) pos))))
                                  arrow-alist))))
    (arrow--save-data file data)))

(defun arrow--load-from-file ()
  "Load bookmark positions from storage.
`arrow--load-data' handles migration of legacy character keys to new strings."
  (when-let* ((file          (arrow--storage-file))
              (data          (arrow--load-data file))
              ((listp data))
              (target-buffer (current-buffer)))
    (setq arrow-alist nil)
    (dolist (item data)
      (when (and (consp item) (numberp (cdr item)))
        (let ((marker (make-marker)))
          (set-marker marker (cdr item) target-buffer)
          (push (cons (car item) marker) arrow-alist))))
    (when arrow-visual-marker
      (arrow--refresh-indicators))))

;;; promote / sort

(defun arrow--promote (key)
  "Move the bookmark for KEY to the front of `arrow-alist'."
  (let ((entry (assoc key arrow-alist)))
    (when entry
      (setq arrow-alist (cons entry (assoc-delete-all key arrow-alist)))
      (arrow--save-to-file))))

(defun arrow-promote-bookmark ()
  "Promote a bookmark to the top of the list."
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to promote"))
  (let ((key (arrow--read-existing-key "Promote bookmark key: " arrow-alist)))
    (arrow--promote key)
    (message "Promoted bookmark [%s]." key)))

;;; Sorting

(defun arrow--sort-by-position ()
  "Sort `arrow-alist' in place by ascending marker position and save."
  (setq arrow-alist
        (sort (copy-sequence arrow-alist)
              (lambda (a b)
                (< (or (marker-position (cdr a)) 0)
                   (or (marker-position (cdr b)) 0)))))
  (arrow--save-to-file))

(defun arrow-sort-bookmarks ()
  "Sort all buffer bookmarks by their line number.
Useful as a manual one-shot command when `arrow-auto-sort' is disabled."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks to sort"))
  (arrow--sort-by-position)
  (when arrow-visual-marker (arrow--refresh-indicators))
  (message "Buffer bookmarks sorted by line number."))

;;; add / delete / jump

(defun arrow-add ()
  "Add a bookmark at point with a 1 or 2 character key.
Press a letter or digit as the first character.  Then either press RET
to confirm a single-character key or press a second letter/digit to form
a 2-character key.  On the first prompt RET auto-assigns the next free key."
  (interactive)
  (let* ((raw-key (arrow--read-bookmark-key "Bookmark key" t))
         (key     (or raw-key (arrow--find-free-key-in arrow-alist))))
    ;; conflict check, skip if we are simply overwriting the same key
    (unless (assoc key arrow-alist)
      (when-let ((conflict (arrow--key-conflicts-p key arrow-alist)))
        (user-error "Key conflict: [%s] is blocked by existing key [%s]"
                    key conflict)))
    (let ((marker (point-marker)))
      ;; upsertm remove old entry for this key then push the new one
      (setq arrow-alist (assoc-delete-all key arrow-alist))
      (push (cons key marker) arrow-alist)
      (cond
       (arrow-auto-sort    (arrow--sort-by-position))
       (arrow-auto-promote (arrow--promote key))
       (t                  (arrow--save-to-file)))
      (message "Added bookmark [%s] at line %d" key (line-number-at-pos))
      (when arrow-visual-marker
        (arrow--refresh-indicators)))))

(defun arrow-delete ()
  "Delete a bookmark from the list by key."
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to delete"))
  (let ((key (arrow--read-existing-key "Delete bookmark key: " arrow-alist)))
    (setq arrow-alist (assoc-delete-all key arrow-alist))
    (arrow--save-to-file)
    (message "Deleted bookmark [%s]" key)
    (when arrow-visual-marker
      (arrow--refresh-indicators))))

(defun arrow-clear-all ()
  "Clear all buffer-local bookmarks for the current buffer."
  (interactive)
  (when (y-or-n-p "Clear all bookmarks for this file? ")
    (setq arrow-alist nil)
    (when-let ((file (arrow--storage-file)))
      (when (file-exists-p file) (delete-file file)))
    (message "Cleared all bookmarks.")
    (when arrow-visual-marker
      (arrow--clear-indicators))))

(defun arrow-jump-buffer ()
  "Jump directly to a buffer bookmark without popup."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks"))
  (let* ((key   (arrow--read-existing-key "Buffer bookmark: " arrow-alist))
         (entry (assoc key arrow-alist)))
    (unless entry (user-error "No bookmark [%s]" key))
    (let ((marker (cdr entry)))
      (when arrow-auto-promote (arrow--promote key))
      (unless (marker-buffer marker)
        (user-error "Bookmark [%s] is dead" key))
      (switch-to-buffer (marker-buffer marker))
      (goto-char marker))))

;;; reorder

(defun arrow-reorder ()
  "Interactively reorder buffer bookmarks.
First select the bookmark to move, then select which bookmark to insert
it before (same key = move to end)."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks to reorder"))
  (when-let* ((source-key (arrow--show-reorder-popup
                           "Buffer – Reorder" arrow-alist
                           #'arrow--format-bookmark-entry nil))
              (target-key (arrow--show-reorder-popup
                           "Buffer – Reorder" arrow-alist
                           #'arrow--format-bookmark-entry source-key)))
    (setq arrow-alist (arrow--reorder-alist arrow-alist source-key target-key))
    (arrow--save-to-file)
    (when arrow-visual-marker (arrow--refresh-indicators))
    (message "Moved bookmark [%s]." source-key)))

;;; unified dispatcher

(defun arrow-show-all ()
  "Unified popup with Buffer, Project, and Global bookmarks together.
keys behave exactly as they do in that layers own `-show' command
Sections with no bookmarks (e.g. project when not inside a project) are omitted."
  (interactive)
  (let* ((root       (ignore-errors (arrow-project--root)))
         (proj-alist (and root (arrow-project--load root)))
         (glob-alist (arrow-global--load))
         (org-alist  (and root (arrow-org--notes-alist root)))
         (sections
          (delq nil
                (list
                 (when arrow-alist
                   (list :title     "Buffer"
                         :alist     arrow-alist
                         :format-fn #'arrow--format-bookmark-entry
                         :jump-fn   #'arrow--jump-to-buffer-entry))
                 (when proj-alist
                   (list :title     "Project"
                         :alist     proj-alist
                         :format-fn #'arrow-project--format-entry
                         :jump-fn   (lambda (key path mods)
                                      (arrow-project--jump-to-entry
                                       root proj-alist key path mods))))
                 (when glob-alist
                   (list :title     "Global"
                         :alist     glob-alist
                         :format-fn #'arrow-global--format-entry
                         :jump-fn   (lambda (_key path mods)
                                      (arrow-global--jump-to-entry path mods))))
                 (when org-alist
                   (list :title     "Org"
                         :alist     org-alist
                         :format-fn #'arrow-org--format-entry
                         :jump-fn   (lambda (_key path mods)
                                      (arrow-org--jump-to-entry path mods))))))))
    (unless sections (user-error "No bookmarks in any layer"))
    (when-let* ((result (arrow--show-multi-popup sections)))
      (let* ((section   (plist-get result :section))
             (selection (plist-get result :selection))
             (mods      (plist-get result :mods))
             (jump-fn   (plist-get section :jump-fn)))
        (funcall jump-fn (car selection) (cdr selection) mods)))))

;;; display and jump logic

(defun arrow--get-context-line (n)
  "Return trimmed text of line N relative to point (0 = current line).
Clamps to buffer boundaries and returns an empty string for out-of-range."
  (save-excursion
    (forward-line n)
    (string-trim
     (buffer-substring (line-beginning-position) (line-end-position)))))

(defun arrow--format-bookmark-entry (key marker)
  "Format a single bookmark entry for the popup.
KEY is a string, MARKER is a buffer marker.
When `arrow-preview-context' is 0, return one line.
When it is N > 0 then N lines before and N lines after."
  (if (not (marker-buffer marker))
      (format " [%s] <dead marker>"
              (propertize key 'face 'arrow-key-face))
    (let* ((ctx  arrow-preview-context)
           (line (line-number-at-pos marker)))
      (if (zerop ctx)
          ;; single-line format
          (let* ((raw     (with-current-buffer (marker-buffer marker)
                            (save-excursion
                              (goto-char marker)
                              (buffer-substring (line-beginning-position)
                                                (line-end-position)))))
                 (preview (truncate-string-to-width (string-trim raw) 55 0 nil "…")))
            (format " [%s] Line %-4s %s"
                    (propertize key 'face 'arrow-key-face)
                    line preview))

        ;; multi-line format
        (with-current-buffer (marker-buffer marker)
          (save-excursion
            (goto-char marker)
            (let* ((key-str (propertize key 'face 'arrow-key-face))
                   (header  (format " [%s] Line %d" key-str line))
                   ;; lines before the bookmark
                   (before  (let (acc)
                               (dotimes (i ctx)
                                 (let* ((offset (- (- ctx i)))
                                        (txt    (arrow--get-context-line offset))
                                        (trunc  (truncate-string-to-width txt 62 0 nil "…")))
                                   (push (concat "      " trunc) acc)))
                               (nreverse acc)))
                   (bm-txt  (arrow--get-context-line 0))
                   (bm-line (concat "   ▶ "
                                    (propertize
                                     (truncate-string-to-width bm-txt 62 0 nil "…")
                                     'face 'bold)))
                   (after   (let (acc)
                               (dotimes (i ctx)
                                 (let* ((offset (1+ i))
                                        (txt    (arrow--get-context-line offset))
                                        (trunc  (truncate-string-to-width txt 62 0 nil "…")))
                                   (push (concat "      " trunc) acc)))
                               (nreverse acc)))
                   (parts   (append (list header) before (list bm-line) after (list ""))))
              (string-join parts "\n"))))))))

(defun arrow--jump-to-buffer-entry (key marker mods)
  "Generic jump to buffer bookmark KEY/MARKER, honoring split MODS.
Promotes KEY when `arrow-auto-promote' is set.  Mirrors the existing
behaviour of `arrow-show'"
  (when arrow-auto-promote
    (arrow--promote key))
  (when (marker-buffer marker)
    (cond
     ((memq 'control mods) (select-window (split-window-below)))
     ((memq 'shift   mods) (select-window (split-window-right))))
    (switch-to-buffer (marker-buffer marker))
    (goto-char marker)))

(defun arrow-show ()
  "Display buffer-local bookmarks in a popup and jump with keypress.
Window splits with C-key (horizontal), S-key / uppercase (vertical).
Context lines per entry controlled by `arrow-preview-context'."
  (interactive)
  (when-let* ((result
               (arrow--show-popup
                "Buffer" arrow-alist #'arrow--format-bookmark-entry)))
    (let* ((selection (car result))
           (mods      (cdr result)))
      (arrow--jump-to-buffer-entry (car selection) (cdr selection) mods))))

;;; buffer-local cycling

(defun arrow--get-sorted-alist ()
  "Return `arrow-alist' sorted by marker position."
  (sort (copy-sequence arrow-alist)
        (lambda (a b) (< (marker-position (cdr a)) (marker-position (cdr b))))))

(defun arrow-next-line ()
  "Move to the next buffer bookmark in the buffer."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks"))
  (let* ((sorted (arrow--get-sorted-alist))
         (target (catch 'found
                   (dolist (bm sorted)
                     (when (> (marker-position (cdr bm)) (point))
                       (throw 'found bm)))
                   (car sorted))))  ; wrap to start
    (goto-char (cdr target))
    (message "Local bookmark: [%s]" (car target))))

(defun arrow-prev-line ()
  "Move to the previous buffer bookmark."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks"))
  (let* ((sorted (reverse (arrow--get-sorted-alist)))
         (target (catch 'found
                   (dolist (bm sorted)
                     (when (< (marker-position (cdr bm)) (point))
                       (throw 'found bm)))
                   (car sorted))))  ; wrap to end
    (goto-char (cdr target))
    (message "Local bookmark: [%s]" (car target))))

;;; minor mode

(defvar arrow-mode-map
  (make-sparse-keymap)
  "Keymap for `arrow-mode'.")

(defvar arrow-modeline-segment
  '(:eval (arrow-project-modeline-string))
  "The modeline segment for arrow.el.")

;;;###autoload
(define-minor-mode arrow-mode
  "Minor mode for buffer-local bookmarks."
  :lighter " Arrow"
  :keymap arrow-mode-map
  (if arrow-mode
      (progn
        (add-to-list 'global-mode-string '("" arrow-modeline-segment) t)
        (arrow--load-from-file)
        (when arrow-visual-marker
          (if (eq arrow-visual-marker-position 'right)
              (setq right-margin-width 1)
            (setq left-margin-width 1))
          (set-window-buffer nil (current-buffer))
          (arrow--refresh-indicators))
        (add-hook 'after-save-hook #'arrow--save-to-file nil t)
        (add-hook 'kill-buffer-hook #'arrow--save-to-file nil t))
    (remove-hook 'after-save-hook #'arrow--save-to-file t)
    (remove-hook 'kill-buffer-hook #'arrow--save-to-file t)
    (setq left-margin-width  0)
    (setq right-margin-width 0)
    (set-window-buffer nil (current-buffer))
    (arrow--clear-indicators)))

(defun arrow--maybe-load ()
  "Load storage if it exists, otherwise continue as normal."
  (let ((file (arrow--storage-file)))
    (when (and file (file-exists-p file))
      (unless arrow-mode (arrow-mode 1)))))

;;;###autoload
(define-minor-mode arrow-auto-mode
  "Global minor mode that auto-enables `arrow-mode' in bookmarked files.
Watches `find-file-hook' and activates `arrow-mode' whenever a file
has stored Arrow bookmarks on disk."
  :global t
  :group 'arrow
  (if arrow-auto-mode
      (add-hook 'find-file-hook #'arrow--maybe-load)
    (remove-hook 'find-file-hook #'arrow--maybe-load)))

(provide 'arrow)

;;; arrow.el ends here
