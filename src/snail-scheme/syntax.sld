(define-library (snail-scheme syntax)
  (export
    ; loc
    <loc>
    loc?
    make-loc
    loc-filename
    loc-line
    loc-column

    ; syntax
    syntax?
    syntax-loc

    ; list-syntax
    <list-syntax>
    make-list-syntax
    list-syntax?
    list-syntax-elements
    list-syntax-improper-tail
    list-syntax-loc

    ; atom-syntax
    <atom-syntax>
    make-atom-syntax
    atom-syntax?
    atom-syntax-value
    atom-syntax-loc)

  (import
    (scheme base)
    (snail-scheme common))

  (begin
    ;
    ; loc
    ;

    (define-record-type <loc>
      (make-loc
        filename ; string
        line ; int, 1-indexed
        column) ; int, 1-indexed
      loc?
      (filename loc-filename)
      (line loc-line)
      (column loc-column))

    ;
    ; syntax
    ;

    (define (syntax? obj)
      (or
        (list-syntax? obj)
        (atom-syntax? obj)))

    (define (syntax-loc stx)
      (cond
        ((list-syntax? stx)
          (list-syntax-loc stx))
        ((atom-syntax? stx)
          (atom-syntax-loc stx))
        (else
          (error "syntax-loc expected syntax object" stx))))

    (define-record-type <list-syntax>
      (make-list-syntax
        elements ; list of syntax objects
        improper-tail ; null or a syntax object representing the improper tail
        loc) ; loc indicating the start of this list syntax object
      list-syntax?
      (elements list-syntax-elements)
      (improper-tail list-syntax-improper-tail)
      (loc list-syntax-loc))

    (define-record-type <atom-syntax>
      (make-atom-syntax
        value ; value of this atom: number? or char? or string? or symbol?
        loc) ; loc indicating the start of this syntax object
      atom-syntax?
      (value atom-syntax-value)
      (loc atom-syntax-loc))))
