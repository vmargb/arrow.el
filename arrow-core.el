;;; arrow-core.el --- Shared helpers for arrow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.0.2
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Minimal shared functions used by arrow, arrow-global & arrow-project
;; such as saving and loading from storage, drawing hover frame
;; handling keypresses etc.

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
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for highlighting bookmark keys in the popup."
  :group 'arrow-core)


;;; storage helpers

(defun arrow--get-storage-path (id-string)
  "Return bookmark storage file given a unique ID-STRING (using md5)."
  (make-directory arrow-storage-dir t)
  (expand-file-name (concat (md5 id-string) ".bm") arrow-storage-dir))

(defun arrow--storage-file ()
  "Return bookmark storage file for current buffer."
  (when (buffer-file-name)
    (arrow--get-storage-path (buffer-file-name))))

(defun arrow--save-data (file data)
  "Function to save DATA to FILE."
  (when file
    (with-temp-file file
      (let ((print-level nil) (print-length nil))
        (insert (prin1-to-string data))))))

(defun arrow--load-data (file)
  "Function to load data from FILE, or nil if not present."
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

(defun arrow-close-popup ()
  "Close the popup window/frame."
  (when (frame-live-p arrow--popup-frame)
    (delete-frame arrow--popup-frame)
    (setq arrow--popup-frame nil))
  (when (window-live-p arrow--popup-window)
    (delete-window arrow--popup-window)
    (setq arrow--popup-window nil)))

(defun arrow--display-child-frame (buf)
  "Display BUF in a centered child frame (GUI only)."
  (let* ((parent (selected-frame))
         (char-width  (or (frame-char-width parent)  10))
         (char-height (or (frame-char-height parent) 20))
         (width-chars 75)
         (px-width (* width-chars char-width))
         (content-lines (with-current-buffer buf
                          (count-lines (point-min) (point-max))))
         ;; cap height so the popup never overflows the parent frame (bookmarks missing)
         (max-lines (max 3 (- (/ (frame-pixel-height parent) char-height) 4)))
         (lines (min (+ 2 content-lines) max-lines))
         (px-height (* lines char-height))
         (left (/ (- (frame-pixel-width parent) px-width) 2))
         ;; clamp top: never go above the parent frame's top edge
         (top (max 0 (/ (- (frame-pixel-height parent) px-height) 2)))
         (frame (make-frame
                 `((parent-frame . ,parent) (minibuffer . nil) (undecorated . t)
                   (internal-border-width . 3)
                   (tab-bar-lines . 0)    ; suppress tab-bar
                   (tool-bar-lines . 0)   ; suppress tool bar
                   (menu-bar-lines . 0)   ; suppress menu bar
                   (background-color . ,(face-background 'tooltip nil t))
                   (width . ,width-chars) (height . ,lines)
                   (left . ,left) (top . ,top)
                   (no-accept-focus . t)))))
    (set-window-buffer (frame-root-window frame) buf)
    ;; explicitly scroll to top so newest entries (at buffer start) are always visible
    (set-window-start (frame-root-window frame)
                      (with-current-buffer buf (point-min)))
    (set-window-dedicated-p (frame-root-window frame) t)
    (make-frame-visible frame)
    (setq arrow--popup-frame frame)))

(defvar arrow--shift-map
  '((?! . ?1) (?@ . ?2) (?# . ?3) (?$ . ?4) (?% . ?5)
    (?^ . ?6) (?& . ?7) (?* . ?8) (?\( . ?9) (?\) . ?0)
    (?_ . ?-) (?+ . ?=) (?{ . ?\[) (?} . ?\]) (?| . ?\\)
    (?: . ?\;) (?\" . ?') (?< . ?,) (?> . ?.) (?? . ?/))
  "Map of shifted symbols to their base keys for when creating window split.")

(defface arrow-legend-face
  '((t (:inherit shadow :slant italic :height 0.9)))
  "Face for the legend shown in the popup header-line."
  :group 'arrow-core)

(defun arrow--show-popup (title alist format-fn)
  "Generic popup with associated TITLE & ALIST & FORMAT-FN.
Return (SELECTION . MODIFIERS) or nil."
  (unless alist (user-error "No bookmarks to display"))
  (let ((buf (get-buffer-create " *arrow-popup*"))
        (text-lines '())
        (result nil))

    (dolist (bm alist)
      (push (funcall format-fn (car bm) (cdr bm)) text-lines))

    (with-current-buffer buf
      (erase-buffer)
      ;; sticky legend using header-line-format to avoid scrolling
      (setq header-line-format
            (concat (propertize (format " %s " title) 'face 'bold)
                    (propertize " [Key] Jump | [C-Key] Split - | [S-Key] Split | | [q] Quit"
                                'face 'arrow-legend-face)))
      (setq mode-line-format nil
            cursor-type nil
            cursor-in-non-selected-windows nil
            truncate-lines t) ; truncate line to prevent line wrapping bug
      (insert (string-join (reverse text-lines) "\n"))
      (goto-char (point-min)))

    (if (display-graphic-p)
        (arrow--display-child-frame buf)
      (setq arrow--popup-window (display-buffer buf '((display-buffer-at-bottom)
                                                      (window-height . fit-window-to-buffer)))))
    (redisplay t)

    (unwind-protect
        (let* ((event (read-key "Select: "))
               (raw-key (event-basic-type event))
               (mods (event-modifiers event))
               ;; check if it's an uppercase letter (A -> a)
               (is-upper (and (characterp raw-key)
                              (not (eq raw-key (downcase raw-key)))))
               ;; check if it's a shifted symbol (! -> 1)
               (shifted-symbol (alist-get raw-key arrow--shift-map))
               ;; normalize key to lookup in alist
               (base-key (cond (is-upper (downcase raw-key))
                               (shifted-symbol shifted-symbol)
                               (t raw-key)))
               (final-mods (append mods ; combine modifer detection
                                   (when (or is-upper shifted-symbol) '(shift)))))
          (cond
           ((or (eq event ?\C-g) (eq event ?q)) (message "Cancelled."))
           ((assoc base-key alist)
            (setq result (cons (assoc base-key alist) final-mods)))
           (t (message "No bookmark for key: %s" (single-key-description event)))))
      (arrow-close-popup))
    result))

;;; reorder helpers

(defun arrow--reorder-alist (alist source-key target-key)
  "Return a new ALIST with SOURCE-KEY moved before TARGET-KEY.
If SOURCE-KEY equals TARGET-KEY, SOURCE-KEY is moved to the end of the list."
  (let* ((source-entry (assoc source-key alist))
         (rest (assq-delete-all source-key alist)))
    (if (eq source-key target-key) ;; if same key move to end
        (append rest (list source-entry))
      ;; insert source before target
      (let (result inserted)
        (dolist (entry rest)
          (when (and (not inserted) (eq (car entry) target-key))
            (push source-entry result)
            (setq inserted t))
          (push entry result))
        ;; append if target not found
        (unless inserted (push source-entry result))
        (nreverse result)))))

(defun arrow--show-reorder-popup (title alist format-fn selected-key)
  "Show a two-step reorder popup over ALIST.
TITLE and FORMAT-FN work the same as in `arrow--show-popup'
SELECTED-KEY is the bookmark being moved (nil in step 1)."
  (unless alist (user-error "No bookmarks to reorder"))
  (let ((buf (get-buffer-create " *arrow-popup*"))
        (text-lines '()))

    (dolist (bm alist)
      (let* ((is-selected (and selected-key (eq (car bm) selected-key)))
             (line (funcall format-fn (car bm) (cdr bm)))
             ;; highlight the item currently being moved
             (line (if is-selected
                       (propertize line 'face '(:weight bold :underline t))
                     line)))
        (push line text-lines)))

    (with-current-buffer buf
      (erase-buffer)
      (setq header-line-format
            (concat (propertize (format " %s " title) 'face 'bold)
                    (propertize
                     (if selected-key
                         (format " Moving [%c] -> insert BEFORE which? (same key = move to end) | [q] Cancel"
                                 selected-key)
                       " [Key] Select bookmark to MOVE | [q] Quit")
                     'face 'arrow-legend-face)))
      (setq mode-line-format nil
            cursor-type nil
            cursor-in-non-selected-windows nil
            truncate-lines t)
      (insert (string-join (reverse text-lines) "\n"))
      (goto-char (point-min)))

    (if (display-graphic-p)
        (arrow--display-child-frame buf)
      (setq arrow--popup-window (display-buffer buf '((display-buffer-at-bottom)
                                                      (window-height . fit-window-to-buffer)))))
    (redisplay t)

    (unwind-protect
        (let* ((event   (read-key "Select: "))
               (raw-key (event-basic-type event)))
          (cond
           ((or (eq event ?\C-g) (eq event ?q))
            (message "Cancelled.")
            nil)
           ((assoc raw-key alist) raw-key)
           (t
            (message "No bookmark for key: %s" (single-key-description event))
            nil)))
      (arrow-close-popup))))

(provide 'arrow-core)
;;; arrow-core.el ends here
