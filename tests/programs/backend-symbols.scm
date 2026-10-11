(import (scheme base) (scheme write) (scheme process-context) (scheme hash-table) (snail typing)
        (only (snail-scheme core) %make-record-type %make-record %record-ref))

(define (check expected actual)
  (unless (equal? expected actual) (error "symbol mismatch" expected actual)))

;; Each mode runs in a fresh process and reaches the registry a different way.
(define mode (cadr (command-line)))
(cond ((string=? mode "literal-first") (check #t (eq? 'literal (string->symbol "literal"))))
      ((string=? mode "dynamic-first")
       (check #f (eq? 'literal (string->symbol "previously-unseen-name"))))
      ((string=? mode "reverse-first") (check "λ😀" (symbol->string '|λ😀|)))
      (else (error "unknown symbol test mode" mode)))

(define dynamic (string->symbol (string-append "lit" "eral")))
(check #t (eq? 'literal dynamic))
(check #t (eqv? 'literal dynamic))
(check #t (equal? 'literal dynamic))
(check #f (eq? 'literal (string->symbol "Literal")))
(check #f (char? dynamic))
(check #f (number? dynamic))
(check #f (string? dynamic))
(check #t (symbol? dynamic))
(check #f (symbol? #\λ))
(check #f (eqv? #\λ (string->symbol "λ")))

;; Dynamic typed entry checks and occurrence predicates share the symbol tag.
(: identity (-> Symbol Symbol))
(define (identity value) value)
(check #t (eq? 'literal (apply identity (list dynamic))))
(: spelling (-> (U String Symbol) String))
(define (spelling value) (if (symbol? value) (symbol->string value) value))
(check "literal" (spelling dynamic))
(check "text" (spelling "text"))

;; Reverse names live in Rust, independently of the input Scheme string.
(define name (string #\λ #\😀 (integer->char 0)))
(define symbol (string->symbol name))
(check name (symbol->string symbol))
(check "" (symbol->string (string->symbol "")))
(define output (open-output-string))
(write '|λ😀| output)
(check "λ😀" (get-output-string output))
(close-port output)

;; Registry names survive collection of the Scheme strings and symbol boxes.
(let loop ((index 0))
  (unless (= index 512)
    (string->symbol (string-append "growing-name-" (number->string index)))
    (loop (+ index 1))))
(check #t (eq? dynamic (string->symbol "literal")))
(check name (symbol->string symbol))

;; Separately allocated boxes must be interchangeable as identity keys.
(for-each
 (lambda (equivalent?)
   (let ((table (make-hash-table equivalent?)))
     (hash-table-set! table 'literal 42)
     (check 42 (hash-table-ref table dynamic))
     (hash-table-set! table (string->symbol "literal") 43)
     (check 1 (hash-table-size table))
     (check 43 (hash-table-ref table 'literal))))
 (list eq? eqv? equal?))

;; Record metadata also compares field-name IDs rather than box addresses.
(define type (%make-record-type 'sample '(field)))
(define record (%make-record type (list (string->symbol "field")) '(99)))
(check 99 (%record-ref type (string->symbol "field") record))
(display "symbol checks passed\n")
