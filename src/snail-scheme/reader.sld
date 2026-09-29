(define-library (snail-scheme reader)
  (export
   <reader>
   make-reader
   reader?
   reader-filename
   reader-chars
   reader-line
   reader-column
   file->reader
   string->reader
   list->reader
   reader-eof?
   peek-reader
   next-reader
   reader-loc)

  (import
   (scheme base)
   (only (snail-scheme common) file->string)
   (snail-scheme source))

  (begin
    ;;
    ;; Character reader
    ;;

    (define-record-type <reader>
      (make-reader
       filename ; filename to include in syntax `<loc>`
       chars ; list of chars
       line ; the 1-indexed line of the first character
       column) ; the 1-indexed column of the first character
      reader?
      (filename reader-filename)
      (chars reader-chars)
      (line reader-line)
      (column reader-column))

    (define (file->reader filename)
      (string->reader filename (file->string filename)))

    (define (string->reader filename str)
      (let ((chars (string->list str)))
        (list->reader filename chars)))

    (define (list->reader filename chars)
      (make-reader filename chars 1 1))

    (define (reader-eof? reader)
      (null? (peek-reader reader)))

    (define (peek-reader reader)
      (let ((chars (reader-chars reader)))
        (if (null? chars) '() (car chars))))

    (define (next-reader reader)
      (let* ((filename (reader-filename reader))
             (old-chars (reader-chars reader))
             (old-line (reader-line reader))
             (old-column (reader-column reader))
             (car-char (car old-chars))
             (next-chars (cdr old-chars))
             ;; Count CRLF as one line ending, and also accept a standalone CR.
             (newline? (or (eqv? car-char #\newline)
                           (and (eqv? car-char #\return)
                                (not (and (pair? next-chars)
                                          (eqv? (car next-chars) #\newline))))))
             (next-line (if newline? (+ 1 old-line) old-line))
             (next-column (if newline? 1 (+ 1 old-column))))
        (make-reader filename next-chars next-line next-column)))

    (define (reader-loc reader)
      (make-loc
       (reader-filename reader)
       (reader-line reader)
       (reader-column reader)))))
