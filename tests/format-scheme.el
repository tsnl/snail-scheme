;;; format-scheme.el --- Formatter regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst snail-test-formatter
  (expand-file-name "../scripts/format-scheme"
                    (file-name-directory load-file-name)))

(defun snail-test-format (source &rest arguments)
  "Run the editor's stdin/stdout formatter on SOURCE, with ARGUMENTS."
  (with-temp-buffer
    (insert source)
    (should (= 0 (apply #'call-process-region (point-min) (point-max)
                        snail-test-formatter t t nil arguments)))
    (buffer-string)))

(defun snail-test-breaks (source expected)
  "Formatting SOURCE at 40 columns makes EXPECTED, which it then leaves alone.
tests/programs/format.sld holds (snail-core format) to the same cases."
  (should (equal expected (snail-test-format source "--width" "40")))
  (should (equal expected (snail-test-format expected "--width" "40"))))

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

(ert-deftest snail-format-breaks-binding-forms ()
  ;; A binding form puts each binding and each body form on its own line,
  ;; and a definition its body; a long header then breaks as a call does.
  (snail-test-breaks
   "(define (f x) (let* ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c)))
(define (make-thing alpha beta gamma delta) (list alpha beta))
"
   "(define (f x)
  (let* ((a (foo x))
         (b (bar a))
         (c (baz b)))
    (+ a b c)))
(define (make-thing alpha
                    beta
                    gamma
                    delta)
  (list alpha beta))
"))

(ert-deftest snail-format-breaks-calls ()
  ;; A call puts each argument after its first under the first. When only
  ;; the first is on the line, it goes under the call's name if it fits
  ;; there. A match arm puts its body under its pattern.
  (snail-test-breaks
   "(string-append \"first part\" (symbol->string name) \"last part\")
(error \"a message that is long enough to matter\")
(match option ((Some value) (display (string-append \"found \" value))) ((None) (display \"nothing\")))
"
   "(string-append \"first part\"
               (symbol->string name)
               \"last part\")
(error
 \"a message that is long enough to matter\")
(match option
  ((Some value)
   (display
    (string-append \"found \" value)))
  ((None) (display \"nothing\")))
"))

(ert-deftest snail-format-breaks-around-comments-and-strings ()
  ;; A comment after the code does not count toward the width and stays at
  ;; the end of its line; a string never breaks, so may stay too long.
  (snail-test-breaks
   "(foo alpha beta gamma delta epsilon) ; fits: the comment does not count
(foo alpha beta gamma delta epsilon zeta) ; stays on the last line
(define message \"a string much longer than forty columns cannot break\")
"
   "(foo alpha beta gamma delta epsilon) ; fits: the comment does not count
(foo alpha
     beta
     gamma
     delta
     epsilon
     zeta) ; stays on the last line
(define message
  \"a string much longer than forty columns cannot break\")
"))

(ert-deftest snail-format-breaks-between-tokens ()
  ;; A function type's effects stay together after its `!'; tokens written
  ;; without a space between them stay together; and forms that share a
  ;; line at the top level break apart.
  (snail-test-breaks
   "(: run (-> Config (List String) Status ! fs console))
(bytes #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
(display \"one\") (display \"two\") (display \"three\")
"
   "(: run
   (-> Config
       (List String)
       Status
       ! fs console))
(bytes
 #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
(display \"one\")
(display \"two\")
(display \"three\")
"))

(ert-deftest snail-format-width ()
  ;; Without --width, code may reach column 80 and no further.
  (let ((fits (concat "(list \"" (make-string 69 ?x) "\" b)\n"))
        (long (concat "(list \"" (make-string 70 ?x) "\" b)\n")))
    (should (= 81 (length fits)))
    (should (equal fits (snail-test-format fits)))
    (should (equal (concat "(list \"" (make-string 70 ?x) "\"\n      b)\n")
                   (snail-test-format long)))))
