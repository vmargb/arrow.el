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

;;; display and jump logic

(defun arrow-close-popup ()
  "close the transient popup window/frame."
  (when (frame-live-p arrow--popup-frame)
    (delete-frame arrow--popup-frame)
    (setq arrow--popup-frame nil))
  (when (window-live-p arrow--popup-window)
    (delete-window arrow--popup-window)
    (setq arrow--popup-window nil)))

(defun arrow--display-child-frame (buf)
  "display buf in a centered child frame (gui only)."
  (let* ((parent (selected-frame))
         (lines (+ 2 (with-current-buffer buf
                       (count-lines (point-min) (point-max)))))
         (width-chars 75)
         (px-width (* width-chars (frame-char-width parent)))
         (px-height (* lines (frame-char-height parent)))
         (left (/ (- (frame-pixel-width parent) px-width) 2))
         (top (/ (- (frame-pixel-height parent) px-height) 2))
         (frame
          (make-frame
           `((parent-frame . ,parent)
             (minibuffer . nil)
             (undecorated . t)
             (internal-border-width . 3)
             (background-color . ,(face-background 'tooltip nil t))
             (width . ,width-chars)
             (height . ,lines)
             (left . ,left)
             (top . ,top)
             (no-accept-focus . t)))))
    (set-window-buffer (frame-root-window frame) buf)
    (set-window-dedicated-p (frame-root-window frame) t)
    (make-frame-visible frame)
    (setq arrow--popup-frame frame)))

(defun arrow-show ()
  "display file bookmarks in a popup and jump via single keypress."
  (interactive)
  (unless arrow-alist (user-error "no bookmarks in this file"))
  (let* ((orig-alist arrow-alist)
         (buf (get-buffer-create " *arrow-popup*"))
         (text-lines '())
         jump-marker)

    (dolist (bm orig-alist)
      (let* ((char (car bm))
             (marker (cdr bm))
             (line (if (marker-buffer marker)
                       (line-number-at-pos marker)
                     "?"))
             (preview
              (if (marker-buffer marker)
                  (with-current-buffer (marker-buffer marker)
                    (save-excursion
                      (goto-char marker)
                      (buffer-substring
                       (line-beginning-position)
                       (line-end-position))))
                "<dead marker>")))
        (push
         (format " [%s] line %-4s %s"
                 (propertize (char-to-string char)
                             'face 'arrow-key-face)
                 line
                 (string-trim preview))
         text-lines)))

    (with-current-buffer buf
      (erase-buffer)
      (setq mode-line-format nil)
      (setq header-line-format nil)
      (setq cursor-type nil)
      (insert (propertize
               " bookmarks (press key to jump, q/c-g to quit)\n\n"
               'face 'bold))
      (insert (string-join (reverse text-lines) "\n")))

    (if (display-graphic-p)
        (arrow--display-child-frame buf)
      (setq arrow--popup-window
            (display-buffer
             buf '((display-buffer-at-bottom)
                   (window-height . fit-window-to-buffer)))))

    (redisplay t)

    (unwind-protect
        (let ((key (read-key "bookmark key: ")))
          (cond
           ((or (eq key ?\c-g) (eq key ?q))
            (message "bookmark jump cancelled."))
           ((alist-get key orig-alist)
            (setq jump-marker (alist-get key orig-alist)))
           (t
            (message "no bookmark for key: %c" key))))
      (arrow-close-popup))

    (when (and jump-marker (marker-buffer jump-marker))
      (switch-to-buffer (marker-buffer jump-marker))
      (goto-char jump-marker))))


;;; Persistence

(defun arrow--save-to-file ()
  "Save markers as positions."
  (when-let* ((file (arrow--storage-file))
              (data (delq nil
                          (mapcar (lambda (x)
                                    (let ((pos (marker-position (cdr x))))
                                      (when pos
                                        (cons (car x) pos))))
                                  arrow-alist))))
    (with-temp-file file
      (let ((print-level nil)
            (print-length nil))
        (insert (prin1-to-string data))))))

(defun arrow--load-from-file ()
  "Load bookmark positions from storage."
  (when-let* ((file (arrow--storage-file))
              ((file-exists-p file))
              (target-buffer (current-buffer))
              (data (with-temp-buffer
                      (insert-file-contents file)
                      (read (current-buffer))))
              ((listp data)))
    (with-current-buffer target-buffer
      (setq arrow-alist nil)
      (dolist (item data)
        (when (and (consp item)
                   (numberp (cdr item)))
          (let ((marker (make-marker)))
            (set-marker marker (cdr item) target-buffer)
            (push (cons (car item) marker) arrow-alist)))))))

;;; Minor Mode

;;;###autoload
(define-minor-mode arrow-mode
  "Minor mode for file-local transient bookmarks."
  :init-value nil
  :lighter " Arrow"
  :keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c b a") #'arrow-add)
    (define-key map (kbd "C-c b l") #'arrow-show)
    (define-key map (kbd "C-c b d") #'arrow-delete)
    (define-key map (kbd "C-c b C") #'arrow-clear-all)
    map)
  (if arrow-mode
      (progn
        (arrow--load-from-file)
        (add-hook 'after-save-hook #'arrow--save-to-file nil t)
        (add-hook 'kill-buffer-hook #'arrow--save-to-file nil t))
    (remove-hook 'after-save-hook #'arrow--save-to-file t)
    (remove-hook 'kill-buffer-hook #'arrow--save-to-file t)))

(defun arrow--maybe-load ()
  "Auto-enable arrow-mode when a bookmark file exists."
  (let ((file (arrow--storage-file)))
    (when (and file (file-exists-p file))
      (unless arrow-mode
        (arrow-mode 1)))))

(add-hook 'find-file-hook #'arrow--maybe-load)

(provide 'arrow)
;;; arrow.el ends here
