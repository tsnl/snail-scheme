;; Prepare the profiling command's private loader view.
(import
 (scheme base)
 (scheme process-context)
 (lofi compiler profile))
(define arguments (cdr (command-line)))
(unless (= (length arguments) 2)
  (error "usage: instrument-compiler.scm REPOSITORY OVERLAY"))
(instrument-compiler (car arguments) (cadr arguments))
