(define-library (snail-scheme common)
  (export
    display-error
    first second third fourth
    repeat-string)
  (import
    (scheme base)
    (scheme write))

  (begin
    ;
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

    ))
