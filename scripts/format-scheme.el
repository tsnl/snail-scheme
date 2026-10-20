;;; format-scheme.el --- Batch Scheme indentation -*- lexical-binding: t; -*-

(require 'scheme)

(dolist (form '(struct enum typeclass instance effect match))
  (put form 'scheme-indent-function 1))
(put 'handle 'scheme-indent-function 2)

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

(defun snail-format-buffer ()
  "Separate declarations and indent Scheme using spaces and built-in rules."
  (scheme-mode)
  (setq-local indent-tabs-mode nil)
  (snail-format-declarations)
  (let ((inhibit-message t))
    (indent-region (point-min) (point-max))))

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
       (t (error "Usage: format-scheme [--write|--check FILE ...]")))
      (kill-emacs status))
  (error
   (princ (format "format-scheme: %s\n" (error-message-string err))
          #'external-debugging-output)
   (kill-emacs 2)))
