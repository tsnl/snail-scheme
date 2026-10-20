;;; format-scheme.el --- Formatter regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst snail-test-formatter
  (expand-file-name "../scripts/format-scheme"
                    (file-name-directory load-file-name)))

(defun snail-test-format (source)
  "Run the editor's stdin/stdout formatter on SOURCE."
  (with-temp-buffer
    (insert source)
    (should (= 0 (call-process-region (point-min) (point-max)
                                     snail-test-formatter t t)))
    (buffer-string)))

(ert-deftest snail-format-declarations ()
  (let ((source "(import (scheme base) (rename (rnrs) (define-record-type record)))
(define-record-type <pair>
  (pair a b) pair? (a pair-a) (b pair-b))
(struct (Pair A) ((first A) (second A)))
(enum Shape (Circle ((radius I64))) (Dot))
")
        (expected "(import
 (scheme base)
 (rename (rnrs) (define-record-type record)))
(define-record-type <pair>
  (pair a b) pair?
  (a pair-a)
  (b pair-b))
(struct (Pair A)
  ((first A)
   (second A)))
(enum Shape (Circle ((radius I64))) (Dot))
"))
    (should (equal expected (snail-test-format source)))
    (should (equal expected (snail-test-format expected)))))

(ert-deftest snail-format-preserves-literals-and-comments ()
  (let ((source ";; (import (ignored) (ignored))
#| outer (import (ignored) (ignored)) #| nested |# |#
#;(import (ignored) (ignored))
(define chars '(#\\( #\\) #\\; #\\\"))
(define |name(import (a) (b))| 1)
(define text \"first
  (import (ignored) (ignored))
last\")
"))
    (should (equal source (snail-test-format source))))
  (should (equal "(import
 (a) ; Keep this trailing comment.
 #| Keep this block comment. |#
 (b))
"
                 (snail-test-format "(import (a) ; Keep this trailing comment.
        #| Keep this block comment. |# (b))
"))))

(ert-deftest snail-format-unfinished-import ()
  (should (equal "(import
 (a)
 (b)
" (snail-test-format "(import (a) (b)
"))))

(ert-deftest snail-format-check-and-write ()
  (let ((file (make-temp-file "snail-format-" nil ".sld"))
        (source "(import (a) (b))\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert source))
          (should (= 1 (call-process snail-test-formatter nil nil nil "--check" file)))
          (should (equal source (with-temp-buffer
                                  (insert-file-contents file)
                                  (buffer-string))))
          (should (= 0 (call-process snail-test-formatter nil nil nil "--write" file)))
          (should (= 0 (call-process snail-test-formatter nil nil nil "--check" file)))
          (should (equal (snail-test-format source)
                         (with-temp-buffer
                           (insert-file-contents file)
                           (buffer-string)))))
      (delete-file file))))
