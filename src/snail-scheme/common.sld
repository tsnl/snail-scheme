(define-library (snail-scheme common)
  (export
   display-error
   first
   second
   third
   fourth
   every?
   repeat-string
   stringify
   assert
   todo
   call-with-input-file
   file->string

   ;; Character predicates
   char-alphabetic?
   char-numeric?
   char-whitespace?
   char-ci=?
   char-intertoken-space?
   char-delimiter?
   char-bare-atom?
   char-bare-atom-initial?
   char-quoted-identifier?
   char-line-comment?
   char-string-literal?
   char-binary-digit?
   char-octal-digit?
   char-decimal-digit?
   char-hexadecimal-digit?
   char-identifier-initial?
   char-identifier-subsequent?
   char-sign?
   char-sign-subsequent?
   char-dot-subsequent?)
  (import
   (scheme base)
   (only (scheme char) char-alphabetic? char-numeric? char-whitespace? char-ci=?)
   (scheme file)
   (scheme write))

  (begin
    ;; Character classes for the lexical grammar. Numeric digits are ASCII;
    ;; the host's Unicode alphabetic predicate also permits letters in identifiers.

    (define (char-intertoken-space? c)
      (memv c '(#\space #\tab #\newline #\return)))

    (define (char-delimiter? c)
      (or (char-intertoken-space? c) (memv c '(#\| #\( #\) #\[ #\] #\{ #\} #\" #\;))))

    (define (char-bare-atom? c)
      (not (char-delimiter? c)))

    ;; Quote abbreviations introduce expressions only at the start of an atom.
    ;; Inside a bare atom, retain them for later identifier validation.
    (define (char-bare-atom-initial? c)
      (and (char-bare-atom? c) (not (memv c '(#\' #\` #\,)))))

    (define (char-quoted-identifier? c)
      (not (memv c '(#\| #\\))))

    (define (char-line-comment? c)
      (not (memv c '(#\newline #\return))))

    (define (char-string-literal? c)
      (not (memv c '(#\" #\\))))

    (define (char-binary-digit? c)
      (char<=? #\0 c #\1))

    (define (char-octal-digit? c)
      (char<=? #\0 c #\7))

    (define (char-decimal-digit? c)
      (char<=? #\0 c #\9))

    (define (char-hexadecimal-digit? c)
      (or (char-decimal-digit? c) (char<=? #\a c #\f) (char<=? #\A c #\F)))

    (define (char-identifier-initial? c)
      (or (char-alphabetic? c) (memv c '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~ #\→))))

    (define (char-identifier-subsequent? c)
      (or (char-identifier-initial? c) (char-decimal-digit? c) (memv c '(#\+ #\- #\. #\@))))

    (define (char-sign? c)
      (memv c '(#\+ #\-)))

    (define (char-sign-subsequent? c)
      (or (char-identifier-initial? c) (char-sign? c) (eqv? c #\@)))

    (define (char-dot-subsequent? c)
      (or (char-sign-subsequent? c) (eqv? c #\.)))

    ;; display-error
    ;;

    (define (display-error message)
      (display message (current-error-port)))

    ;;
    ;; first, second, third, fourth
    ;;

    (define (first it) (list-ref it 0))
    (define (second it) (list-ref it 1))
    (define (third it) (list-ref it 2))
    (define (fourth it) (list-ref it 3))

    (define (every? predicate items)
      (or (null? items) (and (predicate (car items)) (every? predicate (cdr items)))))

    ;;
    ;; string utils
    ;;

    (define (repeat-string s n)
      (let loop ((i 0)
                 (a '()))
        (if (< i n)
            (loop (+ i 1) (cons s a))
            (apply string-append a))))

    (define (with-output-to-string thunk)
      (let ((port (open-output-string)))
        (parameterize ((current-output-port port))
          (thunk))
        (get-output-string port)))

    ;;
    ;; stringify
    ;;

    (define-syntax stringify
      (syntax-rules ()
        ((_ expr)
         (let* ((datum 'expr)
                (str-val (with-output-to-string (lambda () (write datum)))))
           str-val))))

    ;;
    ;; assert
    ;;

    (define-syntax assert
      (syntax-rules ()
        ((_ x)
         (if x
             '()
             (error "assertion failed" (stringify x))))))

    ;;
    ;; todo
    ;;

    (define (todo what)
      (error (string-append "todo: not implemented" what)))

    ;;
    ;; file->string (call-with-input-file is re-exported from scheme file)
    ;;

    (define (file->string filepath)
      (call-with-input-file filepath
        (lambda (port)
          (let recur ((reversed-accumulator '()))
            (let ((chr (read-char port)))
              (if (eof-object? chr)
                  (list->string (reverse reversed-accumulator))
                  (recur (cons chr reversed-accumulator))))))))))
