;;; arrow.el --- Buffer-local bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.0.1
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
  "Alist of file-scoped bookmarks.  Format: ((char . marker) ...).")

(defcustom arrow-project-modeline nil
  "If non-nil, display the project bookmark key in the modeline."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-project-modeline-glyph "➶ "
  "Glyph used for the modeline indicator.
icons like '󱋱 ', '󰁕 ', or simply '➶ '."
  :type 'string
  :group 'arrow)


;; Visual overlay

(defface arrow-bookmark-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face used for bookmark indicators."
  :group 'arrow)

(defvar-local arrow--overlays nil
  "Overlays used for visual bookmark indicators.")

(defun arrow--place-indicator (char marker)
  "Place a visual bookmark indicator for CHAR at MARKER."
  (when (and (marker-buffer marker)
             (eq (marker-buffer marker) (current-buffer)))
    (save-excursion
      (goto-char marker)
      (let* ((pos (line-beginning-position))
             (ov (make-overlay pos pos))
             ;; which margin to use based on user preference
             (margin-side (if (eq arrow-visual-marker-position 'right)
                              'right-margin
                            'left-margin)))
        (overlay-put ov 'before-string
                     (propertize
                      " "
                      'display
                      `((margin ,margin-side)
                        ,(propertize
                          (format "%c " char)
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


;;; Buffer-local functions

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
  "Load bookmark positions from storage."
  (when-let* ((file (arrow--storage-file))
              (data (arrow--load-data file))
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

(defun arrow--promote (char)
  "Move the bookmark for CHAR to the front of `arrow-alist`."
  (let ((entry (assoc char arrow-alist)))
    (when entry
      (setq arrow-alist (cons entry (delq entry arrow-alist)))
      (arrow--save-to-file))))

(defun arrow-promote-bookmark ()
  "Promote a bookmark in list."
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to promote"))
  (let ((char (read-char "Promote bookmark key: ")))
    (if (assoc char arrow-alist)
        (progn (arrow--promote char) (message "Promoted bookmark '%c'." char))
      (message "No bookmark found for '%c'" char))))

(defun arrow-add ()
  "Add a bookmark with keypress."
  (interactive)
  (let* ((input (read-char "Bookmark key (1-9, a-z, RET for auto): "))
         (char (if (= input ?\r)
                   (arrow--find-free-key-in arrow-alist)
                 (unless (or (and (>= input ?a) (<= input ?z))
                             (and (>= input ?0) (<= input ?9)))
                   (user-error "Please use a letter (a-z), number (1-9), or RET"))
                 input))
         (marker (point-marker)))
    (setf (alist-get char arrow-alist) marker)
    (if arrow-auto-promote (arrow--promote char) (arrow--save-to-file))
    (message "Added bookmark '%c' at line %d" char (line-number-at-pos))
    (when arrow-visual-marker
      (arrow--refresh-indicators))))

(defun arrow-delete ()
  "Delete a specific bookmark."
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to delete"))
  (let ((char (read-char "Delete bookmark key: ")))
    (if (alist-get char arrow-alist)
        (progn
          (setq arrow-alist (assq-delete-all char arrow-alist))
          (arrow--save-to-file)
          (message "Deleted bookmark '%c'" char)
          (when arrow-visual-marker
            (arrow--refresh-indicators)))
      (message "No bookmark found for '%c'" char))))

(defun arrow-clear-all ()
  "Clear all bookmarks fr a buffer."
  (interactive)
  (when (y-or-n-p "Clear all bookmarks for this file? ")
    (setq arrow-alist nil)
    (when-let ((file (arrow--storage-file)))
      (when (file-exists-p file) (delete-file file)))
    (message "Cleared all bookmarks.")
    (when arrow-visual-marker
      (arrow--clear-indicators))))

(defun arrow-jump-buffer ()
  "Jump directly to a buffer bookmark."
  (interactive)
  (unless arrow-alist
    (user-error "No buffer bookmarks"))
  (let* ((char (read-char "Buffer bookmark: "))
         (entry (assoc char arrow-alist)))
    (unless entry
      (user-error "No bookmark '%c'" char))
    (let ((marker (cdr entry)))
      (when arrow-auto-promote
        (arrow--promote char))
      (unless (marker-buffer marker)
        (user-error "Bookmark '%c' is dead" char))

      (switch-to-buffer (marker-buffer marker))
      (goto-char marker))))


(defun arrow-jump ()
  "Unified dispatcher for jumping to a buffer, project, or global bookmark."
  (interactive)
  (let* ((b-str (propertize "[b]" 'face '(:foreground "DeepSkyBlue"       :weight bold)))
         (p-str (propertize "[p]" 'face '(:foreground "Orange"            :weight bold)))
         (g-str (propertize "[g]" 'face '(:foreground "MediumSpringGreen" :weight bold)))
         (o-str (propertize "[o]" 'face '(:foreground "MediumOrchid"      :weight bold)))
         (choice (read-char-choice
                  (format "%suffer, %sroject, %slobal, %srg: " b-str p-str g-str o-str)
                  '(?b ?p ?g ?o))))
    (pcase choice
      (?b (arrow-show))
      (?p (arrow-project-show))
      (?g (arrow-global-show))
      (?o (arrow-org-list-project-notes)))))

;;; Display and Jump Logic

(defun arrow-show ()
  "Display file bookmarks in a popup and jump via single keypress.
Supports splits: C-key (horizontal), M-key (vertical)."
  (interactive)
  (when-let* ((result
               (arrow--show-popup
                "Buffer" arrow-alist
                (lambda (char marker)
                  (let* ((line (if (marker-buffer marker)
                                   (line-number-at-pos marker)
                                 "?"))
                         (raw-preview (if (marker-buffer marker)
                                          (with-current-buffer (marker-buffer marker)
                                            (save-excursion
                                              (goto-char marker)
                                              (buffer-substring
                                               (line-beginning-position)
                                               (line-end-position))))
                                        "<dead marker>"))
                         ;; Truncate the string so it fits nicely in the 75-char frame
                         (preview (truncate-string-to-width (string-trim raw-preview) 55 0 nil "…")))
                    (format " [%s] Line %-4s %s"
                            (propertize (char-to-string char)
                                        'face 'arrow-key-face)
                            line
                            preview))))))
    (let* ((selection (car result))
           (mods (cdr result))
           (key (car selection))
           (jump-marker (cdr selection)))

      (when arrow-auto-promote
        (arrow--promote key))

      (when (marker-buffer jump-marker)
        (cond
         ((memq 'control mods) (select-window (split-window-below)))
         ((memq 'shift mods)    (select-window (split-window-right))))

        (switch-to-buffer (marker-buffer jump-marker))
        (goto-char jump-marker)))))

;; --- Buffer-local cycling

(defun arrow--get-sorted-alist ()
  "Return `arrow-alist' sorted by marker position."
  (sort (copy-sequence arrow-alist)
        (lambda (a b) (< (marker-position (cdr a)) (marker-position (cdr b))))))

(defun arrow-next-line ()
  "Move to the next local bookmark in the buffer."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks"))
  (let* ((sorted (arrow--get-sorted-alist))
         (target (catch 'found
                   (dolist (bm sorted)
                     (when (> (marker-position (cdr bm)) (point))
                       (throw 'found bm)))
                   (car sorted)))) ; wrap to start if none found after point
    (goto-char (cdr target))
    (message "Local bookmark: %c" (car target))))

(defun arrow-prev-line ()
  "Move to the previous local bookmark."
  (interactive)
  (unless arrow-alist (user-error "No buffer bookmarks"))
  (let* ((sorted (reverse (arrow--get-sorted-alist)))
         (target (catch 'found
                   (dolist (bm sorted)
                     (when (< (marker-position (cdr bm)) (point))
                       (throw 'found bm)))
                   (car sorted)))) ; wrap to end if none found before point
    (goto-char (cdr target))
    (message "Local bookmark: %c" (car target))))


;;; Minor Mode

(defvar arrow-mode-map
  (make-sparse-keymap)
  "Keymap for `arrow-mode'.")

(defvar arrow-modeline-segment
  '(:eval (arrow-project-modeline-string))
  "The modeline segment for arrow.el.")

;; add to global-mode-string so it shows up in
;; standard Emacs and Doom Modeline (via the misc-info segment).
(add-to-list 'global-mode-string '("" arrow-modeline-segment) t)

;;;###autoload
(define-minor-mode arrow-mode
  "Minor mode for file-local transient bookmarks."
  :lighter " Arrow"
  :keymap arrow-mode-map
  (if arrow-mode
      (progn
        (arrow--load-from-file)
        (when arrow-visual-marker
          (if (eq arrow-visual-marker-position 'right) ;; ensure correct position
              (setq right-margin-width 1)
            (setq left-margin-width 1))
          (set-window-buffer nil (current-buffer))
          (arrow--refresh-indicators)) ;; show changes
        (add-hook 'after-save-hook #'arrow--save-to-file nil t)
        (add-hook 'kill-buffer-hook #'arrow--save-to-file nil t))
    ;; remove hooks and reset margins
    (remove-hook 'after-save-hook #'arrow--save-to-file t)
    (remove-hook 'kill-buffer-hook #'arrow--save-to-file t)
    (setq left-margin-width 0)
    (setq right-margin-width 0)
    (set-window-buffer nil (current-buffer))
    (arrow--clear-indicators)))

(defun arrow--maybe-load ()
  "Load storage if it exists, otherwise continue as normal."
  (let ((file (arrow--storage-file)))
    (when (and file (file-exists-p file))
      (unless arrow-mode (arrow-mode 1)))))

(add-hook 'find-file-hook #'arrow--maybe-load)

(require 'arrow-global)
(require 'arrow-project)
(require 'arrow-org)

(provide 'arrow)

;;; arrow.el ends here
