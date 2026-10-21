;; (lofi table) for the Chibi host: the same Patricia trie as Lofi's, on
;; Chibi's own string hash. A trie is '() when empty, a leaf
;; #(leaf hash entries), or a branch #(branch prefix bit zero one). Entries
;; are (key . value) pairs. Iteration order follows the hash, so it differs
;; from Lofi's.
(define-library (lofi table)
  (export
   empty-table
   table-ref
   table-set
   table-contains?
   table-count
   table-keys
   table-values)
  (import
   (scheme base)
   (only (srfi 69) string-hash)
   (srfi 151)
   (only (lofi base) Some None))
  (begin

    (define empty-table '())

    (define (below hash bit) (bitwise-and hash (- bit 1)))

    (define (leaf? table) (eq? (vector-ref table 0) 'leaf))

    ;; The leaf entry for `key`, or #f.
    (define (entry table key)
      (let ((hash (string-hash key)))
        (let loop ((table table))
          (cond ((null? table) #f)
                ((leaf? table) (and (= (vector-ref table 1) hash) (assoc key (vector-ref table 2))))
                (else (loop (if (zero? (bitwise-and hash (vector-ref table 2))) (vector-ref table 3) (vector-ref table 4))))))))

    (define (table-ref table key)
      (let ((found (entry table key)))
        (if found (Some (cdr found)) (None))))

    (define (table-contains? table key)
      (if (entry table key) #t #f))

    (define (table-set table key value)
      (let* ((hash (string-hash key)) (leaf (vector 'leaf hash (list (cons key value)))))
        (let insert ((table table))
          (cond ((null? table) leaf)
                ((leaf? table)
                 (if (= (vector-ref table 1) hash)
                     (vector 'leaf hash (cons (cons key value) (remove-key key (vector-ref table 2))))
                     (join hash leaf (vector-ref table 1) table)))
                (else
                 (let ((prefix (vector-ref table 1)) (bit (vector-ref table 2)))
                   (cond ((not (= (below hash bit) prefix)) (join hash leaf prefix table))
                         ((zero? (bitwise-and hash bit)) (vector 'branch prefix bit (insert (vector-ref table 3)) (vector-ref table 4)))
                         (else (vector 'branch prefix bit (vector-ref table 3) (insert (vector-ref table 4)))))))))))

    (define (remove-key key entries)
      (cond ((null? entries) '())
            ((string=? (caar entries) key) (cdr entries))
            (else (cons (car entries) (remove-key key (cdr entries))))))

    (define (join a a-table b b-table)
      (let* ((difference (bitwise-xor a b)) (bit (bitwise-and difference (- difference))))
        (if (zero? (bitwise-and a bit))
            (vector 'branch (below a bit) bit a-table b-table)
            (vector 'branch (below a bit) bit b-table a-table))))

    (define (table-fold f initial table)
      (cond ((null? table) initial)
            ((leaf? table)
             (let loop ((entries (vector-ref table 2)) (result initial))
               (if (null? entries) result (loop (cdr entries) (f result (car entries))))))
            (else (table-fold f (table-fold f initial (vector-ref table 3)) (vector-ref table 4)))))

    (define (table-count table) (table-fold (lambda (count entry) (+ count 1)) 0 table))

    (define (table-keys table) (reverse (table-fold (lambda (keys entry) (cons (car entry) keys)) '() table)))

    (define (table-values table) (reverse (table-fold (lambda (values entry) (cons (cdr entry) values)) '() table)))

    ))
