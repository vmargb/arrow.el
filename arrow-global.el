;;; arrow-global.el --- Global bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.0.1
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Cross-project global file bookmarks, follows the same patterns as
;; arrow-project.el and arrow.el but keyed to absolute paths, stored in a
;; fixed file.  Accessible from anywhere regardless of project context
;; Similar to M-x: bookmark-jump but adds unified workflow to arrow

;;; Code:

(require 'arrow-core)

(defgroup arrow-global nil
  "Global (cross-project) bookmarks for arrow."
  :group 'arrow)

(defcustom arrow-global-file
  (expand-file-name "global.bm" arrow-storage-dir)
  "Path to the global bookmarks file.
Each entry is an alist of (CHAR . ABSOLUTE-PATH)."
  :type 'file
  :group 'arrow-global)

(defvar arrow-global--cache nil
  "In-memory cache of global bookmarks alist.
Populated on first use and kept in sync with disk.")

(defvar arrow-global--loaded nil
  "Non-nil once the global cache has been read from disk.")

;;; helpers

(defun arrow-global--load ()
  "Return global bookmarks alist, loading from disk if needed."
  (unless arrow-global--loaded
    (setq arrow-global--cache (arrow--load-data arrow-global-file)
          arrow-global--loaded t))
  arrow-global--cache)

(defun arrow-global--save (alist)
  "Persist ALIST to disk and update cache."
  (setq arrow-global--cache alist)
  (make-directory (file-name-directory arrow-global-file) t)
  (arrow--save-data arrow-global-file alist))

;;; Commands

;;;###autoload
(defun arrow-global-add ()
  "Bookmark the current file in the global list."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Current buffer is not visiting a file"))
  (let* ((alist (arrow-global--load))
         (file-path (buffer-file-name))
         (input (read-char "Global bookmark key (1-9, a-z, RET for auto): "))
         (char (if (= input ?\r)
                   (arrow--find-free-key-in alist)
                 (unless (or (and (>= input ?a) (<= input ?z))
                             (and (>= input ?1) (<= input ?9)))
                   (user-error "Please use a letter (a-z), number (1-9), or RET"))
                 input))
         (new-alist (cons (cons char file-path)
                          (assq-delete-all char alist))))
    (arrow-global--save new-alist)
    (message "Added global bookmark '%c' for %s"
             char (abbreviate-file-name file-path))))

;;;###autoload
(defun arrow-global-delete ()
  "Remove a global bookmark by key."
  (interactive)
  (let ((alist (arrow-global--load)))
    (unless alist (user-error "No global bookmarks to delete"))
    (let ((char (read-char "Delete global bookmark key: ")))
      (if (alist-get char alist)
          (progn
            (arrow-global--save (assq-delete-all char alist))
            (message "Deleted global bookmark '%c'" char))
        (message "No global bookmark found for '%c'" char)))))

;;;###autoload
(defun arrow-global-clear-all ()
  "Delete all global bookmarks after confirmation."
  (interactive)
  (when (y-or-n-p "Clear all global bookmarks? ")
    (arrow-global--save nil)
    (message "Cleared all global bookmarks.")))

;;;###autoload
(defun arrow-jump-global ()
  "Jump directly to a global bookmark without a popup."
  (interactive)
  (let* ((alist (arrow-global--load)))
    (unless alist (user-error "No global bookmarks"))
    (let* ((char (read-char "Global bookmark: "))
           (entry (assoc char alist)))
      (unless entry
        (user-error "No global bookmark '%c'" char))
      (let ((path (cdr entry)))
        (unless (file-exists-p path)
          (user-error "Global bookmark '%c' points to missing file: %s"
                      char (abbreviate-file-name path)))
        (find-file path)))))

;;;###autoload
(defun arrow-global-show ()
  "Show global bookmarks popup and jump via single keypress.
Supports splits: C-key (horizontal split), S-key (vertical split)."
  (interactive)
  (let ((alist (arrow-global--load)))
    (when-let* ((result
                 (arrow--show-popup
                  "Global"
                  alist
                  (lambda (char path)
                    (let* ((exists (file-exists-p path))
                           (label  (abbreviate-file-name path))
                           ;; truncate to fit the 75-char popup frame
                           (label  (truncate-string-to-width label 60 0 nil "…"))
                           (label  (if exists label
                                     (propertize label 'face 'shadow))))
                      (format " [%s] %s"
                              (propertize (char-to-string char)
                                          'face 'arrow-key-face)
                              label))))))
      (let* ((selection (car result))
             (mods      (cdr result))
             (path      (cdr selection)))
        (unless (file-exists-p path)
          (user-error "Global bookmark points to missing file: %s"
                      (abbreviate-file-name path)))
        (cond
         ((memq 'control mods)
          (select-window (split-window-below))
          (find-file path))
         ((memq 'shift mods)
          (select-window (split-window-right))
          (find-file path))
         (t
          (find-file path)))))))

;;; Cycling

(defun arrow-global--cycle (direction)
  "Cycle through global bookmarks.  DIRECTION is 1 (next) or -1 (prev)."
  (let* ((alist (arrow-global--load))
         (len (length alist))
         (current-file (buffer-file-name))
         (current-idx nil)
         (counter 0))
    (unless alist (user-error "No global bookmarks"))
    (when current-file
      (dolist (item alist)
        (when (string= (cdr item) current-file)
          (setq current-idx counter))
        (setq counter (1+ counter))))
    (let* ((new-idx (if current-idx
                        (mod (+ current-idx direction) len)
                      0))
           (target (nth new-idx alist))
           (path (cdr target)))
      (unless (file-exists-p path)
        (user-error "Global bookmark '%c' points to missing file: %s"
                    (car target) (abbreviate-file-name path)))
      (find-file path)
      (message "Global [%c]: %s" (car target) (abbreviate-file-name path)))))

;;;###autoload
(defun arrow-global-next ()
  "Jump to the next global bookmark."
  (interactive)
  (arrow-global--cycle 1))

;;;###autoload
(defun arrow-global-prev ()
  "Jump to the previous global bookmark."
  (interactive)
  (arrow-global--cycle -1))

(provide 'arrow-global)

;;; arrow-global.el ends here
