(define-library (snail-scheme common)
  (export
    display-error
    first second third fourth
    repeat-string
    stringify
    assert
    todo)
  (import
    (scheme base)
    (scheme write))

  (begin
    ; display-error
    ;

    (define (display-error message)
      (display message (current-error-port)))

    ;
    ; first, second, third, fourth
    ;

    (define (first it) (list-ref it 0))
    (define (second it) (list-ref it 1))
    (define (third it) (list-ref it 2))
    (define (fourth it) (list-ref it 3))

    ;
    ; string utils
    ;

    (define (repeat-string s n)
      (let loop
        ( (i 0)
          (a '()) )
        (if (< i n)
          (loop (+ i 1) (cons s a))
          (apply string-append a))))

    (define (with-output-to-string thunk)
      (let ((port (open-output-string)))
        (parameterize ((current-output-port port))
          (thunk))
        (get-output-string port)))

    ;
    ; stringify
    ;

    (define-syntax stringify
      (syntax-rules ()
        ( (_ expr)
          (let*
            ( (datum 'expr)
              (str-val (with-output-to-string (lambda () (write datum)))) )
            str-val) )))

    ;
    ; assert
    ;

    (define-syntax assert
      (syntax-rules ()
        ( (_ x)
          (if x
            '()
            (error "assertion failed" (stringify x))) )))

    ;
    ; todo
    ;

    (define (todo what)
      (error (string-append "todo: not implemented" what)))

    ))
