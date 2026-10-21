;; (lofi table) for the Chibi host, over SRFI 69 hash tables.
(define-library (lofi table)
  (export
   make-table
   table-ref
   table-set!
   table-contains?
   table-count
   table-keys
   table-values)
  (import
   (scheme base)
   (srfi 69)
   (only (lofi base) Some None))
  (begin

    (define (make-table) (make-hash-table string=? string-hash))

    (define (table-ref table key)
      (if (hash-table-exists? table key) (Some (hash-table-ref table key)) (None)))

    (define (table-set! table key value) (hash-table-set! table key value))

    (define (table-contains? table key) (hash-table-exists? table key))

    (define (table-count table) (hash-table-size table))

    (define (table-keys table) (hash-table-keys table))

    (define (table-values table) (hash-table-values table))

    ))
