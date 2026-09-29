(define (test-input-stream)
  (let*
    ((is (list->input-stream '(#\a #\newline #\b)))
      (fn (input-stream-filename is))
      (_ (expect is (make-input-stream fn '(#\a #\newline #\b) 1 1)))
      (_ (expect (peek-input-stream is) #\a))
      (is (next-input-stream is))
      (_ (expect is (make-input-stream fn '(#\newline #\b) 1 2)))
      (_ (expect (peek-input-stream is) #\newline))
      (is (next-input-stream is))
      (_ (expect is (make-input-stream fn '(#\b) 2 1)))
      (_ (expect (peek-input-stream is) #\b))
      (is (next-input-stream is))
      (_ (expect is (make-input-stream fn '() 2 2)))
      (_ (expect (peek-input-stream is) '())))
    '()))

;
; Parser combinator tests
;

(define (test->>=)
  (let*
    ((input-stream (string->input-stream "a"))

      (a (char #\a))
      (parse-result (a input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect #\a (parse-result-value parse-result)))

      (y (>>= a (lambda (v) (return (string v)))))
      (parse-result (y input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect "a" (parse-result-value parse-result))))
    '()))

(define (test-chain)
  (let*
    ((input-stream (string->input-stream "abc"))

      (abc
        (chain
          (lambda (_) (char #\a))
          (lambda (_) (char #\b))
          (lambda (_) (char #\c))))

      (parse-result (abc input-stream))
      (_ (assert (parse-result-ok? parse-result))))
    '()))

(define (test-char-if)
  (let*
    ( ; init input stream to "ab"
      (input-stream (string->input-stream "ab"))

      ; parse "a"
      (pc (char-if (lambda (v) (eqv? v #\a))))
      (pr (pc input-stream))
      (_ (assert (parse-result-success pr)))
      (_ (expect #\a (parse-result-value pr)))

      ; try parsing "a" again, will fail
      (input-stream (parse-result-input pr))
      (pr (pc input-stream))
      (_ (assert (not (parse-result-success pr))))
      (_ (expect '() (parse-result-value pr)))

      ; try parsing "b" now, with the input stream from the failed result.
      (input-stream (parse-result-input pr))
      (pc (char-if (lambda (v) (eqv? v #\b))))
      (pr (pc input-stream))
      (_ (assert (parse-result-success pr)))
      (_ (expect #\b (parse-result-value pr)))

      ; expect input stream input-stream at EOF
      (input-stream (parse-result-input pr))
      (_ (expect (peek-input-stream input-stream) '())))
    '()))

(define (test-repeat)
  (let*
    ( ; init input stream to "aaab"
      ; define pc as a single character parser
      (input-stream (string->input-stream "aaab"))

      ; parse "a" repeatedly with repeat
      (a (repeat (char #\a)))
      (parse-result (a input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect '(#\a #\a #\a) (parse-result-value parse-result)))

      ; parse "a" again should succeed with length 0
      (input-stream (parse-result-input parse-result))
      (parse-result (a input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect '() (parse-result-value parse-result)))

      ; parse "a" again with repeat-at-least-once should fail
      (parse-result ((repeat-at-least-once (char #\a)) input-stream))
      (_ (assert (parse-result-err? parse-result)))

      ; parse "b" with repeat should succeed with length 1
      (input-stream (parse-result-input parse-result))
      (parse-result ((repeat (char #\b)) input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect '(#\b) (parse-result-value parse-result))))
    '()))

(define (test-discard)
  (let*
    ((input-stream (string->input-stream "a"))

      ; the parser `a := (char #\a)` should return value `#\a`
      (a (char #\a))
      (parse-result (a input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect #\a (parse-result-value parse-result)))
      (_ (assert (input-stream-eof? (parse-result-input parse-result))))

      ; the parser `d := (discard a)` should return value `'()`
      ; even though the post-input-stream should be empty
      (d (discard a))
      (parse-result (d input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (assert (null? (parse-result-value parse-result))))
      (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
    '()))

(define (test-tuple)
  (let*
    ((input-stream (string->input-stream "abcd"))

      (abcd (tuple (char #\a) (char #\b) (char #\c) (char #\d)))
      (parse-result (abcd input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect '(#\a #\b #\c #\d) (parse-result-value parse-result)))
      (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
    '()))

(define (test-optional)
  (let*
    ((input-stream (string->input-stream "a"))

      (aa (tuple (char #\a) (optional (char #\a))))
      (parse-result (aa input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect '(#\a ()) (parse-result-value parse-result)))
      (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
    '()))

(define (test-tag)
  (let*
    ((input-stream (string->input-stream "abc"))

      (abc (tag "abc"))
      (parse-result (abc input-stream))
      (_ (assert (parse-result-ok? parse-result)))
      (_ (expect "abc" (parse-result-value parse-result)))
      (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
    '()))

; Language parser tests

; TODO

(define (test-parser)
  (run-test test-input-stream)
  (run-test test->>=)
  (run-test test-chain)
  (run-test test-char-if)
  (run-test test-repeat)
  (run-test test-discard)
  (run-test test-tuple)
  (run-test test-optional)
  (run-test test-tag))
