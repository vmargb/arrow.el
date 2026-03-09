;;; arrow.el --- File-local and Project-local transient bookmarks -*- lexical-binding: t; -*-

;; Author: vmargb
;; Version: 0.3.0
;; Package-Requires: ((emacs "28.1"))
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; License: MIT

;; Description: Buffer-local and project-local bookmarks with a centered transient hover window.

;;; Commentary:
;; An implementation of arrow.nvim in Emacs.  A harpoon-like bookmarking system using transient menu.

(require 'arrow-core)

;;; Code:

(defgroup arrow nil
  "File-local bookmarks with transient popups."
  :group 'convenience)

(defcustom arrow-persist t
  "If non-nil, save bookmarks to a storage file automatically."
  :type 'boolean
  :group 'arrow)

(defcustom arrow-auto-promote nil
  "If non-nil, automatically move bookmarks to the top of the list when jumping."
  :type 'boolean
  :group 'arrow)

(defvar-local arrow-alist nil
  "Alist of file-scoped bookmarks.  Format: ((char . marker) ...).")


;;; Buffer-local functions

(defun arrow--save-to-file ()
  "Save markers as positions."
  (when-let* ((file (arrow--storage-file))
              (data (delq nil
                          (mapcar (lambda (x)
                                    (let ((pos (marker-position (cdr x))))
                                      (when pos (cons (car x) pos))))
                                  arrow-alist))))
    (arrow--save-data file data)))

(defun arrow--load-from-file ()
  "Load bookmark positions from storage."
  (when-let* ((file (arrow--storage-file))
              (data (arrow--load-data file))
              ((listp data))
              (target-buffer (current-buffer)))
    (setq arrow-alist nil)
    (dolist (item data)
      (when (and (consp item) (numberp (cdr item)))
        (let ((marker (make-marker)))
          (set-marker marker (cdr item) target-buffer)
          (push (cons (car item) marker) arrow-alist))))))

(defun arrow--promote (char)
  "Move the bookmark for CHAR to the front of `arrow-alist`."
  (let ((entry (assoc char arrow-alist)))
    (when entry
      (setq arrow-alist (cons entry (delq entry arrow-alist)))
      (arrow--save-to-file))))

(defun arrow-promote-bookmark ()
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to promote"))
  (let ((char (read-char "Promote bookmark key: ")))
    (if (assoc char arrow-alist)
        (progn (arrow--promote char) (message "Promoted bookmark '%c'." char))
      (message "No bookmark found for '%c'" char))))

(defun arrow-add ()
  (interactive)
  (let* ((input (read-char "Bookmark key (0-9, a-z, RET for auto): "))
         (char (if (= input ?\r)
                   (arrow--find-free-key-in arrow-alist)
                 (unless (or (and (>= input ?a) (<= input ?z))
                             (and (>= input ?0) (<= input ?9)))
                   (user-error "Please use a letter (a-z), number (0-9), or RET"))
                 input))
         (marker (point-marker)))
    (setf (alist-get char arrow-alist) marker)
    (if arrow-auto-promote (arrow--promote char) (arrow--save-to-file))
    (message "Added bookmark '%c' at line %d" char (line-number-at-pos))))

(defun arrow-delete ()
  (interactive)
  (unless arrow-alist (user-error "No bookmarks to delete"))
  (let ((char (read-char "Delete bookmark key: ")))
    (if (alist-get char arrow-alist)
        (progn
          (setq arrow-alist (assq-delete-all char arrow-alist))
          (arrow--save-to-file)
          (message "Deleted bookmark '%c'" char))
      (message "No bookmark found for '%c'" char))))

(defun arrow-clear-all ()
  (interactive)
  (when (y-or-n-p "Clear all bookmarks for this file? ")
    (setq arrow-alist nil)
    (when-let ((file (arrow--storage-file)))
      (when (file-exists-p file) (delete-file file)))
    (message "Cleared all bookmarks.")))

;;; Display and Jump Logic

(defun arrow-close-popup ()
  "Close the transient popup window/frame."
  (when (frame-live-p arrow--popup-frame)
    (delete-frame arrow--popup-frame)
    (setq arrow--popup-frame nil))
  (when (window-live-p arrow--popup-window)
    (delete-window arrow--popup-window)
    (setq arrow--popup-window nil)))

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
                 `((parent-frame . ,parent) (minibuffer . nil) (undecorated . t)
                   (internal-border-width . 3) (background-color . ,(face-background 'tooltip nil t))
                   (width . ,width-chars) (height . ,lines) (left . ,left) (top . ,top)
                   (no-accept-focus . t)))))
    (set-window-buffer (frame-root-window frame) buf)
    (set-window-dedicated-p (frame-root-window frame) t)
    (make-frame-visible frame)
    (setq arrow--popup-frame frame)))

(defun arrow--show-popup (title alist format-fn)
  "Generic transient popup logic. Returns the selected (key . value) or nil."
  (unless alist (user-error "No bookmarks to display"))
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
      (setq arrow--popup-window (display-buffer buf '((display-buffer-at-bottom)
                                                      (window-height . fit-window-to-buffer)))))
    (redisplay t)
    
    (unwind-protect
        (let ((key (read-key "Bookmark key: ")))
          (cond
           ((or (eq key ?\C-g) (eq key ?q)) (message "Cancelled."))
           ((alist-get key alist) (setq result (assoc key alist)))
           (t (message "No bookmark for key: %c" key))))
      (arrow-close-popup))
    
    result)) ;; return the selection AFTER the popup closes

(defun arrow-show ()
  "Display file bookmarks in a popup and jump via single keypress."
  (interactive)
  (when-let* ((selection
               (arrow--show-popup
                "Bookmarks" arrow-alist
                (lambda (char marker)
                  (let* ((line (if (marker-buffer marker)
                                   (line-number-at-pos marker)
                                 "?"))
                         (preview (if (marker-buffer marker)
                                      (with-current-buffer (marker-buffer marker)
                                        (save-excursion
                                          (goto-char marker)
                                          (buffer-substring
                                           (line-beginning-position)
                                           (line-end-position))))
                                    "<dead marker>")))
                    (format " [%s] Line %-4s %s"
                            (propertize (char-to-string char)
                                        'face 'arrow-key-face)
                            line
                            (string-trim preview))))))

              (key (car selection))
              (jump-marker (cdr selection)))

    ;; Actions run safely outside popup lifecycle
    (when arrow-auto-promote
      (arrow--promote key))

    (when (marker-buffer jump-marker)
      (switch-to-buffer (marker-buffer jump-marker))
      (goto-char jump-marker))))

;;; Minor Mode

(defvar arrow-mode-map
  (make-sparse-keymap)
  "Keymap for `arrow-mode'.")

;;;###autoload
(define-minor-mode arrow-mode
  "Minor mode for file-local transient bookmarks."
  :lighter " Arrow"
  :keymap arrow-mode-map
  (if arrow-mode
      (progn
        (arrow--load-from-file)
        (add-hook 'after-save-hook #'arrow--save-to-file nil t)
        (add-hook 'kill-buffer-hook #'arrow--save-to-file nil t))
    (remove-hook 'after-save-hook #'arrow--save-to-file t)
    (remove-hook 'kill-buffer-hook #'arrow--save-to-file t)))

(defun arrow--maybe-load ()
  "Load storage if it exists, otherwise continue as normal."
  (let ((file (arrow--storage-file)))
    (when (and file (file-exists-p file))
      (unless arrow-mode (arrow-mode 1)))))

(add-hook 'find-file-hook #'arrow--maybe-load)

(require 'arrow-project)

(provide 'arrow)

;;; arrow.el ends here
