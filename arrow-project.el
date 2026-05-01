;;; arrow-project.el --- Project-local bookmarks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.0
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Project local implementation with identical functionality to arrow.el
;; but for files isolated within a project/git repo

;;; Code:

(require 'project)

;; forward declarations
(defvar arrow-auto-promote)
(defvar arrow-project-modeline)
(defvar arrow-project-modeline-glyph)

(defvar arrow-project-cache (make-hash-table :test 'equal)
  "Cache for project bookmarks to avoid constant disk IO.  Keyed by project root.")

(defvar-local arrow-project--cached-root 'unset
  "Cached project root for the current buffer.")

(defvar-local arrow-project--modeline-cache nil
  "Cons of (alist . string) caching the last modeline result.")

(defun arrow-project--root ()
  "Return project root if found."
  (if-let ((proj (project-current)))
      (project-root proj)
    (user-error "Not currently in a project (via project.el)")))

(defun arrow-project--get-root ()
  "Return the project root for the current buffer, cached buffer-locally.
Returns nil when the buffer is not inside a project."
  (when (eq arrow-project--cached-root 'unset)
    (setq arrow-project--cached-root
          (when-let ((proj (project-current)))
            (project-root proj))))
  arrow-project--cached-root)

(defun arrow-project--file (root)
  "Get storage file for project ROOT."
  (arrow--get-storage-path root))

(defun arrow-project--load (root)
  "Load bookmark alist for project ROOT.
`arrow--load-data' handles migration of legacy character keys to strings."
  (or (gethash root arrow-project-cache)
      (let* ((file (arrow-project--file root))
             (data (arrow--load-data file)))
        (puthash root data arrow-project-cache)
        data)))

(defun arrow-project--save (root alist)
  "Save project ALIST for project ROOT to cache and disk."
  (puthash root alist arrow-project-cache)
  (arrow--save-data (arrow-project--file root) alist))


;;; commands

;;;###autoload
(defun arrow-project-add ()
  "Add the current file to the project bookmark list.
Press a letter or digit as the first key character.  Then either press
RET to confirm a 1-char key, or a second letter/digit for a 2-char key."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Current buffer is not visiting a file"))
  (let* ((root      (arrow-project--root))
         (alist     (or (arrow-project--load root) nil))
         (file-path (file-relative-name (buffer-file-name) root))
         (raw-key   (arrow--read-bookmark-key "Project bookmark key" t))
         (key       (or raw-key (arrow--find-free-key-in alist))))
    ;; conflict check
    (unless (assoc key alist)
      (when-let ((conflict (arrow--key-conflicts-p key alist)))
        (user-error "Key conflict: [%s] is blocked by existing key [%s]"
                    key conflict)))
    (setq alist (cons (cons key file-path)
                      (assoc-delete-all key alist)))
    ;; auto-promote, entry is already at the front
    (when arrow-auto-promote
      (setq alist (cons (assoc key alist)
                        (assoc-delete-all key alist))))
    (arrow-project--save root alist)
    (message "Added project bookmark [%s] for %s" key file-path)))

;;;###autoload
(defun arrow-project-delete ()
  "Delete a file from the project bookmark list."
  (interactive)
  (let* ((root  (arrow-project--root))
         (alist (arrow-project--load root)))
    (unless alist (user-error "No project bookmarks to delete"))
    (let ((key (arrow--read-existing-key "Delete project bookmark key: " alist)))
      (setq alist (assoc-delete-all key alist))
      (arrow-project--save root alist)
      (message "Deleted project bookmark [%s]" key))))

;;;###autoload
(defun arrow-project-jump ()
  "Jump directly to a project bookmark without a menu."
  (interactive)
  (let* ((root  (arrow-project--root))
         (alist (arrow-project--load root)))
    (unless alist (user-error "No project bookmarks"))
    (let* ((key   (arrow--read-existing-key "Project bookmark: " alist))
           (entry (assoc key alist)))
      (unless entry (user-error "No project bookmark [%s]" key))
      (let ((path (cdr entry)))
        (when arrow-auto-promote
          (arrow-project--save root
                               (cons entry (assoc-delete-all key alist))))
        (find-file (expand-file-name path root))))))

;;;###autoload
(defun arrow-project-show ()
  "Show project bookmarks.  Window splits C-key (horizontal), S-key (vertical)."
  (interactive)
  (let* ((root      (arrow-project--root))
         (alist     (or (arrow-project--load root) nil))
         (proj-name (file-name-nondirectory (directory-file-name root))))
    (when-let* ((result
                 (arrow--show-popup
                  (format "Project (%s)" proj-name)
                  alist
                  (lambda (key path)
                    (format " [%s] %s"
                            (propertize key 'face 'arrow-key-face)
                            path)))))
      (let* ((selection (car result))
             (mods      (cdr result))
             (key       (car selection))
             (path      (cdr selection))
             (full-path (expand-file-name path root)))

        (when arrow-auto-promote
          (arrow-project--save root
                               (cons (assoc key alist)
                                     (assoc-delete-all key alist))))
        (cond
         ((memq 'control mods)   ; horizontal split
          (select-window (split-window-below))
          (find-file full-path))
         ((memq 'shift mods)     ; vertical split
          (select-window (split-window-right))
          (find-file full-path))
         (t                      ; normal open
          (find-file full-path)))))))

;;;###autoload
(defun arrow-project-reorder ()
  "Interactively reorder project bookmarks.
Select the bookmark to move, then select which bookmark to insert it before
\(same key = move to end)."
  (interactive)
  (let* ((root  (arrow-project--root))
         (alist (arrow-project--load root))
         (fmt   (lambda (key path)
                  (format " [%s] %s"
                          (propertize key 'face 'arrow-key-face)
                          path))))
    (unless alist (user-error "No project bookmarks to reorder"))
    (when-let* ((source-key (arrow--show-reorder-popup "Project: Reorder" alist fmt nil))
                (target-key (arrow--show-reorder-popup "Project: Reorder" alist fmt source-key)))
      (arrow-project--save root (arrow--reorder-alist alist source-key target-key))
      (message "Moved project bookmark [%s]." source-key))))


;;; cycling

(defun arrow-project-cycle (direction)
  "Cycle project bookmarks.  DIRECTION is 1 (next) or -1 (prev)."
  (let* ((root        (arrow-project--root))
         (alist       (arrow-project--load root))
         (current-file (when (buffer-file-name)
                         (file-relative-name (buffer-file-name) root)))
         (len         (length alist))
         (current-idx nil)
         (counter     0))
    (unless alist (user-error "No project bookmarks"))
    (dolist (item alist)
      (when (string= (cdr item) current-file)
        (setq current-idx counter))
      (setq counter (1+ counter)))
    (let* ((new-idx (if current-idx (mod (+ current-idx direction) len) 0))
           (target  (nth new-idx alist)))
      (find-file (expand-file-name (cdr target) root))
      (message "Project [%s]: %s" (car target) (cdr target)))))

;;;###autoload
(defun arrow-project-next ()
  "Move forward in project list."
  (interactive) (arrow-project-cycle 1))

;;;###autoload
(defun arrow-project-prev ()
  "Move backward in project list."
  (interactive) (arrow-project-cycle -1))


;;; modeline

(defun arrow-project--current-key ()
  "Return the project bookmark key for the current buffer, or nil if none."
  (when-let* ((file   (buffer-file-name))
              (proj   (project-current))
              (root   (project-root proj))
              (alist  (arrow-project--load root))
              (rel    (file-relative-name file root))
              ;; rassoc looks up by value using `equal'
              (entry  (rassoc rel alist)))
    (car entry)))

(defun arrow-project-modeline-string ()
  "Return the modeline string for the current project bookmark.
The result is cached buffer-locally and only recomputed when alist changes."
  (when (and arrow-project-modeline (buffer-file-name))
    (when-let* ((root  (arrow-project--get-root))
                (alist (arrow-project--load root)))
      (let ((cache arrow-project--modeline-cache))
        (if (and cache (eq (car cache) alist))
            (cdr cache) ; if alist object unchanged, return cached string
          ;; otherwise recompute and save in cache
          (let* ((rel   (file-relative-name (buffer-file-name) root))
                 (entry (rassoc rel alist))
                 (str   (when entry
                          (propertize
                           (format " %s[%s] "
                                   arrow-project-modeline-glyph
                                   (car entry))
                           'face 'arrow-bookmark-face))))
            (setq arrow-project--modeline-cache (cons alist str))
            str))))))

(provide 'arrow-project)
;;; arrow-project.el ends here
