;;; format-scheme.el --- Batch Scheme formatting -*- lexical-binding: t; -*-

(require 'scheme)
(require 'seq)
(require 'cl-lib)

(dolist (form '(fn struct enum typeclass instance effect match))
  (put form 'scheme-indent-function 1))
(put 'handle 'scheme-indent-function 2)
;; Emacs 31 indents `guard' this way; older versions treat it as a call.
(put 'guard 'scheme-indent-function 1)

(defun snail-format-entries (header-length)
  "Put each list entry after HEADER-LENGTH elements on its own line."
  (save-excursion
    (forward-char)
    (dotimes (_ header-length)
      (forward-comment (point-max))
      (forward-sexp))
    (forward-comment (point-max))
    (while (eq (char-after) ?\()
      (unless (save-excursion (skip-chars-backward " \t") (bolp))
        (delete-horizontal-space)
        (insert "\n"))
      (forward-sexp)
      (forward-comment (point-max)))))

(defun snail-format-line-break ()
  "Start a new line at point unless it already begins one."
  (unless (save-excursion (skip-chars-backward " \t") (bolp))
    (delete-horizontal-space)
    (insert "\n")))

(defun snail-format-struct ()
  "Put the field list of the struct at point on its own line, one field per line."
  (save-excursion
    (down-list)
    (forward-sexp 2)
    (forward-comment (point-max))
    (when (eq (char-after) ?\()
      (snail-format-line-break)
      (down-list)
      (forward-comment (point-max))
      (when (eq (char-after) ?\()
        (forward-sexp)
        (forward-comment (point-max))
        (while (eq (char-after) ?\()
          (snail-format-line-break)
          (forward-sexp)
          (forward-comment (point-max)))))))

(defun snail-format-declarations ()
  "Separate import specifications and struct fields, preserving comments."
  (goto-char (point-min))
  (while (re-search-forward
          "(\\(import\\|define-record-type\\|struct\\)\\_>"
          nil t)
    (let ((form (match-string 1))
          (start (match-beginning 0))
          (state (save-excursion (syntax-ppss (match-beginning 0)))))
      (unless (or (nth 3 state) (nth 4 state))
        (condition-case nil
            (progn
              (save-excursion
                (goto-char start)
                (cond
                 ((equal form "import") (snail-format-entries 1))
                 ((equal form "define-record-type") (snail-format-entries 4))
                 ((equal form "struct") (snail-format-struct))))
              ;; Import specs are data: (define-record-type alias) is a rename.
              (when (equal form "import")
                (goto-char start)
                (forward-sexp)))
          ;; An unfinished import owns the remaining buffer, including renames.
          (scan-error (when (equal form "import") (goto-char (point-max)))))))))

;;; Long lines

(defvar snail-format-width 100
  "The column a line's code may reach.
A line whose code, not counting a comment after it, runs past this column
is broken until it fits or nothing on it can break.")

(defconst snail-format-binding-forms
  '(("let*" . 1) ("letrec" . 1) ("letrec*" . 1) ("let-values" . 1)
    ("let*-values" . 1) ("parameterize" . 1) ("do" . 1) ("handle" . 2)
    ("learning" . 2) ("expanding" . 2) ("naming" . 2) ("specializing" . 2))
  "Binding forms besides `let', with the element each keeps its bindings in,
counting the form's name as element 0. The body follows the bindings.")

(defun snail-format-shape (open)
  "How the list whose parenthesis is at OPEN breaks, as its first element says.
A call, (call), breaks before each argument after its first, or before its
first when no other is on the line; (body FROM) breaks before each element
from FROM on; (binding BINDINGS) breaks before each element after its list
of bindings at BINDINGS, and before each binding after the first. Which a
name is follows the rule `scheme-indent-function' finds for it: a special
form keeps only its first distinguished argument beside its name, and a
definition its first."
  (save-excursion
    (goto-char (1+ open))
    (forward-comment (buffer-size))
    (skip-syntax-forward "'")
    (if (not (looking-at "\\sw\\|\\s_"))
        '(body 1)
      (let* ((name (buffer-substring (point) (progn (forward-sexp) (point))))
             (method (get (intern-soft name) 'scheme-indent-function))
             (binding (assoc name snail-format-binding-forms)))
        (cond (binding (list 'binding (cdr binding)))
              ((eq method 'scheme-let-indent)
               ;; A named let, as `scheme-let-indent' recognizes one.
               (skip-chars-forward " \t")
               (if (looking-at "[-a-zA-Z0-9+*/?!@$%^&_:~]")
                   '(binding 2)
                 '(binding 1)))
              ((or (eq method 'defun)
                   (and (null method)
                        (> (length name) 3)
                        (string-match "\\`def" name)))
               '(body 2))
              ((integerp method) (list 'body (min (1+ method) 2)))
              (t '(call)))))))

;; What breaking needs to know of a line: where it starts, where its code
;; starts and ends, a comment after the code not counting, and each
;; expression that starts on it.
(cl-defstruct (snail-format-line (:constructor snail-format-line-make))
  bol first end elements)

(defun snail-format-elements (state end)
  "The expressions that start between point and END, which starts in STATE.
Each is (START OPEN DEPTH PARENT), from left to right: where it starts,
counting a prefix such as a quote; its parenthesis if it is a list; and the
depth and parenthesis of the list it is an element of."
  (let (elements)
    (while (progn (setq state (parse-partial-sexp (point) end nil t state))
                  (< (point) end))
      (let ((open (and (looking-at "\\s(") (point))))
        (push (list (save-excursion (backward-prefix-chars) (point))
                    open (nth 0 state) (nth 1 state))
              elements)
        (setq state (parse-partial-sexp
                     (point)
                     (if open
                         (1+ open)
                       (min end (condition-case nil
                                    (save-excursion (forward-sexp) (point))
                                  (scan-error end))))
                     nil nil state))))
    (nreverse elements)))

(defun snail-format-code-end (state)
  "Where the current line's code ends, the line starting in STATE.
A comment after the code, and the spaces before it, do not count."
  (save-excursion
    (let* ((bol (line-beginning-position))
           (end (parse-partial-sexp bol (line-end-position) nil nil state)))
      (unless (nth 3 end)
        (when (nth 4 end) (goto-char (nth 8 end)))
        (while (and (> (point) bol) (forward-comment -1))))
      (max bol (point)))))

(defun snail-format-read-line (state)
  "The current line as breaking sees it, the line starting in STATE."
  (save-excursion
    (let ((bol (line-beginning-position)))
      (syntax-propertize (line-end-position))
      (snail-format-line-make
       :bol bol
       :first (progn (goto-char bol) (forward-comment (buffer-size)) (point))
       :end (snail-format-code-end state)
       :elements (progn (goto-char bol)
                        (snail-format-elements state (line-end-position)))))))

(defun snail-format-children (open line)
  "The elements on LINE of the list at OPEN, each as (INDEX . ELEMENT).
OPEN is 0 for the top level. A list that opened above the line, as the top
level did, has its head behind it, so its elements count from 1."
  (let ((index (if (< open (snail-format-line-bol line)) 1 0)))
    (mapcar (lambda (element)
              (prog1 (cons index element) (setq index (1+ index))))
            (seq-filter (lambda (element) (eql (or (nth 3 element) 0) open))
                        (snail-format-line-elements line)))))

(defun snail-format-breakable-p (start line)
  "Whether LINE can break before START: not at its first token, and only
where spaces are, so that tokens written together stay together."
  (and (/= start (snail-format-line-first line))
       (memq (char-before start) '(?\s ?\t))))

(defun snail-format-moved-fits (head start line)
  "Whether the rest of LINE from START fits on a line of its own under HEAD."
  (<= (+ (- head (snail-format-line-bol line))
         (- (snail-format-line-end line) start))
      snail-format-width))

(defun snail-format-list-breaks (open line)
  "Where the list at OPEN breaks LINE: (DEPTH OPEN BREAKS FALLBACK ABSORBED).
BREAKS are the starts its shape breaks before. FALLBACK is a call's first
argument, as (START . FITS), which breaks only when nothing else does;
FITS says whether what it moves then fits under the call's name. A binding
form also breaks before each binding after the first, when it opens on the
line; ABSORBED is the parenthesis of its bindings. A list that opened above
the line breaks before each element. Nothing breaks after a `!' on the
line: the effects a function type lists after it stay together."
  (let ((shape (if (< open (snail-format-line-bol line))
                   '(body 1)
                 (snail-format-shape open)))
        depth head effects breaks fallback absorbed)
    (dolist (child (snail-format-children open line))
      (let ((index (car child)) (start (nth 1 child)) (list (nth 2 child)))
        (setq depth (nth 3 child))
        (cond ((= index 0) (setq head start))
              ((or (not (snail-format-breakable-p start line)) effects))
              ((and (eq (car shape) 'binding) (= index (nth 1 shape)) list)
               (setq absorbed list)
               (dolist (binding (cdr (snail-format-children list line)))
                 (when (snail-format-breakable-p (nth 1 binding) line)
                   (push (nth 1 binding) breaks))))
              ((>= index (pcase shape
                           (`(call) 2)
                           (`(body ,from) from)
                           (`(binding ,bindings) (1+ bindings))))
               (push start breaks))
              ((and (eq (car shape) 'call) (= index 1) head)
               (setq fallback
                     (cons start (snail-format-moved-fits head start line)))))
        (when (save-excursion (goto-char start) (looking-at "!\\_>"))
          (setq effects t))))
    (list depth open (sort breaks #'<) fallback absorbed)))

(defun snail-format-outermost (candidates eligible)
  "The outermost of CANDIDATES that ELIGIBLE accepts, the leftmost of those
equally deep."
  (let (best)
    (dolist (candidate candidates best)
      (when (and (funcall eligible candidate)
                 (or (null best)
                     (< (car candidate) (car best))
                     (and (= (car candidate) (car best))
                          (< (nth 1 candidate) (nth 1 best)))))
        (setq best candidate)))))

(defun snail-format-candidates (line)
  "Where each list could break LINE, as `snail-format-list-breaks' says.
Every list with an element after the line's first token has an entry, and
so does the top level, as a list at depth 0, except a binding form's list
of bindings, whose breaks are the binding form's."
  (let* ((first (snail-format-line-first line))
         (lists (delete-dups
                 (delq nil (mapcar (lambda (element)
                                     (and (/= (car element) first)
                                          (or (nth 3 element) 0)))
                                   (snail-format-line-elements line)))))
         (all (mapcar (lambda (open) (snail-format-list-breaks open line))
                      lists))
         (absorbed (delq nil (mapcar (lambda (candidate) (nth 4 candidate))
                                     all))))
    (seq-remove (lambda (candidate) (memql (nth 1 candidate) absorbed)) all)))

(defun snail-format-breaks (line)
  "Where to break LINE, or nil.
The outermost list that can break does, unless the only break it has is a
call's first argument whose move would not fit; that breaks only when
nothing else on the line can."
  (let* ((candidates (snail-format-candidates line))
         (best (snail-format-outermost candidates
                                       (lambda (candidate)
                                         (or (nth 2 candidate)
                                             (cdr (nth 3 candidate))))))
         (last (snail-format-outermost candidates
                                       (lambda (candidate) (nth 3 candidate)))))
    (cond ((nth 2 best))
          (best (list (car (nth 3 best))))
          (last (list (car (nth 3 last)))))))

(defun snail-format-break (state)
  "Break the current line, which starts in STATE, until its code fits within
`snail-format-width' or no list on it can break. Each break removes the
spaces before it; the lines it makes are indented as they are reached."
  (unless (or (nth 3 state) (nth 4 state))
    (let ((line (snail-format-read-line state))
          breaks)
      (while (and (> (- (snail-format-line-end line)
                        (snail-format-line-bol line))
                     snail-format-width)
                  (setq breaks (snail-format-breaks line)))
        (dolist (position (reverse breaks))
          (goto-char position)
          (delete-horizontal-space)
          (insert "\n"))
        (goto-char (snail-format-line-bol line))
        (setq line (snail-format-read-line state))))))

(defun snail-format-lines ()
  "Indent each line as `indent-region' does, then break it if it is long.
A line's indentation depends only on the text above it and its own first
token, so breaking a line before going on to the next leaves every line as
indenting the whole result would."
  (goto-char (point-min))
  (while (< (point) (point-max))
    (unless (and (bolp) (eolp))
      (indent-according-to-mode t)
      (snail-format-break (syntax-ppss (line-beginning-position))))
    (forward-line 1)))

(defun snail-format-buffer ()
  "Separate declarations, then indent Scheme with spaces and built-in rules,
breaking each line that runs past `snail-format-width'."
  (scheme-mode)
  (setq-local indent-tabs-mode nil)
  (snail-format-declarations)
  (let ((inhibit-message t))
    (snail-format-lines)))

(defun snail-format-file (file check)
  "Format FILE, or report whether it needs formatting when CHECK is non-nil."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((original (buffer-string)))
      (condition-case err
          (snail-format-buffer)
        (error (error "%s: %s" file (error-message-string err))))
      (unless (equal original (buffer-string))
        (if check
            (princ (format "%s: needs formatting\n" file)
                   #'external-debugging-output)
          (write-region (point-min) (point-max) file nil 'silent))
        t))))

(condition-case err
    (let ((args command-line-args-left)
          (status 0))
      (setq command-line-args-left nil)
      (when (equal (car args) "--width")
        (setq snail-format-width (string-to-number (or (cadr args) "")))
        (unless (> snail-format-width 0)
          (error "--width takes a positive number of columns"))
        (setq args (cddr args)))
      (cond
       ((null args)
        ;; Zed supplies the buffer on stdin and expects only source on stdout.
        (with-temp-buffer
          (insert-file-contents "/dev/stdin")
          (snail-format-buffer)
          (let ((coding-system-for-write 'utf-8-unix))
            (princ (buffer-string)))))
       ((and (member (car args) '("--write" "--check")) (cdr args))
        (let ((check (equal (car args) "--check")))
          (dolist (file (cdr args))
            (when (and (snail-format-file file check) check)
              (setq status 1)))))
       (t (error (concat "Usage: format-scheme [--width COLUMNS]"
                         " [--write|--check FILE ...]"))))
      (kill-emacs status))
  (error
   (princ (format "format-scheme: %s\n" (error-message-string err))
          #'external-debugging-output)
   (kill-emacs 2)))
