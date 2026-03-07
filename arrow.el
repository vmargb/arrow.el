;;; arrow.el --- buffer-local transient bookmarks -*- lexical-binding: t; -*-

;; author: vmargb
;; version: 0.1
;; package-requires: ((emacs "27.1"))
;; description: buffer-local bookmarks with a transient hover menu.

;;; Commentary:

;; An implementation of arrow.nvim in Emacs.  Which is a
;; harpoon-like bookmarking system for your buffer (isolated per buffer)
;; where each line is a mark to jump or iterate through

;;; code:

(defgroup arrow nil ;; customization group
  "buffer-local bookmarks with transient popups."
  :group 'convenience)

(defcustom arrow-persist t
  "if non-nil, save bookmarks to a storage file automatically."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-storage-dir
  (expand-file-name "arrow/" user-emacs-directory)
  "directory where arrow bookmark files are stored."
  :type 'directory
  :group 'arrow)

(defvar-local arrow-alist nil
  "alist of file-scoped bookmarks. format: ((char . marker) ...)")

;; popup state
(defvar arrow--popup-frame nil)
(defvar arrow--popup-window nil)

(defface arrow-key-face
  '((t (:inherit font-lock-keyword-face :weight bold :foreground "#ff6b6b")))
  "face for highlighting bookmark keys in the popup."
  :group 'arrow)


;; storage

(defun arrow--storage-file ()
  "Return bookmark storage file for current buffer."
  (when (buffer-file-name)
    (make-directory arrow-storage-dir t)
    (expand-file-name
     (concat (md5 (buffer-file-name)) ".bm")
     arrow-storage-dir)))


;;; Main functionality

(defun arrow-add ()
  "Add or update a bookmark at point using a single character."
  (interactive)
  (let ((char (read-char "Bookmark key (a-z, 0-9): ")))
    (unless (or (and (>= char ?a) (<= char ?z))
                (and (>= char ?0) (<= char ?9)))
      (user-error "Please use a letter (a-z) or number (0-9)"))
    (let ((marker (point-marker)))
      (setf (alist-get char arrow-alist) marker)
      (arrow--save-to-file) ;; to be implemented
      (message "Added bookmark '%c' at line %d" char (line-number-at-pos)))))

(defun arrow-delete ()
  "Delete a specific bookmark by its character key."
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to delete"))
  (let ((char (read-char "Delete bookmark key: ")))
    (if (alist-get char arrow-alist)
        (progn
          (setq arrow-alist (assq-delete-all char arrow-alist))
          (arrow--save-to-file) ;; to be implemented
          (message "Deleted bookmark '%c'" char))
      (message "No bookmark found for '%c'" char))))

(defun arrow-clear-all ()
  "Clear all file-local bookmarks and remove the storage file."
  (interactive)
  (when (y-or-n-p "Clear all bookmarks for this file? ")
    (setq arrow-alist nil)
    (let ((file (arrow--storage-file)))
      (when (and file (file-exists-p file))
        (delete-file file)))
    (message "Cleared all bookmarks.")))



(provide 'arrow)
;;; arrow.el ends here
