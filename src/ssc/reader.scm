(define (file->token-list filename)
  (call-with-input-file filename
    (lambda (input-port)
      (port->token-list input-port))))

(define (port->token-list port) 
  (let ((next-token (read-one-token port)))
    (if (eof-object? next-token)
      next-token
      (cons
        next-token
        (port->token-list port)))))

(define (read-one-token port) 
  (let ((ch (read-char port))) (read-one-token/c port ch)))

(define (read-one-token/c port ch)
  (define (span)
    '())
  
  (cond
    ( (eof-object? ch)
      ch )
    ( (member ch (string->list "^*/%+"))
      (if (eq? (peek-char port) #\=)
        (begin
          (read-char port)
          (let* 
            ( (op-str (string-append (make-string 1 ch) "="))
              (op-sym (string->symbol op-str)) )
            (token 'update-op (span) op-str op-sym)))
        (begin
          (let* 
            ( (op-str (make-string 1 ch))
              (op-sym (string->symbol op-str)) )
            (token 'binary-op (span) op-str op-sym)))) )
    ( (eq? ch #\-)
      (if (eq? ch #\>)
        (token 'punctuation (span) "->" '->)
        (token 'binary-op (span) "-" '-)) )
    ( (member ch (string->list "<>"))
      (if (eq? (peek-char port) #\=)
        (begin
          (read-char port)
          (let* 
            ( (op-str (string-append (make-string 1 ch) "="))
              (op-sym (string->symbol op-str)) )
            (token 'binary-op (span) op-str op-sym)))
        (begin
          (let*
            ( (op-str (make-string 1 ch))
              (op-sym (string->symbol op-str)) )
            (token 'binary-op (span) op-str op-sym))))
    ( (member ch (string->list "=!"))
      (if (eq? (peek-char port) #\=)
        (begin
          (read-char port)
          (let* 
            ( (op-str (string-append (make-string 1 ch) "="))
              (op-sym (string->symbol op-str)) )
            (token 'binop (span) op-str op-sym)))
        (if (eq? ch #\=)
          (token 'punctuation (span) "=" '=)
          (token 'unary-op (span) "!" '!))) )
    ( (eq? ch ':)
      (cond 
        ( (eq? (peek-char port) #\=)
          (begin
            (read-char port)
            (token 'update-op (span) ":=" ':=)) )
        ( (eq? (peek-char port) #\:)
          (begin
            (read-char port)
            (token 'update-op (span) "::" '::)) )
        ( else
          (begin
            (token 'update-op (span) ":" ':)) ) )
    ( (member ch (string->list ",.")) )
    ( (dec-digit? ch)
      (if (eq? ch #\0)
        (begin  ;;; checking if 'hex' fragment, 'dec' fragment, or just '0'
          (let  
            ( (next-char (peek-char port)) )
            (cond   ;;; note: at this point, only '0' is read, 'x' may be next-char if hex token, etc.
              ( (member next-char '(#\x #\X)) 
                (begin
                  (read-char port)
                  (read-one-token-la1/hex-num-token port)) )
              ( (dec-digit? next-char)
                (read-one-token-la1/dec-num-token port #\0) )
              ( else
                (token 'literal/int (span) "0" '0) ))))
        (begin  ;;; must just be a decimal integer 
          (read-one-token-la1/dec-num-token port ch))) )
    ( (id-char? ch)
      (read-one-token/id-token port (make-string 1 ch)) )
    ( else
      (begin
        (format "ERROR: '~a' came as a complete surprise." ch)
        #f) )))

(define (read-one-token/hex-num-token port)
  '())
(define (read-one-token/dec-num-token port first-char)
  '())
(define (read-one-token/id-token port leading-prefix)
  '())

(define (dec-digit? ch) (member ch dec-digit-char-set))
(define (hex-digit? ch) (member ch hex-digit-char-set))
(define (id-char? ch) (or (char-alphabetic? ch) (dec-digit? ch)))
(define (whitespace-char? ch) (or (char-whitespace? ch)))

(define dec-digit-char-set (string->list "0123456789"))
(define hex-digit-char-set (string->list "0123456789aaAAbbBBccCCddDDeeEEffFF"))
