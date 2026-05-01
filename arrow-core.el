;;; arrow-core.el --- Shared helpers for arrow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.0
;; URL: https://github.com/vmargb/arrow.el
;; Keywords: convenience, navigation, bookmarks
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Minimal shared functions used by arrow, arrow-global & arrow-project
;; such as saving and loading from storage, drawing hover frame, and
;; handling keypresses.
;;
;; Keys are stored as strings (1 or 2 characters).  Legacy bookmark
;; files that used integer character codes are automatically migrated on
;; load.  And a strict prefix-free rule is enforced: if "m" exists then
;; "ma" is blocked, and vice versa.  This guarantees instant auto-jump
;; with no RET confirmation needed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

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

(defun arrow--migrate-keys (alist)
  "Migrate ALIST from legacy character keys to string keys.
Any entry whose car is a character (integer code) is converted via
`char-to-string'.  String keys are passed through unchanged."
  (mapcar (lambda (entry)
            (let ((k (car entry))
                  (v (cdr entry)))
              (cons (if (characterp k) (char-to-string k) k) v)))
          alist))

(defun arrow--load-data (file)
  "Load data from FILE, or nil if its not present.
Automatically migrates legacy character keys to strings."
  (when (and file (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((data (read (current-buffer))))
        (when (listp data)
          (arrow--migrate-keys data))))))


;;; key helpers

(defun arrow--key-conflicts-p (new-key alist)
  "Return the conflicting key if NEW-KEY violates the prefix-free rule in ALIST.
A conflict occurs when NEW-KEY is a prefix of an existing key or vice-versa.
Returns the conflicting key string, or nil if there is no conflict."
  (catch 'conflict
    (dolist (entry alist)
      (let ((existing (car entry)))
        (when (or (string-prefix-p new-key existing)
                  (string-prefix-p existing new-key))
          (throw 'conflict existing))))
    nil))

(defun arrow--find-free-key-in (alist)
  "Find the next available bookmark key in ALIST as a string.
Tries single characters (1-9 then a-z) first.  If every single char is
either taken or blocked by an existing 2-char prefix, then fall back to
2-character combinations (aa, ab, … zz)."
  (let* ((used-keys (mapcar #'car alist))
         (singles   (append
                     (mapcar #'char-to-string (number-sequence ?1 ?9))
                     (mapcar #'char-to-string (number-sequence ?a ?z)))))
    (or
     ;; single-char candidates
     (cl-find-if (lambda (k)
                   (and (not (member k used-keys))
                        (not (arrow--key-conflicts-p k alist))))
                 singles)
     ;; two-char fallback: aa, ab, … zz
     (catch 'found
       (dolist (a (number-sequence ?a ?z))
         (dolist (b (number-sequence ?a ?z))
           (let ((k (string a b)))
             (when (and (not (member k used-keys))
                        (not (arrow--key-conflicts-p k alist)))
               (throw 'found k)))))
       (user-error "No free bookmark keys available")))))


;;; interactive key-reading helpers

(defun arrow--read-bookmark-key (prompt &optional allow-auto)
  "Interactively read a 1-or-2 character bookmark key string.
with PROMPT shown to the user.
If ALLOW-AUTO is non-nil, pressing RET on the first character returns nil,
signalling to auto-assign a key via `arrow--find-free-key-in'."
  (let* ((event1 (read-key (format "%s (a-z/0-9%s): "
                                   prompt
                                   (if allow-auto ", RET=auto" ""))))
         (char1  (event-basic-type event1)))
    (cond
     ;; abort
     ((eq event1 ?\C-g)
      (keyboard-quit))
     ;; auto-assign requested
     ((and allow-auto (eq char1 ?\r))
      nil)
     ;; if invalid first character
     ((not (and (characterp char1)
                (or (and (>= char1 ?a) (<= char1 ?z))
                    (and (>= char1 ?0) (<= char1 ?9)))))
      (user-error "Please use a letter (a-z) or number (0-9)%s"
                  (if allow-auto ", or RET for auto" "")))
     (t
      ;; if valid first char -> offer second char or RET to confirm
      (let* ((s1     (char-to-string char1))
             (event2 (read-key
                      (format "[%s]: another a-z/0-9 for 2-char key or RET to confirm [%s]: "
                              s1 s1)))
             (char2  (event-basic-type event2)))
        (cond
         ((eq event2 ?\C-g)  (keyboard-quit))
         ;; single-char key confirmed
         ((eq char2  ?\r)    s1)
         ;; valid second char -> 2-char key
         ((and (characterp char2)
               (or (and (>= char2 ?a) (<= char2 ?z))
                   (and (>= char2 ?0) (<= char2 ?9))))
          (concat s1 (char-to-string char2)))
         (t
          (user-error "Second character must be a letter (a-z) or number (0-9)"))))))))

