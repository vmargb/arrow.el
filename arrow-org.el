;;; arrow-org.el --- Dynamic note bookmarks for arrow -*- lexical-binding: t; -*-

;;; Commentary:
;; Project and file-specific note management with smart return navigation.

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
  "Ways to open notes are 'same-window, 'other-window, or 'other-frame."
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

;;; commands

(defun arrow-org-open-project ()
  "Toggle between project-wide notes and the current file.
Always returns to the specific file you came from."
  (interactive)
  (if (arrow-org--is-note-buffer-p)
      ;; GOING BACK to file, get properties BEFORE leaving org buffer
      (if-let ((source (org-entry-get (point-min) "ARROW_SOURCE" t)))
          (let ((return-pos (org-entry-get (point-min) "ARROW_POS" t)))
            (save-buffer)
            (find-file source)
            ;; Restore position if we stored it
            (when return-pos
              (goto-char (string-to-number return-pos))))
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
          (progn
            (save-buffer)
            (find-file source))
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

(defun arrow-org-quick-capture ()
  "Quickly capture a note without leaving current buffer.
Inserts a timestamped entry into the project notes."
  (interactive)
  (let* ((root (arrow-org--get-project-root))
         (notes-file (expand-file-name 
                      (concat (file-name-nondirectory (directory-file-name root)) ".org")
                      arrow-org-directory))
         (source-file (buffer-file-name))
         (selection (when (use-region-p)
                      (buffer-substring-no-properties (region-beginning) (region-end)))))
    (unless (file-exists-p (file-name-directory notes-file))
      (make-directory (file-name-directory notes-file) t))
    (with-current-buffer (find-file-noselect notes-file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "** TODO %s\n   :PROPERTIES:\n   :ARROW_SOURCE: %s\n   :CAPTURED: %s\n   :END:\n"
                      (or selection "Note")
                      source-file
                      (format-time-string "%Y-%m-%d %H:%M")))
      (when selection
        (insert (format "   #+BEGIN_QUOTE\n   %s\n   #+END_QUOTE\n" selection)))
      (save-buffer))
    (message "Captured to %s" (file-name-nondirectory notes-file))))

(defun arrow-org-list-project-notes ()
  "List all project notes with completion."
  (interactive)
  (let* ((root (arrow-org--get-project-root))
         (project-dir (expand-file-name
                       (file-name-nondirectory (directory-file-name root))
                       arrow-org-directory))
         (files (when (file-exists-p project-dir)
                  (directory-files-recursively project-dir "\\.org$"))))
    (if files
        (find-file (completing-read "Project note: " files nil t))
      (message "No notes found for this project"))))

;;; Legacy aliases for backward compatibility

(defalias 'arrow-notes-open-project 'arrow-org-open-project)
(defalias 'arrow-notes-open-file 'arrow-org-open-file)

(provide 'arrow-org)

;;; arrow-org.el ends here
