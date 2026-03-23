;;; arrow-org.el --- Dynamic org bookmarks for arrow -*- lexical-binding: t; -*-

;; Author: vmargb
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Project and file-specific note management with smart return navigation
;; every file and project is dynamically linked to its own org file
;; used for quick note-taking and jumping back-and-forth between them

;;; Code:

(require 'project)
(require 'arrow-core)

(defgroup arrow-org nil
  "Note-taking integration for arrow."
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

;;; helpers

(defun arrow-org--is-note-buffer-p ()
  "Check if the current buffer is an Arrow note."
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
                    (format-time-string "%Y-%m-%d")))))

(defun arrow-org--return-to-source (source &optional return-pos)
  "Return to SOURCE file at RETURN-POS, closing the org note's window or frame.
Mirrors how the note was opened, so same-window uses `find-file', `other-window'
deletes the note window, `other-frame' deletes the note frame"
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

(defun arrow-org-open-project ()
  "Toggle between project-wide notes and the current file.
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
      ;; store return position in the source file property for later
      (org-set-property "ARROW_POS" (number-to-string current-pos)))))

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

;;; legacy aliases for backward compatibility

(defalias 'arrow-notes-open-project 'arrow-org-open-project)
(defalias 'arrow-notes-open-file 'arrow-org-open-file)

(provide 'arrow-org)

;;; arrow-org.el ends here
