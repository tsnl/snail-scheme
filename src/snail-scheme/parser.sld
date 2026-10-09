(define-library (snail-scheme parser)
  (export
   ;; Results
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

   ;; Combinators and primitive parsers
   return
   ε
   fail
   >>=
   chain
   pmap
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
   optional
   eof
   location)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme reader))

  (begin
    ;;
    ;; ParseResult
    ;; Do not confuse with (Parser T):
    ;; Parser T := (Reader) -> (ParseResult T)
    ;;

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

    ;;
    ;; Basic Monadic (Parser T)
    ;; Parser T := (Reader) -> (ParseResult T)
    ;; IMPORTANT: the monadic type is (Parser T), NOT (ParseResult T).
    ;;

    ;;; `chain` sequences binders, starting with the value '().
    ;;;
    ;;; It is a parser combinator (i.e. its application returns a parser function) that chains
    ;;; multiple parsers together.
    ;;;   ```scheme
    ;;;   (chain
    ;;;     (lambda (value) (...))
    ;;;     (lambda (value) (...)))
    ;;;   ```
    ;;; The `chain` statement will try applying each closure in sequence until one of them fails,
    ;;; including the init.
    (define chain
      (lambda binder-list
        (let recur ((binder-list binder-list)
                    (parser (ε)))
          (if (null? binder-list)
              parser
              (recur
               (cdr binder-list)
               (>>= parser (car binder-list)))))))

    ;;; monadic return operator for (Parser T)
    ;;;   return :: (T) -> Parser T
    (define (return value)
      (lambda (reader)
        (parse-result-ok value reader)))

    ;; The empty sequence succeeds without consuming input.
    (define (ε) (return '()))

    ;;; monadic return operator (fail variant) for (Parser T)
    ;;;   fail :: () -> Parser T
    (define (fail)
      (lambda (reader)
        (parse-result-err reader)))

    ;;; monadic bind operator for (Parser T)
    ;;;   >>= :: (Parser T, ((T) -> Parser U)) -> Parser U
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
      (>>= parser (lambda (value) (return (transform value)))))

    ;;
    ;; Primitive parsers: written manually, not by composition
    ;;

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

    ;;
    ;; Higher-order general-purpose parsers and combinators
    ;;

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
      (>>= (repeat parser)
           (lambda (v) (if (null? v) (fail) (return v)))))

    (define (discard parser)
      (pmap parser (lambda (_) '())))

    (define (tuple . parsers)
      (define (make-binder parser)
        (lambda (reversed-values)
          (pmap parser (lambda (value) (cons value reversed-values)))))
      (pmap (apply chain (map make-binder parsers)) reverse))

    (define (optional parser)
      (choice parser (ε)))
    ))
