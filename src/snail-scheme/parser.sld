(define-library (snail-scheme parser)
  (export

   ;; ---- Results ----

   <parse-result>
   make-parse-result
   parse-result?
   parse-result-success
   parse-result-value
   parse-result-input
   parse-result-ok
   parse-result-err
   parse-result-ok?
   parse-result-err?

   ;; ---- Combinators and primitive parsers ----

   return
   ε
   fail
   >>=
   chain
   pmap
   where
   char-if
   lookahead
   not-followed-by
   char
   char-from
   tag
   tag-ci
   tag-val
   choice
   repeat
   repeat-at-least-once
   discard
   tuple
   named-tuple
   optional
   eof
   location)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme reader))

  (begin

    ;; ---- Parse results ----

    ;; Do not confuse with (Parser T):
    ;; Parser T := (Reader) -> (ParseResult T)

    (define-record-type <parse-result>
      (make-parse-result
       success ; whether the parse succeeded
       value ; value payload if success, null if failure
       input) ; reader post-parse
      parse-result?
      (success parse-result-success)
      (value parse-result-value)
      (input parse-result-input))

    (define (parse-result-ok value input)
      (make-parse-result #t value input))

    (define (parse-result-err input)
      (make-parse-result #f '() input))

    (define (parse-result-ok? x)
      (and (parse-result? x) (parse-result-success x)))

    (define (parse-result-err? x)
      (and (parse-result? x) (not (parse-result-success x))))

    ;; ---- Basic combinators ----

    ;; Parser T := (Reader) -> (ParseResult T)
    ;; IMPORTANT: the monadic type is (Parser T), NOT (ParseResult T).

    ;; Run the initial parser, then pass each successful value to the next binder.
    ;; With no binders, return the initial parser unchanged.
    (define (chain parser . binders)
      (let recur ((binders binders) (parser parser))
        (if (null? binders)
            parser
            (recur (cdr binders) (>>= parser (car binders))))))

    ;; monadic return operator for (Parser T)
    ;;   return :: (T) -> Parser T
    (define (return value)
      (lambda (reader)
        (parse-result-ok value reader)))

    ;; The empty sequence succeeds without consuming input.
    (define (ε) (return '()))

    ;; monadic return operator (fail variant) for (Parser T)
    ;;   fail :: () -> Parser T
    (define (fail)
      (lambda (reader)
        (parse-result-err reader)))

    ;; monadic bind operator for (Parser T)
    ;;   >>= :: (Parser T, ((T) -> Parser U)) -> Parser U
    (define (>>= parser binder)
      (lambda (reader)
        (let ((parse-result (parser reader)))
          (if (parse-result-err? parse-result)
              parse-result
              (let* ((value (parse-result-value parse-result))
                     (input (parse-result-input parse-result))
                     (parser (binder value)))
                (parser input))))))

    ;; Transform a parser's value without changing consumption or failure.
    ;; Parser value mapping: (pmap parser transform).
    (define (pmap parser transform)
      (lambda (reader)
        (let ((result (parser reader)))
          (if (parse-result-err? result)
              result
              (parse-result-ok (transform (parse-result-value result))
                               (parse-result-input result))))))

    ;; Keep a successful value only when the boolean predicate returns #t.
    ;; Rejection fails at the reader position after parsing that value.
    (define (where parser predicate)
      (chain parser
             (lambda (value)
               (let ((accepted? (predicate value)))
                 (assert (boolean? accepted?))
                 (if accepted? (return value) (fail))))))

    ;; ---- Primitive parsers ----

    (define (char-if predicate)
      (lambda (reader)
        (let ((peek (peek-reader reader)))
          (if (and (not (null? peek)) (predicate peek))
              (parse-result-ok peek (next-reader reader))
              (parse-result-err reader)))))

    ;; PEG &p: preserve the value, but never consume input, even on failure.
    (define (lookahead parser)
      (lambda (reader)
        (let ((result (parser reader)))
          (if (parse-result-ok? result)
              (parse-result-ok (parse-result-value result) reader)
              (parse-result-err reader)))))

    ;; PEG !p: succeed exactly when p fails, without consuming input.
    (define (not-followed-by parser)
      (lambda (reader)
        (if (parse-result-err? (parser reader))
            (parse-result-ok '() reader)
            (parse-result-err reader))))

    (define (repeat parser)
      (lambda (reader)
        (let recur ((reader reader)
                    (acc '()))
          (let ((parse-result (parser reader)))
            (if (parse-result-ok? parse-result)
                (let ((next-input (parse-result-input parse-result)))
                  ;; A nullable parser here is a programming error, not a parse failure.
                  (if (and (= (reader-line reader) (reader-line next-input))
                           (= (reader-column reader) (reader-column next-input)))
                      (error "repeat: parser succeeded without consuming input")
                      (recur next-input (cons (parse-result-value parse-result) acc))))
                (parse-result-ok (reverse acc) reader))))))

    (define (choice . parsers)
      (lambda (reader)
        (let recur ((reader reader)
                    (parsers parsers))
          (if (null? parsers)
              (parse-result-err reader)
              (let ((parse-result ((car parsers) reader)))
                (if (parse-result-ok? parse-result)
                    parse-result
                    (recur reader (cdr parsers))))))))

    (define (eof)
      (lambda (reader)
        (if (reader-eof? reader)
            (parse-result-ok '() reader)
            (parse-result-err reader))))

    (define (location)
      (lambda (reader)
        (parse-result-ok (reader-loc reader) reader)))

    ;; ---- Composed parsers ----

    (define (char chr)
      (assert (char? chr))
      (char-if (lambda (c) (eqv? c chr))))

    (define (tag str)
      (tag-val str str))

    (define (tag-ci str)
      (pmap (apply tuple
                   (map (lambda (chr) (char-if (lambda (c) (char-ci=? c chr))))
                        (string->list str)))
            list->string))

    (define (tag-val str val)
      (pmap (apply tuple (map char (string->list str)))
            (lambda (_) val)))

    (define (char-from lst)
      (char-if (lambda (c) (member c lst))))

    (define (repeat-at-least-once parser)
      (where (repeat parser) pair?))

    (define (discard parser)
      (pmap parser (lambda (_) '())))

    (define (tuple . parsers)
      (lambda (reader)
        (let loop ((parsers parsers) (reader reader) (reversed-values '()))
          (if (null? parsers)
              (parse-result-ok (reverse reversed-values) reader)
              (let ((result ((car parsers) reader)))
                (if (parse-result-err? result)
                    result
                    (loop (cdr parsers) (parse-result-input result)
                          (cons (parse-result-value result) reversed-values))))))))

    ;; Fields are (symbol . parser) pairs. `_` runs its parser but omits its value.
    (define (named-tuple . fields)
      (let validate ((fields fields) (keys '()))
        (if (pair? fields)
            (let ((field (car fields)))
              (assert (and (pair? field) (symbol? (car field)) (procedure? (cdr field))))
              (assert (or (eq? (car field) '_) (not (memq (car field) keys))))
              (validate (cdr fields) (cons (car field) keys)))))
      ;; As with the former pmap callbacks, capture each parser now but read its
      ;; field name after it succeeds. No caller-owned list is modified.
      (let ((captured (map (lambda (field) (cons field (cdr field))) fields)))
        (lambda (reader) (parse-named-fields captured reader '()))))

    (define (parse-named-fields fields reader reversed-fields)
      (if (null? fields) (parse-result-ok (reverse reversed-fields) reader)
          (let* ((field (car fields)) (result ((cdr field) reader)))
            (if (parse-result-err? result) result
                (parse-named-fields
                 (cdr fields) (parse-result-input result)
                 (if (eq? (caar field) '_) reversed-fields
                     (cons (cons (caar field) (parse-result-value result)) reversed-fields)))))))

    (define (optional parser)
      (choice
       parser
       (ε)))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-parser)
    (import (snail-scheme test-utils) (snail-scheme source))
    (begin
      ;; Compare location fields explicitly instead of relying on record equality.
      (define (test-value value)
        (cond
         ((loc? value) (list (loc-filename value) (loc-line value) (loc-column value)))
         ((pair? value) (cons (test-value (car value)) (test-value (cdr value))))
         (else value)))

      (define (at line column)
        (make-loc "<anonymous-reader>" line column))

      ;; Success defaults to consuming all input; failure defaults to consuming none.
      ;; Supply a remainder to check prefix parsers and failures after partial progress.
      (define (check-ok parser text value . remainder)
        (let ((result (parser (string->reader "<anonymous-reader>" text))))
          (expect
           (list text (parse-result-ok? result) (test-value (parse-result-value result))
                 (list->string (reader-chars (parse-result-input result))))
           (list text #t (test-value value) (if (null? remainder) "" (car remainder))))))

      (define (check-fail parser text . remainder)
        (let ((result (parser (string->reader "<anonymous-reader>" text))))
          (expect
           (list text (parse-result-err? result) (parse-result-value result)
                 (list->string (reader-chars (parse-result-input result))))
           (list text #t '() (if (null? remainder) text (car remainder))))))

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

      (define (test-named-tuple-evaluation)
        (let* ((reader (string->reader "fields.scm" "ab"))
               (failure (parse-result-err (next-reader reader)))
               (calls '())
               (parser (named-tuple
                        (cons '_ (lambda (input) (set! calls (cons 'first calls))
                                         ((char #\a) input)))
                        (cons 'failed (lambda (_) (set! calls (cons 'second calls)) failure))
                        (cons '_ (lambda (_) (error "must stop at the first failure"))))))
          (expect (eq? (parser reader) failure) #t)
          (expect calls '(second first)))
        (let* ((field (cons 'before (char #\a))) (parser (named-tuple field)))
          ;; Construction captures the procedure, but names are read on success.
          (set-cdr! field (fail))
          (set-car! field 'after)
          (check-ok parser "a" '((after . #\a)))
          (set-car! field '_)
          (check-ok parser "a" '())))

      (define (test-named-tuple-reentrancy)
        (letrec ((parser
                  (named-tuple
                   (cons 'first
                         (lambda (reader)
                           (if (eqv? (peek-reader reader) #\a)
                               (check-ok parser "bc!" '((first . #\b) (second . #\c)) "!"))
                           ((char-if char-alphabetic?) reader)))
                   (cons '_ (ε))
                   (cons '_ (ε))
                   (cons 'second (char #\c)))))
          (check-ok parser "ac?" '((first . #\a) (second . #\c)) "?")))

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
        (run-test test-named-tuple-evaluation)
        (run-test test-named-tuple-reentrancy)
        (run-test test-optional)
        (run-test test-tag)
        (run-test test-eof-and-location))
      ))))
