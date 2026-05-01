;;; arrow.el --- Buffer-local bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.0
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

(defgroup arrow nil
  "File-local bookmarks with transient popups."
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

(defcustom arrow-project-modeline-glyph "➶ "
  "Glyph used for the modeline indicator.  '󱋱 ', '󰁕 ', '➶ '."
  :type 'string
  :group 'arrow)

(defcustom arrow-preview-context 0
  "Number of context lines shown above and below each bookmark in the popup.
Set to 0 (default) for the classic single-line preview."
  :type 'natnum
  :group 'arrow)


;; Visual overlay

(defface arrow-bookmark-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face used for bookmark indicators."
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
             (ov          (make-overlay pos pos))
             (margin-side (if (eq arrow-visual-marker-position 'right)
                              'right-margin
                            'left-margin)))
        (overlay-put ov 'before-string
                     (propertize
                      " "
                      'display
                      `((margin ,margin-side)
                        ,(propertize
                          (format "%s " key)
                          'face 'arrow-bookmark-face))))
        (push ov arrow--overlays)))))

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

(defun arrow-jump ()
  "Unified dispatcher for jumping to a buffer, project, or global bookmark."
  (interactive)
  (let* ((b-str (propertize "[b]" 'face '(:inherit font-lock-keyword-face :weight bold)))
         (p-str (propertize "[p]" 'face '(:inherit font-lock-type-face     :weight bold)))
         (g-str (propertize "[g]" 'face '(:inherit success                 :weight bold)))
         (o-str (propertize "[o]" 'face '(:inherit warning                 :weight bold)))
         (choice (read-char-choice
                  (format "%suffer, %sroject, %slobal, %srg: "
                          b-str p-str g-str o-str)
                  '(?b ?p ?g ?o))))
    (pcase choice
      (?b (arrow-show))
      (?p (arrow-project-show))
      (?g (arrow-global-show))
      (?o (arrow-org-list-project-notes)))))


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

(defun arrow-show ()
  "Display buffer-local bookmarks in a popup and jump with keypress.
Window splits with C-key (horizontal), S-key / uppercase (vertical).
Context lines per entry controlled by `arrow-preview-context'."
  (interactive)
  (when-let* ((result
               (arrow--show-popup
                "Buffer" arrow-alist #'arrow--format-bookmark-entry)))
    (let* ((selection   (car result))
           (mods        (cdr result))
           (key         (car selection))
           (jump-marker (cdr selection)))

      (when arrow-auto-promote
        (arrow--promote key))

      (when (marker-buffer jump-marker)
        (cond
         ((memq 'control mods) (select-window (split-window-below)))
         ((memq 'shift   mods) (select-window (split-window-right))))

        (switch-to-buffer (marker-buffer jump-marker))
        (goto-char jump-marker)))))


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
