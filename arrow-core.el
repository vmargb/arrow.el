;;; arrow-core.el --- shared helpers for arrow -*- lexical-binding: t; -*-

;; Minimal shared core used by arrow.el and arrow-project.el
;; Exports:
;;   arrow--get-storage-path, arrow--storage-file (helper),
;;   arrow--save-data, arrow--load-data,
;;   arrow--find-free-key-in,
;;   arrow--show-popup (generic popup)
;;   face: arrow-key-face

;;; commentary:
;; Shared utility functions to handle arrow and arrow-core functionality.

(require 'subr-x)

;;; Code:

(defgroup arrow-core nil
  "Shared helpers for arrow.* packages."
  :group 'convenience)

(defcustom arrow-storage-dir
  (expand-file-name "arrow/" user-emacs-directory)
  "Directory where arrow bookmark files are stored."
  :type 'directory
  :group 'arrow-core)

;; popup state
(defvar arrow--popup-frame nil)
(defvar arrow--popup-window nil)

(defface arrow-key-face
  '((t (:inherit font-lock-keyword-face :weight bold :foreground "#FF6B6B")))
  "Face for highlighting bookmark keys in the popup."
  :group 'arrow-core)

;;; storage helpers

(defun arrow--get-storage-path (id-string)
  "Return bookmark storage file given a unique ID-STRING."
  (make-directory arrow-storage-dir t)
  (expand-file-name (concat (md5 id-string) ".bm") arrow-storage-dir))

(defun arrow--storage-file ()
  "Return bookmark storage file for current buffer."
  (when (buffer-file-name)
    (arrow--get-storage-path (buffer-file-name))))

(defun arrow--save-data (file data)
  "Generic function to save DATA to FILE."
  (when file
    (with-temp-file file
      (let ((print-level nil) (print-length nil))
        (insert (prin1-to-string data))))))

(defun arrow--load-data (file)
  "Generic function to load data from FILE, or nil if not present."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (read (current-buffer)))))

;;; key helpers

(defun arrow--find-free-key-in (alist)
  "Find next available bookmark key (1-9 then a-z) missing from ALIST."
  (let* ((used-keys (mapcar #'car alist))
         (priority (append (number-sequence ?1 ?9)
                           (number-sequence ?a ?z)))
         (keys priority)
         found)
    (while keys
      (let ((k (pop keys)))
        (unless (memq k used-keys)
          (setq found k)
          (setq keys nil))))
    (or found (user-error "No free bookmark keys available (1-9, a-z)"))))

;;; popup display helpers

(defun arrow--display-child-frame (buf)
  "Display BUF in a centered child frame (GUI only)."
  (let* ((parent (selected-frame))
         (lines (+ 2 (with-current-buffer buf (count-lines (point-min) (point-max)))))
         (width-chars 75)
         (char-width (or (frame-char-width parent) 10))
         (char-height (or (frame-char-height parent) 20))
         (px-width (* width-chars char-width))
         (px-height (* lines char-height))
         (left (/ (- (frame-pixel-width parent) px-width) 2))
         (top (/ (- (frame-pixel-height parent) px-height) 2))
         (frame (make-frame
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

(defun arrow--show-popup (title alist format-fn)
  "Generic transient popup.  Return selected (KEY . VAL) or nil.
TITLE is displayed at top; ALIST is the list to show; FORMAT-FN is a
function (key val) -> string for each line."
  (unless alist (user-error "No items to display"))
  (let ((buf (get-buffer-create " *arrow-popup*"))
        (text-lines '())
        (result nil))
    (dolist (bm alist)
      (push (funcall format-fn (car bm) (cdr bm)) text-lines))

    (with-current-buffer buf
      (erase-buffer)
      (setq mode-line-format nil header-line-format nil cursor-type nil)
      (insert (propertize (format " %s (Press key to jump, q/C-g to quit)\n\n" title) 'face 'bold))
      (insert (string-join (reverse text-lines) "\n")))

    (if (display-graphic-p)
        (arrow--display-child-frame buf)
      (setq arrow--popup-window
            (display-buffer buf '((display-buffer-at-bottom) (window-height . fit-window-to-buffer)))))
    (redisplay t)

    (unwind-protect
        (let ((key (read-key "Key: ")))
          (cond
           ((or (eq key ?\C-g) (eq key ?q))
            (message "Cancelled."))
           ((alist-get key alist)
            ;; use assoc to return the original cons cell
            (setq result (assoc key alist)))
           (t (message "No item for key: %c" key))))
      (when (frame-live-p arrow--popup-frame)
        (delete-frame arrow--popup-frame)
        (setq arrow--popup-frame nil))
      (when (window-live-p arrow--popup-window)
        (delete-window arrow--popup-window)
        (setq arrow--popup-window nil)))
    result))

(provide 'arrow-core)
;;; arrow-core.el ends here
