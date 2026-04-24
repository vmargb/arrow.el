;;; arrow-org.el --- Dynamic org bookmarks for arrow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.0.2
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Project and file-specific note management with smart return navigation
;; every file and project is dynamically linked to its own org file
;; used for quick note-taking and jumping back-and-forth between them

;;; Code:

(require 'project)

(declare-function org-set-property "org" (property value))
(declare-function org-entry-get "org" (pom property &optional inherit literal-nil))

(defgroup arrow-org nil
  "Org-mode bookmarks for arrow."
  :group 'arrow)

(defcustom arrow-org-directory "~/org/arrow-notes/"
  "Directory for where project and file-specific notes are stored."
  :type 'directory
  :group 'arrow-org)

(defcustom arrow-org-window-behavior 'same-window
  "Ways to open notes are `same-window', `other-window', or `other-frame'."
  :type '(choice (const :tag "Same window" same-window)
                 (const :tag "Other window" other-window)
                 (const :tag "Other frame" other-frame))
  :group 'arrow-org)

(defcustom arrow-org-function-heading-level 2
  "Org heading level used when creating per-function headings."
  :type 'natnum
  :group 'arrow-org)

;;; helpers

(defun arrow-org--is-note-buffer-p ()
  "Check if the current buffer is an Org note."
  (and (derived-mode-p 'org-mode)
       (string-prefix-p (expand-file-name arrow-org-directory)
                        (or (buffer-file-name) ""))))

(defun arrow-org--get-project-root ()
  "Get the current project root or error."
  (if-let ((proj (project-current)))
      (project-root proj)
    (user-error "Not in a project")))

(defun arrow-org--ensure-source-property (path)
  "Store the source PATH in the Org file properties, updating if changed."
  (when (and path (derived-mode-p 'org-mode))
    (save-excursion
      (goto-char (point-min))
      ;; always update to current source allowing dynamic return
      (org-set-property "ARROW_SOURCE" path))))

(defun arrow-org--open-file (file)
  "Open FILE according to `arrow-org-window-behavior'."
  (pcase arrow-org-window-behavior
    ('other-window (find-file-other-window file))
    ('other-frame (find-file-other-frame file))
    (_ (find-file file))))

(defun arrow-org--open-and-setup (note-path source-path)
  "Open NOTE-PATH and ensure it links back to SOURCE-PATH."
  (let ((dir (file-name-directory note-path)))
    (unless (file-exists-p dir) (make-directory dir t)))
  (arrow-org--open-file note-path)
  (arrow-org--ensure-source-property source-path)
  ;; add a header if new file
  (when (= (point-min) (point-max))
    (insert (format "#+TITLE: Notes for %s\n#+DATE: %s\n\n* Overview\n\n"
                    (file-name-base note-path)
                    (format-time-string "%F")))))

(defun arrow-org--return-to-source (source &optional return-pos)
  "Return to SOURCE file at RETURN-POS, closing the org note's window or frame.
Mirrors how the note was opened, so same-window uses `find-file', `other-window'
deletes the note window and `other-frame' deletes the note frame"
  (save-buffer)
  (pcase arrow-org-window-behavior
    ('other-frame
     ;; the source is already open in the original frame so close this one
     ;; delete-frame returns focus to the original frame automatically.
     (let ((source-buf (find-buffer-visiting source)))
       (delete-frame)
       (when source-buf
         (switch-to-buffer source-buf)
         (when return-pos
           (goto-char (string-to-number return-pos))))))
    ('other-window
     ;; the source is still visible in the original windows, close this split
     (let* ((source-buf (find-buffer-visiting source))
            (source-win (and source-buf (get-buffer-window source-buf))))
       (if source-win
           (progn
             ;; set position before switching windows
             (when return-pos
               (with-current-buffer source-buf
                 (goto-char (string-to-number return-pos))))
             (delete-window))
         ;; fallback, source somehow not visible, just open it normally
         (find-file source)
         (when return-pos
           (goto-char (string-to-number return-pos))))))
    (_
     ;; same-window: replace current buffer with source as before
     (find-file source)
     (when return-pos
       (goto-char (string-to-number return-pos))))))

;;; commands

;;;###autoload
(defun arrow-org-open-project ()
  "Toggle between project-wide notes from any source file.
Always returns to the specific file you came from."
  (interactive)
  (if (arrow-org--is-note-buffer-p)
      ;; GOING BACK to file, get properties BEFORE leaving org buffer
      (if-let ((source (org-entry-get (point-min) "ARROW_SOURCE" t)))
          (arrow-org--return-to-source
           source (org-entry-get (point-min) "ARROW_POS" t))
        (message "No source link found."))
    ;; GOING TO NOTE, store current position for precise return
    (let* ((root (arrow-org--get-project-root))
           (notes-file (expand-file-name
                        (concat (file-name-nondirectory (directory-file-name root)) ".org")
                        arrow-org-directory))
           (current-pos (point)))
      ;; store position in a buffer-local variable or property
      (arrow-org--open-and-setup notes-file (buffer-file-name))
      ;; Anchor to point-min so ARROW_POS lands at the document level,
      ;; the same place ARROW_SOURCE is written and org-entry-get reads from.
      (save-excursion
        (goto-char (point-min))
        (org-set-property "ARROW_POS" (number-to-string current-pos))))))

;;;###autoload
(defun arrow-org-open-file ()
  "Toggle between file-specific notes and the source file.
Maintains separate note files per source file."
  (interactive)
  (if (arrow-org--is-note-buffer-p)
      ;; GOING BACK
      (if-let ((source (org-entry-get (point-min) "ARROW_SOURCE" t)))
          (arrow-org--return-to-source source)
        (message "No source link found."))
    ;; GOING TO NOTE
    (unless (buffer-file-name) (user-error "Buffer has no file"))
    (let* ((root (arrow-org--get-project-root))
           (relpath (file-relative-name (buffer-file-name) root))
           ;; sanitize path for filesystem safety
           (safe-relpath (replace-regexp-in-string "[\\/]" "-" relpath))
           (note-path (expand-file-name
                       (concat (file-name-nondirectory (directory-file-name root))
                               "/" safe-relpath ".notes.org")
                       arrow-org-directory)))
      (arrow-org--open-and-setup note-path (buffer-file-name)))))

;;;###autoload
(defun arrow-org-open-function ()
  "Open or jump to an Org heading for the function at point.
Uses the same per-file note as `arrow-org-open-file'.  If the note
already contains a heading for the current function it jumps straight
to it, otherwise a new heading is created at the end of the file."
  (interactive)
  (when (arrow-org--is-note-buffer-p)
    (user-error "arrow-org-open-function is for source files only"))
  (unless (buffer-file-name) (user-error "Buffer has no file"))
  (let* ((fn-name (or (add-log-current-defun) ; get current function (built-in)
                      (user-error "No function found at point")))
         (source-file (buffer-file-name))
         (source-pos  (point))
         (root        (arrow-org--get-project-root))
         (relpath     (file-relative-name source-file root))
         (safe-name   (replace-regexp-in-string "[\\/]" "-" relpath))
         (note-path   (expand-file-name
                       (concat (file-name-nondirectory (directory-file-name root))
                               "/" safe-name ".notes.org")
                       arrow-org-directory)))
    ;; open / create the note file (stores ARROW_SOURCE automatically)
    (arrow-org--open-and-setup note-path source-file)
    ;; also store exact cursor position so return lands precisely
    (org-set-property "ARROW_POS" (number-to-string source-pos))
    ;; search for existing heading or create a new one
    (let* ((level   (max 1 arrow-org-function-heading-level))
           (stars   (make-string level ?*))
           (heading-re (format "^%s[ \t]+%s[ \t]*$"
                               (regexp-quote stars)
                               (regexp-quote fn-name))))
      (goto-char (point-min))
      (if (re-search-forward heading-re nil t)
          (progn
            (beginning-of-line)
            (message "arrow-org: jumped to '%s'" fn-name))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "\n%s %s\n\n" stars fn-name))
        (forward-line -1)
        (message "arrow-org: created heading for '%s'" fn-name)))))

;;;###autoload
(defun arrow-org-list-project-notes ()
  "List all project notes with completion."
  (interactive)
  (let* ((root (arrow-org--get-project-root))
         (project-name (file-name-nondirectory (directory-file-name root)))
         (project-note (expand-file-name
                        (concat project-name ".org")
                        arrow-org-directory))
         (project-dir (expand-file-name project-name arrow-org-directory))
         (file-notes (when (file-exists-p project-dir)
                       (directory-files-recursively project-dir "\\.org$")))
         (files (append
                 (when (file-exists-p project-note) (list project-note))
                 file-notes)))
    (if files
        (find-file (completing-read "Project note: " files nil t))
      (message "No notes found for this project"))))

(provide 'arrow-org)

;;; arrow-org.el ends here
