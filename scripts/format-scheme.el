;;; format-scheme.el --- Batch Scheme indentation -*- lexical-binding: t; -*-

(require 'scheme)

(defun snail-format-buffer ()
  "Indent Scheme using spaces and Emacs's built-in form rules."
  (scheme-mode)
  (setq-local indent-tabs-mode nil)
  (let ((inhibit-message t))
    (indent-region (point-min) (point-max))))

(defun snail-format-file (file check)
  "Format FILE, or report whether it needs formatting when CHECK is non-nil."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((original (buffer-string)))
      (snail-format-buffer)
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