(defun arrow--read-existing-key (prompt alist)
  "Read a bookmark key that exists in ALIST, dealing with 1-or-2 char.
Shows PROMPT then waits for keypress.
If the first character is an exact match, return it immediately.
If it is a prefix of 2-char keys, prompt for a second character."
  (let* ((event1 (read-key prompt))
         (char1  (event-basic-type event1)))
    (when (eq event1 ?\C-g) (keyboard-quit))
    (unless (characterp char1)
      (user-error "Invalid key"))
    (let* ((s1          (char-to-string char1))
           (exact       (assoc s1 alist))
           (prefix-hits (cl-remove-if-not
                         (lambda (e) (string-prefix-p s1 (car e)))
                         alist)))
      (cond
       ;; immediate exact match
       (exact s1)
       ;; first char is prefix of 2-char keys so wait for second char
       (prefix-hits
        (let* ((event2 (read-key (format "[%s…]: " s1)))
               (char2  (event-basic-type event2)))
          (cond
           ((eq event2 ?\C-g) (keyboard-quit))
           ((eq char2  ?\r)   (user-error "Cancelled"))
           (t
            (let ((combined (concat s1 (char-to-string char2))))
              (if (assoc combined alist)
                  combined
                (user-error "No bookmark for key: %s" combined)))))))
       ;; no match at all
       (t (user-error "No bookmark for key: %s" s1))))))


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
  (let* ((parent      (selected-frame))
         (char-width  (or (frame-char-width  parent)  10))
         (char-height (or (frame-char-height parent) 20))
         (width-chars 75)
         (px-width    (* width-chars char-width))
         (content-lines (with-current-buffer buf
                          (count-lines (point-min) (point-max))))
         ;; cap height so the popup never overflows the parent frame
         (max-lines   (max 3 (- (/ (frame-pixel-height parent) char-height) 4)))
         (lines       (min (+ 2 content-lines) max-lines))
         (px-height   (* lines char-height))
         (left        (/ (- (frame-pixel-width  parent) px-width)  2))
         ;; clamp top, never go above the parent frame's top edge
         (top         (max 0 (/ (- (frame-pixel-height parent) px-height) 2)))
         (frame       (make-frame
                       `((parent-frame          . ,parent)
                         (minibuffer            . nil)
                         (undecorated           . t)
                         (internal-border-width . 3)
                         (tab-bar-lines         . 0) ;; supress tab-bar
                         (tool-bar-lines        . 0) ;; suppress tool-bar
                         (menu-bar-lines        . 0) ;; suppress menu-bar
                         (background-color      . ,(face-background 'tooltip nil t))
                         (width                 . ,width-chars)
                         (height                . ,lines)
                         (left                  . ,left)
                         (top                   . ,top)
                         (no-accept-focus       . t)))))
    (set-window-buffer (frame-root-window frame) buf)
    (set-window-start  (frame-root-window frame)
                       (with-current-buffer buf (point-min)))
    (set-window-dedicated-p (frame-root-window frame) t)
    (make-frame-visible frame)
    (setq arrow--popup-frame frame)))

(defvar arrow--shift-map
  '((?! . ?1) (?@ . ?2) (?# . ?3) (?$ . ?4) (?% . ?5)
    (?^ . ?6) (?& . ?7) (?* . ?8) (?\( . ?9) (?\) . ?0)
    (?_ . ?-) (?+ . ?=) (?{ . ?\[) (?} . ?\]) (?| . ?\\)
    (?: . ?\;) (?\" . ?') (?< . ?,) (?> . ?.) (?? . ?/))
  "Map of shifted symbols to their base keys for split-window detection.")

(defface arrow-legend-face
  '((t (:inherit shadow :slant italic :height 0.9)))
  "Face for the legend shown in the popup header-line."
  :group 'arrow-core)


;;; dynamic popup 1-or-2 char input with live filtering

(defun arrow--show-popup (title alist format-fn)
  "Popup with TITLE, ALIST of (key . value) pairs, and FORMAT-FN.
FORMAT-FN is called as (FORMAT-FN key value) for each entry.
Where keys in ALIST must be strings (1 or 2 characters).
The input loop supports instant jumping with no RET confirmation:
  - After the first keystroke the popup is filtered to show only entries
    that start with the typed character (or instant jump on match)
  - Window split Modifiers are captured on the first keypress:
Returns (SELECTION . MODIFIERS) where SELECTION is the matching alist entry
cons cell, or nil if the user cancelled or no match was found."
  (unless alist (user-error "No bookmarks to display"))
  (let ((buf    (get-buffer-create " *arrow-popup*"))
        (result nil))

    ;; render helper
    ;; Re-fill the BUF with CURRENT-ALIST and refreshes the popup display
    (cl-labels
        ((render (current-alist)
           (with-current-buffer buf
             (erase-buffer)
             (setq header-line-format
                   (concat
                    (propertize (format " %s " title) 'face 'bold)
                    (propertize " [Key] Jump | [C-Key] Split─ | [S-Key] Split│ | [q] Quit"
                                'face 'arrow-legend-face)))
             (setq mode-line-format               nil
                   cursor-type                    nil
                   cursor-in-non-selected-windows nil
                   truncate-lines                 t)
             (insert (string-join
                      (mapcar (lambda (bm)
                                (funcall format-fn (car bm) (cdr bm)))
                              current-alist)
                      "\n"))
             (goto-char (point-min)))
           (cond
            ((frame-live-p arrow--popup-frame)
             (set-window-start (frame-root-window arrow--popup-frame)
                               (with-current-buffer buf (point-min))))
            ((window-live-p arrow--popup-window)
             (set-window-start arrow--popup-window
                               (with-current-buffer buf (point-min)))))
           (redisplay t)))

      ;; initial render display
      (render alist)
      (if (display-graphic-p)
          (arrow--display-child-frame buf)
        (setq arrow--popup-window
              (display-buffer buf '((display-buffer-at-bottom)
                                    (window-height . fit-window-to-buffer)))))
      (redisplay t)

      ;; input loop
      (unwind-protect
          (let ((input-string "")
                (first-mods   nil)
                (done         nil))
            (while (not done)
              (let* ((prompt     (if (string-empty-p input-string)
                                     "Select: "
                                   (format "Select [%s…]: " input-string)))
                     (event      (read-key prompt))
                     (raw-key    (event-basic-type event))
                     (mods       (event-modifiers event))
                     ;; uppercase A-Z: shift + lowercase equivalent
                     (is-upper   (and (characterp raw-key)
                                      (not (eq raw-key (downcase raw-key)))))
                     ;; shifted symbol !@#…: base digit/punctuation
                     (shifted    (alist-get raw-key arrow--shift-map))
                     ;; normalised base key used for alist lookup
                     (base-key   (cond (is-upper (downcase raw-key))
                                       (shifted  shifted)
                                       (t        raw-key)))
                     (combo-mods (append mods
                                         (when (or is-upper shifted) '(shift)))))

                ;; record split modifiers from the very first keypress only
                (when (string-empty-p input-string)
                  (setq first-mods combo-mods))

                (cond
                 ((or (eq event ?\C-g) (eq event ?q)) ; quit
                  (message "Cancelled.")
                  (setq done t))

                 ;; printable character
                 ((characterp base-key)
                  (let* ((new-input   (concat input-string
                                              (char-to-string base-key)))
                         (exact       (assoc new-input alist))
                         (prefix-hits (cl-remove-if-not
                                       (lambda (e)
                                         (string-prefix-p new-input (car e)))
                                       alist)))
                    (setq input-string new-input)
                    (cond
                     ;; exact match: jump immediately
                     (exact
                      (setq result (cons exact first-mods))
                      (setq done t))

                     ;; abort if nothing matches
                     ((null prefix-hits)
                      (message "No bookmark for key: %s" input-string)
                      (setq done t))

                     ;; prefix matches on first char: filter popup and wait
                     ((= (length input-string) 1)
                      (render prefix-hits))
                     ;; 2 chars typed with no exact match: abort
                     (t
                      (message "No bookmark for key: %s" input-string)
                      (setq done t)))))

                 ;; also abort on non-character (F-keys, etc)
                 (t
                  (message "Invalid key.")
                  (setq done t))))))
        (arrow-close-popup)))
    result))


;;; reorder helpers

(defun arrow--reorder-alist (alist source-key target-key)
  "Return a new ALIST with SOURCE-KEY moved before TARGET-KEY.
If SOURCE-KEY equals TARGET-KEY, SOURCE-KEY is moved to the end of the list."
  (let* ((source-entry (assoc source-key alist))
         (rest         (assoc-delete-all source-key (copy-sequence alist))))
    (if (equal source-key target-key)
        ;; same key: move to end
        (append rest (list source-entry))
      ;; insert source-entry before target-key
      (let (result inserted)
        (dolist (entry rest)
          (when (and (not inserted) (equal (car entry) target-key))
            (push source-entry result)
            (setq inserted t))
          (push entry result))
        ;; if target not found, append at end
        (unless inserted (push source-entry result))
        (nreverse result)))))

(defun arrow--show-reorder-popup (title alist format-fn selected-key)
  "Show a two-step reorder popup over ALIST.
TITLE and FORMAT-FN work the same as in `arrow--show-popup'.
SELECTED-KEY is the bookmark being moved (nil in step 1)."
  (unless alist (user-error "No bookmarks to reorder"))
  (let ((buf (get-buffer-create " *arrow-popup*")))

    (with-current-buffer buf
      (erase-buffer)
      (setq header-line-format
            (concat
             (propertize (format " %s " title) 'face 'bold)
             (propertize
              (if selected-key
                  (format " Moving [%s]: insert BEFORE which? (same key = end) | [q] Cancel"
                          selected-key)
                " [Key] Select bookmark to MOVE | [q] Quit")
              'face 'arrow-legend-face)))
      (setq mode-line-format               nil
            cursor-type                    nil
            cursor-in-non-selected-windows nil
            truncate-lines                 t)
      (insert (string-join
               (mapcar (lambda (bm)
                         (let* ((is-sel (and selected-key
                                             (equal (car bm) selected-key)))
                                (line   (funcall format-fn (car bm) (cdr bm))))
                           (if is-sel
                               (propertize line 'face '(:weight bold :underline t))
                             line)))
                       alist)
               "\n"))
      (goto-char (point-min)))

    (if (display-graphic-p)
        (arrow--display-child-frame buf)
      (setq arrow--popup-window
            (display-buffer buf '((display-buffer-at-bottom)
                                  (window-height . fit-window-to-buffer)))))
    (redisplay t)

    (unwind-protect
        (let ((input-string "")
              (done         nil)
              (result       nil))
          (while (not done)
            (let* ((prompt  (if (string-empty-p input-string)
                                "Select: "
                              (format "Select [%s…]: " input-string)))
                   (event   (read-key prompt))
                   (raw-key (event-basic-type event)))
              (cond
               ((or (eq event ?\C-g) (eq event ?q))
                (message "Cancelled.")
                (setq done t))

               ((characterp raw-key)
                (let* ((new-input   (concat input-string
                                            (char-to-string raw-key)))
                       (exact       (assoc new-input alist))
                       (prefix-hits (cl-remove-if-not
                                     (lambda (e)
                                       (string-prefix-p new-input (car e)))
                                     alist)))
                  (setq input-string new-input)
                  (cond
                   (exact
                    (setq result new-input)
                    (setq done t))
                   ((null prefix-hits)
                    (message "No bookmark for key: %s" input-string)
                    (setq done t))
                   ;; still 1 char with prefix matches: wait for next char
                   ((= (length input-string) 1) nil)
                   (t
                    (message "No bookmark for key: %s" input-string)
                    (setq done t)))))

               (t
                (message "Invalid key.")
                (setq done t)))))
          result)
      (arrow-close-popup))))

(provide 'arrow-core)
;;; arrow-core.el ends here
