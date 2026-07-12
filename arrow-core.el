;;; arrow-core.el --- Shared helpers for arrow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vmargb
;; Author: vmargb
;; Version: 1.1.1
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

(defcustom arrow-max-key-length 2
  "Maximum number of characters allowed in a bookmark key."
  :type '(choice (natnum :tag "Max length") (const :tag "No limit" nil))
  :group 'arrow-core)

;; popup state
(defvar arrow--popup-frame nil)
(defvar arrow--popup-window nil)

(defcustom arrow-popup-background-face 'tooltip
  "Most themes style the built-in `tooltip' to match their palette.
Some others leave it untouched, which makes the popup look wrong
point it at a different face, such as `mode-line-inactive' or `default'."
  :type 'face
  :group 'arrow-core)

(defface arrow-key-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for highlighting bookmark keys in the popup."
  :group 'arrow-core)

(defface arrow-legend-face
  '((t (:inherit shadow :slant italic :height 0.9)))
  "Face for the legend shown in the popup header-line."
  :group 'arrow-core)

(defvar arrow--shift-map
  '((?! . ?1) (?@ . ?2) (?# . ?3) (?$ . ?4) (?% . ?5)
    (?^ . ?6) (?& . ?7) (?* . ?8) (?\( . ?9) (?\) . ?0)
    (?_ . ?-) (?+ . ?=) (?{ . ?\[) (?} . ?\]) (?| . ?\\)
    (?: . ?\;) (?\" . ?') (?< . ?,) (?> . ?.) (?? . ?/))
  "Map of shifted symbols to their base keys for `split-window' detection.")

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

(defun arrow--alnum-char-p (char)
  "Return non-nil when CHAR is a lowercase letter or digit."
  (and (characterp char)
       (or (and (>= char ?a) (<= char ?z))
           (and (>= char ?0) (<= char ?9)))))

(defun arrow--return-event-p (event basic)
  "Return non-nil when EVENT/BASIC represent Return."
  (or (eq event ?\r) (eq event 'return)
      (eq basic ?\r) (eq basic 'return)))

(defun arrow--prompt-for-key (input legend)
  "Build the `read-key' echo-area prompt from LEGEND and the typed INPUT so far."
  (concat legend "  "
          (if (string-empty-p input)
              "Select: "
            (format "Select [%s…]: " input))))

(defun arrow--matching-prefixes (input alist)
  "Return entries in ALIST whose key begins with INPUT."
  (cl-remove-if-not (lambda (entry)
                      (string-prefix-p input (car entry)))
                    alist))

(defun arrow--key-conflicts-p (new-key alist)
  "Return the conflicting key if NEW-KEY violates the prefix-free rule in ALIST.
A conflict occurs when NEW-KEY is a prefix of an existing key or vice-versa."
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
either taken or blocked by an existing prefix, falls back to 2-character
combinations (aa, ab, … zz), and so on up to `arrow-max-key-length'"
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
       (let ((max-len (or arrow-max-key-length 2)))
         (cl-loop for len from 2 to max-len do
                  (let ((chars (number-sequence ?a ?z)))
                    (cl-labels ((gen (prefix remaining)
                                  (if (= remaining 0)
                                      (when (and (not (member prefix used-keys))
                                                 (not (arrow--key-conflicts-p prefix alist)))
                                        (throw 'found prefix))
                                    (dolist (c chars)
                                      (gen (concat prefix (char-to-string c))
                                           (1- remaining))))))
                      (dolist (c chars)
                        (gen (char-to-string c) (1- len)))))))
       (user-error "No free bookmark keys available (max key length: %s)"
                   (or arrow-max-key-length "∞"))))))

(defun arrow--read-bookmark-key (prompt &optional allow-auto)
  "Interactively read a bookmark PROMPT of any length.
Valid characters are a-z and 0-9.  Press RET to confirm the key.
If ALLOW-AUTO is non-nil and RET is pressed without typing anything,
return nil to signal auto-assignment via `arrow--find-free-key-in'."
  (let ((input ""))
    (catch 'done
      (while t
        (let* ((ev   (read-key (if (string-empty-p input)
                                   (format "%s (a-z/0-9%s): "
                                           prompt
                                           (if allow-auto ", RET=auto" ""))
                                 (format "Key [%s] (RET confirms, C-g aborts): " input))))
               (base (event-basic-type ev)))
          (cond
           ((eq ev ?\C-g) ; abort
            (keyboard-quit))
           ;; RET pressed check both raw event and basic type
           ;; to cover terminal vs GUI differences
           ((arrow--return-event-p ev base)
            (if (string-empty-p input)
                (if allow-auto
                    (throw 'done nil)     ; empty RET: signal auto-assign
                  (user-error "Please use a letter (a-z) or number (0-9)"))
              (throw 'done input)))       ; confirm accumulated string

           ((arrow--alnum-char-p base) ; valid alphanumeric
            (setq input (concat input (char-to-string base)))
            ;; auto-submit when max length is reached (no RET needed)
            (when (and arrow-max-key-length
                       (>= (length input) arrow-max-key-length))
              (throw 'done input)))

           ;; anything else
           (t
            (user-error "Please use a letter (a-z) or number (0-9)%s"
                        (if (and allow-auto (string-empty-p input))
                            ", or RET for auto"
                          "")))))))))

(defun arrow--read-existing-key (prompt alist)
  "Read a bookmark key that exists in ALIST.
Shows PROMPT then waits for keypress.
If the first character is an exact match, return it immediately.
otherwise keey prompting until RET confirms the full key."
  (let* ((event1 (read-key prompt))
         (char1  (event-basic-type event1)))
    (when (eq event1 ?\C-g) (keyboard-quit))
    (unless (characterp char1)
      (user-error "Invalid key"))
    (let* ((s1          (char-to-string char1))
           (exact       (assoc s1 alist))
           (prefix-hits (arrow--matching-prefixes s1 alist)))
      (cond
       ;; immediate exact match jump/delete right away
       (exact s1)
       ;; no match at all
       ((null prefix-hits)
        (user-error "No bookmark for key: %s" s1))
       ;; prefix matches: read more chars until RET confirms
       (t
        (catch 'done
          (let ((input s1))
            (while t
              (let* ((event (read-key (format "[%s…] (RET confirms, C-g aborts): " input)))
                     (char (event-basic-type event)))
                (cond
                 ((eq event ?\C-g)
                  (keyboard-quit))
                 ;; RET confirms check both raw event and basic type for GUI/terminal
                 ((arrow--return-event-p event char)
                  (if (assoc input alist)
                      (throw 'done input)
                    (user-error "No bookmark for key: %s" input)))
                 ;; accumulate valid a-z/0-9
                 ((arrow--alnum-char-p char)
                  (setq input (concat input (char-to-string char)))
                  ;; bail early if this matches nothing and isn't a prefix
                  (unless (or (assoc input alist)
                              (cl-some (lambda (e) (string-prefix-p input (car e))) alist))
                    (user-error "No bookmark for key: %s" input))
                  ;; auto-submit when max length is reached
                  (when (and arrow-max-key-length
                             (>= (length input) arrow-max-key-length))
                    (if (assoc input alist)
                        (throw 'done input)
                      (user-error "No bookmark for key: %s" input))))
                 ;; anything else
                 (t
                  (user-error "Invalid key"))))))))))))

;;; popup display helpers

(defun arrow-close-popup ()
  "Close the popup window/frame."
  (when (frame-live-p arrow--popup-frame)
    (delete-frame arrow--popup-frame)
    (setq arrow--popup-frame nil)
    ;; re-run after-make-frame-functions on the parent frame
    (when (display-graphic-p)
      (run-hook-with-args 'after-make-frame-functions (selected-frame))))
  (when (window-live-p arrow--popup-window)
    (delete-window arrow--popup-window)
    (setq arrow--popup-window nil)))

(defun arrow--popup-frame-geometry (buf parent)
  "Compute child-frame geometry for displaying BUF over PARENT.
Returns a plist (:width-chars W :lines L :left LEFT :top TOP)."
  (let* ((char-width  (or (frame-char-width  parent)  10))
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
         (top         (max 0 (/ (- (frame-pixel-height parent) px-height) 2))))
    (list :width-chars width-chars :lines lines :left left :top top)))

(defun arrow--display-child-frame (buf)
  "Display BUF in a centered child frame (GUI only)."
  (let* ((parent (selected-frame))
         (geo    (arrow--popup-frame-geometry buf parent))
         ;; suppress after-make-frame-functions for this transient frame
         ;; packages such as highlight-indent-guides register a hook there
         ;; that recomputes guide-face colours from the new frames background
         ;; because the popup uses the tooltip background (a different shade),
         ;; those faces end up globally overwritten with the wrong colours and
         ;; stay broken after the popup closes.
         (frame  (let ((after-make-frame-functions nil))
                   (make-frame
                    `((parent-frame          . ,parent)
                      (minibuffer            . nil)
                      (undecorated           . t)
                      (internal-border-width . 3)
                      (tab-bar-lines         . 0) ;; suppress tab-bar
                      (tool-bar-lines        . 0) ;; suppress tool-bar
                      (menu-bar-lines        . 0) ;; suppress menu-bar
                      (background-color      . ,(face-background arrow-popup-background-face nil t))
                      ;; geometry per group for different set of marks
                      (width                 . ,(plist-get geo :width-chars))
                      (height                . ,(plist-get geo :lines))
                      (left                  . ,(plist-get geo :left))
                      (top                   . ,(plist-get geo :top))
                      (no-accept-focus       . t))))))
    (set-window-buffer (frame-root-window frame) buf)
    (set-window-start  (frame-root-window frame)
                       (with-current-buffer buf (point-min)))
    (set-window-dedicated-p (frame-root-window frame) t)
    (make-frame-visible frame)
    (setq arrow--popup-frame frame)))

(defun arrow--resize-child-frame (buf)
  "Resize and re-center the popup child frame to fit BUF's content.
Used when a popup is re-rendered with different content after it was
first shown like switching sections or narrowing by prefix."
  (when (frame-live-p arrow--popup-frame)
    (let* ((parent (or (frame-parent arrow--popup-frame) (selected-frame)))
           (geo    (arrow--popup-frame-geometry buf parent)))
      (set-frame-height arrow--popup-frame (plist-get geo :lines))
      (set-frame-position arrow--popup-frame
                          (plist-get geo :left)
                          (plist-get geo :top)))))

(defun arrow--display-popup-buffer (buf)
  "Display BUF in the current popup presentation."
  (if (display-graphic-p)
      (arrow--display-child-frame buf)
    (setq arrow--popup-window
          (display-buffer buf '((display-buffer-at-bottom)
                                (window-height . fit-window-to-buffer)))))
  (redisplay t))

(defun arrow--popup-header-line (title)
  "Build the header line for TITLE."
  (if (text-property-not-all 0 (length title) 'face nil title)
      (format " %s " title)
    (propertize (format " %s " title) 'face 'bold)))

(defun arrow--popup-render (buf title lines)
  "Render TITLE and LINES into BUF and refresh the popup viewport.
Also re-renders the already-displayed popup frame to fit the new content"
  (with-current-buffer buf
    (erase-buffer)
    (setq header-line-format
          (arrow--popup-header-line title))
    (setq mode-line-format               nil
          cursor-type                    nil
          cursor-in-non-selected-windows nil
          truncate-lines                 t)
    (insert (string-join lines "\n"))
    (goto-char (point-min)))
  (cond
   ((frame-live-p arrow--popup-frame)
    (arrow--resize-child-frame buf)
    (set-window-start (frame-root-window arrow--popup-frame)
                      (with-current-buffer buf (point-min))))
   ((window-live-p arrow--popup-window)
    (fit-window-to-buffer arrow--popup-window)
    (set-window-start arrow--popup-window
                      (with-current-buffer buf (point-min)))))
  (redisplay t))

;;; dynamic popup 1-or-2 char input with live filtering

(defun arrow--show-popup (title alist format-fn)
  "Popup with TITLE, ALIST of (key . value) pairs, and FORMAT-FN.
FORMAT-FN is called as (FORMAT-FN key value) for each entry.
After the first keystroke the popup is filtered to show only entries
that start with the typed character (or instant jump on match)"
  (unless alist (user-error "No bookmarks to display"))
  (let ((buf    (get-buffer-create " *arrow-popup*"))
        (legend " [Key] Jump | [C-Key] Split─ | [S-Key] Split│ | [q] Quit")
        (result nil))

    ;; re-fill the BUF with CURRENT-ALIST and refreshes the popup display
    (cl-labels
        ((render (current-alist)
           (arrow--popup-render
            buf
            title
            (mapcar (lambda (bm)
                      (funcall format-fn (car bm) (cdr bm)))
                    current-alist))))

      ;; initial render display
      (render alist)
      (arrow--display-popup-buffer buf)

      ;; input loop
      (unwind-protect
          (let ((input-string "")
                (first-mods   nil)
                (done         nil))
            (while (not done)
              (let* ((prompt     (arrow--prompt-for-key input-string legend))
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
                         (prefix-hits (arrow--matching-prefixes new-input alist)))
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

                     ;; prefix matches: keep filtering and wait for more input
                     (t
                      (when (and arrow-max-key-length
                                 (>= (length input-string) arrow-max-key-length))
                        ;; at max length with only prefix hits and no exact: abort
                        (message "No bookmark for key: %s" input-string)
                        (setq done t))
                      (unless done (render prefix-hits))))))

                 ;; also abort on non-character (F-keys, etc)
                 (t
                  (message "Invalid key.")
                  (setq done t))))))
        (arrow-close-popup)))
    result))

;; =======================================================
;; unified multi-section popup (Tab/S-Tab cycle)

(defun arrow--multi-popup-tab-strip (sections idx)
  "Build a header tab-strip for SECTIONS with the section at IDX active."
  (string-join
   (cl-loop for section in sections
            for i from 0
            collect (let ((title (plist-get section :title)))
                      (if (= i idx)
                          (propertize (format "[%s]" title)
                                      'face '(:weight bold :underline t))
                        (propertize title 'face 'arrow-legend-face))))
   " "))

;; returns a plist (:section SECTION :selection (KEY . VALUE) :mods MODS)
(defun arrow--show-multi-popup (sections)
  "Tab-cycling popup over SECTIONS.
Each element of SECTIONS is a plist with :title, :alist, and :format-fn"
  (unless sections (user-error "No bookmarks to display"))
  (let* ((buf    (get-buffer-create " *arrow-popup*"))
         (legend " [Key] Jump | [Tab] Section | [C/S-Key] Split | [q] Quit")
         (n      (length sections))
         (idx    0)
         (result nil))

    (cl-labels
        ((current-section () (nth idx sections))
         (render (entries)
           (arrow--popup-render
            buf
            (arrow--multi-popup-tab-strip sections idx)
            (mapcar (lambda (bm)
                      (funcall (plist-get (current-section) :format-fn)
                               (car bm) (cdr bm)))
                    entries))))

      (render (plist-get (current-section) :alist))
      (arrow--display-popup-buffer buf)

      (unwind-protect
          (let ((input-string "")
                (first-mods   nil)
                (done         nil))
            (while (not done)
              (let* ((alist      (plist-get (current-section) :alist))
                     (prompt     (arrow--prompt-for-key input-string legend))
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

                ;; record split modifiers from the first keypress only
                (when (string-empty-p input-string)
                  (setq first-mods combo-mods))

                (cond
                 ((or (eq event ?\C-g) (eq event ?q)) ; quit
                  (message "Cancelled.")
                  (setq done t))

                 ;; next section: reset input and re-render that sections full list
                 ((memq event '(tab ?\t))
                  (setq idx (mod (1+ idx) n))
                  (setq input-string "")
                  (render (plist-get (current-section) :alist)))

                 ;; previous section
                 ((memq event '(backtab S-tab))
                  (setq idx (mod (1- idx) n))
                  (setq input-string "")
                  (render (plist-get (current-section) :alist)))

                 ;; printable character
                 ((characterp base-key)
                  (let* ((new-input   (concat input-string
                                              (char-to-string base-key)))
                         (exact       (assoc new-input alist))
                         (prefix-hits (arrow--matching-prefixes new-input alist)))
                    (setq input-string new-input)
                    (cond
                     ;; exact match jump immediately
                     (exact
                      (setq result (list :section   (current-section)
                                         :selection exact
                                         :mods      first-mods))
                      (setq done t))

                     ;; abort if nothing matches
                     ((null prefix-hits)
                      (message "No bookmark for key: %s" input-string)
                      (setq done t))

                     ;; prefix matches so keep filtering and wait for more input
                     (t
                      (when (and arrow-max-key-length
                                 (>= (length input-string) arrow-max-key-length))
                        ;; at max length with only prefix hits and no exact: abort
                        (message "No bookmark for key: %s" input-string)
                        (setq done t))
                      (unless done (render prefix-hits))))))

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
  (let ((buf    (get-buffer-create " *arrow-popup*"))
        (legend (if selected-key
                    (format " Moving [%s]: insert BEFORE which? (same key = end) | [q] Cancel"
                            selected-key)
                  " [Key] Select bookmark to MOVE | [q] Quit")))

    (arrow--popup-render
     buf
     title
     (mapcar (lambda (bm)
               (let* ((is-sel (and selected-key
                                   (equal (car bm) selected-key)))
                      (line   (funcall format-fn (car bm) (cdr bm))))
                 (if is-sel
                     (propertize line 'face '(:weight bold :underline t))
                   line)))
             alist))

    (arrow--display-popup-buffer buf)

    (unwind-protect
        (let ((input-string "")
              (done         nil)
              (result       nil))
          (while (not done)
            (let* ((prompt  (arrow--prompt-for-key input-string legend))
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
                       (prefix-hits (arrow--matching-prefixes new-input alist)))
                  (setq input-string new-input)
                  (cond
                   (exact
                    (setq result new-input)
                    (setq done t))
                   ((null prefix-hits)
                    (message "No bookmark for key: %s" input-string)
                    (setq done t))
                   ;; at max length with only prefix hits and no exact: abort
                   ((and arrow-max-key-length
                         (>= (length input-string) arrow-max-key-length))
                    (message "No bookmark for key: %s" input-string)
                    (setq done t))
                   ;; prefix matches: wait for next char
                   (t nil))))

               (t
                (message "Invalid key.")
                (setq done t)))))
          result)
      (arrow-close-popup))))

(provide 'arrow-core)
;;; arrow-core.el ends here
