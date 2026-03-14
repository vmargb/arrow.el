;;; arrow-project.el --- Project-level transient bookmarks -*- lexical-binding: t; -*-

;;; commentary:
;; Project specific implementation of arrow.nvim in Emacs with identical
;; functionality to arrow.el

(require 'project)
(require 'arrow-core)

;;; Code:

(defvar arrow-project-cache (make-hash-table :test 'equal)
  "Cache for project bookmarks to avoid constant disk IO.  Keyed by project root.")

(defun arrow-project--root ()
  (if-let ((proj (project-current)))
      (project-root proj)
    (user-error "Not currently in a project (via project.el)")))

(defun arrow-project--file (root)
  (arrow--get-storage-path root))

(defun arrow-project--load (root)
  "Load bookmark alist for project ROOT."
  (or (gethash root arrow-project-cache)
      (let* ((file (arrow-project--file root))
             (data (or (arrow--load-data file) nil)))
        (puthash root data arrow-project-cache)
        data)))

(defun arrow-project--save (root alist)
  "Save project ALIST for project ROOT to cache and disk."
  (puthash root alist arrow-project-cache)
  (arrow--save-data (arrow-project--file root) alist))

(defun arrow-project-add ()
  (interactive)
  (unless (buffer-file-name)
    (user-error "Current buffer is not visiting a file"))
  (let* ((root (arrow-project--root))
         (alist (or (arrow-project--load root) nil))
         (file-path (file-relative-name (buffer-file-name) root))
         (input (read-char "Project bookmark key (1-9, a-z, RET for auto): "))
         (char (if (= input ?\r)
                   (arrow--find-free-key-in alist)
                 (unless (or (and (>= input ?a) (<= input ?z))
                             (and (>= input ?1) (<= input ?9)))
                   (user-error "Please use a letter (a-z), number (1-9), or RET"))
                 input)))
    ;; alist is updated properly
    (setq alist (cons (cons char file-path) (assq-delete-all char alist)))
    (when arrow-auto-promote
      (setq alist (cons (assoc char alist) (assq-delete-all char alist))))
    (arrow-project--save root alist)
    (message "Added project bookmark '%c' for %s" char file-path)))

(defun arrow-project-delete ()
  (interactive)
  (let* ((root (arrow-project--root))
         (alist (arrow-project--load root)))
    (unless alist (user-error "No project bookmarks to delete"))
    (let ((char (read-char "Delete project bookmark key: ")))
      (if (alist-get char alist)
          (progn
            (setq alist (assq-delete-all char alist))
            (arrow-project--save root alist)
            (message "Deleted project bookmark '%c'" char))
        (message "No project bookmark found for '%c'" char)))))


(defun arrow-jump-project ()
  "Jump directly to a project bookmark."
  (interactive)
  (let* ((root (arrow-project--root))
         (alist (arrow-project--load root)))

    (unless alist
      (user-error "No project bookmarks"))

    (let* ((char (read-char "Project bookmark: "))
           (entry (assoc char alist)))
      (unless entry
        (user-error "No project bookmark '%c'" char))
      (let ((path (cdr entry)))
        (when arrow-auto-promote
          (let ((new-alist
                 (cons entry (assq-delete-all char alist))))
            (arrow-project--save root new-alist)))

        (find-file (expand-file-name path root))))))

(defun arrow-project-show ()
  "Show first before jumping."
  (interactive)
  (let* ((root (arrow-project--root))
         (alist (or (arrow-project--load root) nil))
         (proj-name (file-name-nondirectory (directory-file-name root))))
    (when-let* ((selection
                 (arrow--show-popup
                  (format "Project Files (%s)" proj-name)
                  alist
                  (lambda (char path)
                    (format " [%s] %s"
                            (propertize (char-to-string char) 'face 'arrow-key-face)
                            path)))))
      (let ((key (car selection))
            (path (cdr selection)))
        (when arrow-auto-promote
          (let ((new-alist (cons (assoc key alist) (assq-delete-all key alist))))
            (arrow-project--save root new-alist)))
        (find-file (expand-file-name path root))))))

;; --- project-wide cycling

(defun arrow-project-cycle (direction)
  "Cycle project bookmarks. DIRECTION is 1 (next) or -1 (prev)."
  (let* ((root (arrow-project--root))
         (alist (arrow-project--load root))
         (current-file (when (buffer-file-name) 
                         (file-relative-name (buffer-file-name) root)))
         (len (length alist))
         (current-idx nil)
         (counter 0))
    (unless alist (user-error "No project bookmarks"))
    ;; find the current index
    (dolist (item alist)
      (when (string= (cdr item) current-file)
        (setq current-idx counter))
      (setq counter (1+ counter)))
    
    (let* ((new-idx (if current-idx (mod (+ current-idx direction) len) 0))
           (target (nth new-idx alist)))
      (find-file (expand-file-name (cdr target) root))
      (message "Project [%c]: %s" (car target) (cdr target)))))

(defun arrow-project-next () (interactive) (arrow-project-cycle 1))
(defun arrow-project-prev () (interactive) (arrow-project-cycle -1))

(provide 'arrow-project)
;;; arrow-project.el ends here
