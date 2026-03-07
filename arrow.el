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



(provide 'arrow)
;;; arrow.el ends here
