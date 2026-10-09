(define-library (snail-scheme test-parser)
  (export
   test-parser)

  (import
   (scheme base)
   (only (snail-scheme common) char-alphabetic?)
   (snail-scheme reader)
   (snail-scheme parser)
   (snail-scheme test-utils))

  (begin
    (define (test-return-and-fail)
      (check-ok (return #f) "a" #f "a")
      (check-ok (ε) "" '())
      (check-ok (ε) "a" '() "a")
      (check-fail (fail) "a"))

    (define (test->>=)
      (check-ok (>>= (char #\a) (lambda (value) (return (string value)))) "ab" "a" "b")
      (check-ok (>>= (char #\a) (lambda (value) (char value))) "aa" #\a)
      (check-fail (>>= (fail) (lambda (_) (error "binder must not run"))) "a")
      (check-fail (>>= (char #\a) (lambda (_) (fail))) "ab" "b"))

    (define (test-chain)
      (check-ok (chain (ε)) "a" '() "a")
      (check-ok (chain (char #\a)) "ab" #\a "b")
      (check-ok (chain (char #\a) (lambda (_) (char #\b))) "ab" #\b)
      (check-ok (chain (char #\a) (lambda (value) (char value))) "aab" #\a "b")
      (check-fail (chain (fail) (lambda (_) (error "binder must not run"))) "a")
      (check-fail (chain (char #\a) (lambda (_) (char #\b))) "ac" "c"))

    (define (test-pmap)
      (check-ok (pmap (char #\a) string) "ab" "a" "b")
      (check-ok (pmap (return #f) not) "a" #t "a")
      (check-ok (pmap (char #\a) (lambda (_) #f)) "ab" #f "b")
      (check-ok (pmap (tuple (char #\a) (char #\b)) list->string) "ab" "ab")
      (check-fail (pmap (tag "ab") (lambda (_) (error "transform must not run"))) "ac" "c")
      (let ((calls '()))
        (check-ok (pmap (return #f) (lambda (value) (set! calls (cons value calls)) value))
                  "a" #f "a")
        (expect calls '(#f))))

    (define (test-combinator-failure-preservation)
      (let* ((reader (string->reader "failure.scm" "ab"))
             (failure (parse-result-err (next-reader reader)))
             (parser (lambda (_) failure))
             (unreachable (lambda (_) (error "must stop at the first failure"))))
        (expect (eq? ((pmap parser unreachable) reader) failure) #t)
        (expect (eq? ((tuple (char #\a) parser unreachable) reader) failure) #t)))

    (define (test-where)
      (check-ok (where (char #\a) char-alphabetic?) "ab" #\a "b")
      (check-ok (where (return #f) boolean?) "a" #f "a")
      (check-fail (where (char #\a) (lambda (_) #f)) "ab" "b")
      (check-fail (where (tag "ab") (lambda (_) (error "predicate must not run"))) "ac" "c")
      (check-ok
       (choice
        (where (char #\a) (lambda (_) #f))
        (tag "ab"))
       "abc" "ab" "c")
      (let ((calls 0))
        (check-ok
         (where (char #\a)
                (lambda (value)
                  (set! calls (+ calls 1))
                  (char? value)))
         "ab" #\a "b")
        (expect calls 1))
      (for-each
       (lambda (result)
         (expect
          (guard (ex ((error-object? ex) (error-object-message ex)))
            ((where (char #\a) (lambda (_) result)) (string->reader "where.scm" "a"))
            #f)
          "assertion failed"))
       (list (return #t) (fail) '() 1)))

    (define (test-char-if)
      (check-ok (char-if char-alphabetic?) "ab" #\a "b")
      (check-fail (char-if char-alphabetic?) "1")
      (check-fail (char-if (lambda (_) (error "predicate must not run at EOF"))) "")
      (check-ok (char-from '(#\a #\b)) "b" #\b)
      (check-fail (char-from '()) "a"))

    (define (test-lookahead)
      (check-ok (lookahead (char-if char-alphabetic?)) "ab" #\a "ab")
      (check-fail (lookahead (char-if char-alphabetic?)) "1")
      (check-fail (lookahead (char-if (lambda (_) (error "predicate must not run at EOF")))) "")
      (check-ok (lookahead (tag "ab")) "abc" "ab" "abc")
      (check-fail (lookahead (tag "ab")) "ac")
      (check-ok (tuple (lookahead (char #\a)) (char #\a)) "ab" '(#\a #\a) "b")
      (check-ok (lookahead (eof)) "" '()))

    (define (test-not-followed-by)
      (check-ok (not-followed-by (tag "ab")) "ac" '() "ac")
      (check-fail (not-followed-by (tag "ab")) "ab")
      (check-ok (not-followed-by (char #\a)) "" '())
      (check-fail (not-followed-by (eof)) "")
      (check-fail (not-followed-by (return #f)) "x"))

    (define (test-repeat)
      (check-ok (repeat (char #\a)) "aaab" '(#\a #\a #\a) "b")
      (check-ok (repeat (char #\a)) "b" '() "b")
      (check-ok (repeat (char #\a)) "" '())
      (check-ok (repeat (tag "ab")) "abac" '("ab") "ac")
      (for-each
       (lambda (parser)
         (expect
          (guard (ex ((error-object? ex) (error-object-message ex)))
            ((repeat parser) (string->reader "<test-repeat>" "")))
          "repeat: parser succeeded without consuming input"))
       (list (ε) (optional (char #\a)) (eof)
             (lookahead (eof)) (not-followed-by (char #\a)))))

    (define (test-repeat-at-least-once)
      (check-ok (repeat-at-least-once (char #\a)) "a" '(#\a))
      (check-ok (repeat-at-least-once (char #\a)) "aab" '(#\a #\a) "b")
      (check-ok (repeat-at-least-once (discard (char #\a))) "aa" '(() ()))
      (check-fail (repeat-at-least-once (char #\a)) "b")
      (check-fail (repeat-at-least-once (char #\a)) ""))

    (define (test-choice)
      (check-ok
       (choice
        (tag "ab")
        (tag "ac"))
       "ac" "ac")
      (check-ok
       (choice
        (tag "a")
        (tag "ab"))
       "ab" "a" "b")
      (check-fail
       (choice
        (tag "ab")
        (tag "ac"))
       "ad")
      (check-fail (choice) "a"))

    (define (test-discard)
      (check-ok (discard (char #\a)) "ab" '() "b")
      (check-fail (discard (char #\a)) "b"))

    (define (test-tuple)
      (check-ok (tuple) "a" '() "a")
      (check-ok (tuple (char #\a) (char #\b) (char #\c)) "abc" '(#\a #\b #\c))
      (check-fail (tuple (char #\a) (char #\b)) "ac" "c")
      (let ((parser (tuple (return #f) (ε) (char #\a))))
        (check-ok parser "ab" '(#f () #\a) "b")
        (check-fail parser "b")
        (check-ok parser "a" '(#f () #\a))))

    (define (test-tuple-reentrancy)
      (letrec ((parser
                (tuple
                 (lambda (reader)
                   (if (eqv? (peek-reader reader) #\a)
                       (check-ok parser "bc!" '(#\b #\c) "!"))
                   ((char-if char-alphabetic?) reader))
                 (char #\c))))
        (check-ok parser "ac?" '(#\a #\c) "?")))

    (define (test-named-tuple)
      (check-ok (named-tuple) "a" '() "a")
      (check-ok
       (named-tuple
        `(left . ,(char #\a))
        `(_ . ,(char #\:))
        `(right . ,(char #\b))
        `(_ . ,(char #\;)))
       "a:b;c" '((left . #\a) (right . #\b)) "c")
      (check-ok
       (named-tuple
        `(false . ,(return #f))
        `(empty . ,(ε)))
       "a" '((false . #f) (empty)) "a")
      (check-fail
       (named-tuple
        `(left . ,(char #\a))
        `(_ . ,(char #\:))
        `(right . ,(char #\b)))
       "ac" "c")
      (for-each
       (lambda (fields)
         (expect
          (guard (ex ((error-object? ex) (error-object-message ex)))
            (apply named-tuple fields)
            #f)
          "assertion failed"))
       (list (list 'x)
             (list (cons "x" (ε)))
             (list (cons 'x #f))
             (list (cons 'x (ε)) (cons 'x (ε))))))

    (define (test-optional)
      (check-ok (optional (char #\a)) "ab" #\a "b")
      (check-ok (optional (tag "ab")) "ac" '() "ac")
      (check-ok (optional (char #\a)) "" '()))

    (define (test-tag)
      (check-ok (tag "ab") "abc" "ab" "c")
      (check-ok (tag "") "a" "" "a")
      (check-ok (tag-ci "") "a" "" "a")
      (check-ok (tag-ci "Ab") "aBc" "aB" "c")
      (check-fail (tag-ci "ab") "Ac" "c")
      (check-ok (tag-val "a" #f) "a" #f)
      (check-fail (tag "ab") "ac" "c")
      (check-fail (tag "a") ""))

    (define (test-eof-and-location)
      (check-ok (eof) "" '())
      (check-fail (eof) "a")
      (check-ok (location) "a" (at 1 1) "a")
      (check-ok (chain (tag "a\n") (lambda (_) (location))) "a\nb" (at 2 1) "b"))

    (define (test-parser)
      (run-test test-return-and-fail)
      (run-test test->>=)
      (run-test test-chain)
      (run-test test-pmap)
      (run-test test-combinator-failure-preservation)
      (run-test test-where)
      (run-test test-char-if)
      (run-test test-lookahead)
      (run-test test-not-followed-by)
      (run-test test-repeat)
      (run-test test-repeat-at-least-once)
      (run-test test-choice)
      (run-test test-discard)
      (run-test test-tuple)
      (run-test test-tuple-reentrancy)
      (run-test test-named-tuple)
      (run-test test-optional)
      (run-test test-tag)
      (run-test test-eof-and-location))))
