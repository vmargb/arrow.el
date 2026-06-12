;;; arrow-global.el --- Global bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.0
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Cross-project global file bookmarks, follows the same patterns as
;; arrow-project.el and arrow.el but keyed to absolute paths.
;; These marks are accessible from anywhere regardless of context.
;; Similar to M-x bookmark-jump but adds a *unified* workflow to arrow.
;;
;; Keys are strings in arrow-core.el
;; Legacy bookmark files that used integer character codes are migrated
;; automatically on first load via `arrow--load-data'.

;;; Code:

(defgroup arrow-global nil
  "Global (cross-project) bookmarks for arrow."
  :group 'arrow)

(defcustom arrow-global-file
  (expand-file-name "global.bm" arrow-storage-dir)
  "Path to the global bookmarks file.
Each entry is an alist of (STRING-KEY . ABSOLUTE-PATH)."
  :type 'file
  :group 'arrow-global)

(defvar arrow-global--cache nil
  "In-memory cache of global bookmarks alist.
Populated on first use and kept in sync with disk.")

(defvar arrow-global--loaded nil
  "Non-nil once the global cache has been read from disk.")


;;; helpers

(defun arrow-global--load ()
  "Return global bookmarks alist, loading from disk if needed.
`arrow--load-data' handles migration of legacy character keys to strings."
  (unless arrow-global--loaded
    (setq arrow-global--cache  (arrow--load-data arrow-global-file)
          arrow-global--loaded t))
  arrow-global--cache)

(defun arrow-global--save (alist)
  "Persist ALIST to disk and update the in-memory cache."
  (setq arrow-global--cache alist)
  (make-directory (file-name-directory arrow-global-file) t)
  (arrow--save-data arrow-global-file alist))


;;; commands

;;;###autoload
(defun arrow-global-add ()
  "Bookmark the current file in the global list.
Press a letter or digit as the first key character.  Then press RET to
confirm a single-character key, or press a second letter/digit to create a
2-character key.  At the first prompt, RET auto-assigns the next free key."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Current buffer is not visiting a file"))
  (let* ((alist     (arrow-global--load))
         (file-path (buffer-file-name))
         (raw-key   (arrow--read-bookmark-key "Global bookmark key" t))
         (key       (or raw-key (arrow--find-free-key-in alist))))
    ;; conflict check, skip when overwriting the same key
    (unless (assoc key alist)
      (when-let ((conflict (arrow--key-conflicts-p key alist)))
        (user-error "Key conflict: [%s] is blocked by existing key [%s]"
                    key conflict)))
    (let ((new-alist (cons (cons key file-path)
                           (assoc-delete-all key alist))))
      (arrow-global--save new-alist)
      (message "Added global bookmark [%s] for %s"
               key (abbreviate-file-name file-path)))))

;;;###autoload
(defun arrow-global-delete ()
  "Remove a global bookmark by key."
  (interactive)
  (let ((alist (arrow-global--load)))
    (unless alist (user-error "No global bookmarks to delete"))
    (let ((key (arrow--read-existing-key "Delete global bookmark key: " alist)))
      (arrow-global--save (assoc-delete-all key alist))
      (message "Deleted global bookmark [%s]" key))))

;;;###autoload
(defun arrow-global-clear-all ()
  "Clear all global bookmarks after confirmation."
  (interactive)
  (when (y-or-n-p "Clear all global bookmarks? ")
    (setq arrow-global--cache nil)
    (when (file-exists-p arrow-global-file)
      (delete-file arrow-global-file))
    (message "Cleared all global bookmarks.")))

;;;###autoload
(defun arrow-global-jump ()
  "Jump directly to a global bookmark without a popup."
  (interactive)
  (let* ((alist (arrow-global--load)))
    (unless alist (user-error "No global bookmarks"))
    (let* ((key   (arrow--read-existing-key "Global bookmark: " alist))
           (entry (assoc key alist)))
      (unless entry
        (user-error "No global bookmark [%s]" key))
      (let ((path (cdr entry)))
        (unless (file-exists-p path)
          (user-error "Global bookmark [%s] points to missing file: %s"
                      key (abbreviate-file-name path)))
        (find-file path)))))

;;;###autoload
(defun arrow-global-show ()
  "Show global bookmarks popup and jump via keypress.
Window splits: C-key (horizontal split), S-key / uppercase (vertical split)."
  (interactive)
  (let ((alist (arrow-global--load)))
    (when-let* ((result
                 (arrow--show-popup
                  "Global"
                  alist
                  (lambda (key path)
                    (let* ((exists (file-exists-p path))
                           (label  (abbreviate-file-name path))
                           ;; truncate to fit the 75-char popup frame
                           (label  (truncate-string-to-width label 60 0 nil "…"))
                           (label  (if exists label
                                     (propertize label 'face 'shadow))))
                      (format " [%s] %s"
                              (propertize key 'face 'arrow-key-face)
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

;;;###autoload
(defun arrow-global-reorder ()
  "Interactively reorder global bookmarks.
Select the bookmark to move, then select which bookmark to insert it before
\(same key = move to end)."
  (interactive)
  (let* ((alist (arrow-global--load))
         (fmt   (lambda (key path)
                  (let* ((label (abbreviate-file-name path))
                         (label (truncate-string-to-width label 60 0 nil "…")))
                    (format " [%s] %s"
                            (propertize key 'face 'arrow-key-face)
                            label)))))
    (unless alist (user-error "No global bookmarks to reorder"))
    (when-let* ((source-key (arrow--show-reorder-popup "Global: Reorder" alist fmt nil))
                (target-key (arrow--show-reorder-popup "Global: Reorder" alist fmt source-key)))
      (arrow-global--save (arrow--reorder-alist alist source-key target-key))
      (message "Moved global bookmark [%s]." source-key))))


;;; cycling

(defun arrow-global--cycle (direction)
  "Cycle through global bookmarks.  DIRECTION is 1 (next) or -1 (prev)."
  (let* ((alist        (arrow-global--load))
         (len          (length alist))
         (current-file (buffer-file-name))
         (current-idx  nil)
         (counter      0))
    (unless alist (user-error "No global bookmarks"))
    (when current-file
      (dolist (item alist)
        (when (string= (cdr item) current-file)
          (setq current-idx counter))
        (setq counter (1+ counter))))
    (let* ((new-idx (if current-idx (mod (+ current-idx direction) len) 0))
           (target  (nth new-idx alist))
           (path    (cdr target)))
      (unless (file-exists-p path)
        (user-error "Global bookmark [%s] points to missing file: %s"
                    (car target) (abbreviate-file-name path)))
      (find-file path)
      (message "Global [%s]: %s" (car target) (abbreviate-file-name path)))))

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
