;; Mutable hash tables from strings to values: open hashing over an array of
;; association lists that doubles when it averages two entries per bucket.
(define-library (lofi table)
  (export
   Table
   make-table
   table-ref
   table-set!
   table-contains?
   table-count
   table-keys
   table-values)
  (import
   (lofi base))
  (begin

    (struct (Table V)
      ((buckets (Ref (Array (List (Pair String V)))))
       (count (Ref I64))))

    (: make-table (All (V) (-> (Table V) ! mut)))
    (define (make-table)
      (Table (ref (make-array 16 (Nil))) (ref 0)))

    ;; FNV-1a over the code points, wrapping in 64 bits.
    (: string-hash (-> String I64))
    (define (string-hash key)
      (let loop ((index 0) (hash -3750763034362895579))
        (if (= index (string-length key))
            hash
            (loop (+ index 1) (* (i64-xor hash (char->integer (string-ref key index))) 1099511628211)))))

    (: bucket-index (All (V) (-> (Table V) String I64 ! mut)))
    (define (bucket-index table key)
      (i64-and (string-hash key) (- (array-length (ref-get (Table-buckets table))) 1)))

    (: table-ref (All (V) (-> (Table V) String (Option V) ! mut)))
    (define (table-ref table key)
      (match (find (lambda (entry) (string=? (Pair-first entry) key))
                   (array-ref (ref-get (Table-buckets table)) (bucket-index table key)))
        ((Some entry) (Some (Pair-second entry)))
        ((None) (None))))

    (: table-contains? (All (V) (-> (Table V) String Bool ! mut)))
    (define (table-contains? table key)
      (match (table-ref table key)
        ((Some _) #t)
        ((None) #f)))

    (: table-set! (All (V) (-> (Table V) String V Unit ! mut)))
    (define (table-set! table key value)
      (let* ((buckets (ref-get (Table-buckets table))) (index (bucket-index table key))
             (bucket (array-ref buckets index)))
        (if (any? (lambda (entry) (string=? (Pair-first entry) key)) bucket)
            (array-set! buckets index (map (lambda (entry) (if (string=? (Pair-first entry) key) (Pair key value) entry)) bucket))
            (begin (array-set! buckets index (Cons (Pair key value) bucket))
                   (ref-set! (Table-count table) (+ (ref-get (Table-count table)) 1))
                   (when (> (ref-get (Table-count table)) (* 2 (array-length buckets)))
                     (grow! table))))))

    ;; Rehashes every entry into twice as many buckets.
    (: grow! (All (V) (-> (Table V) Unit ! mut)))
    (define (grow! table)
      (let ((entries (table-entries table)))
        (ref-set! (Table-buckets table) (make-array (* 2 (array-length (ref-get (Table-buckets table)))) (Nil)))
        (for-each (lambda (entry)
                    (let ((index (bucket-index table (Pair-first entry))))
                      (array-set! (ref-get (Table-buckets table)) index (Cons entry (array-ref (ref-get (Table-buckets table)) index)))))
                  entries)))

    (: table-count (All (V) (-> (Table V) I64 ! mut)))
    (define (table-count table)
      (ref-get (Table-count table)))

    ;; Entries in bucket order, which depends only on the keys.
    (: table-entries (All (V) (-> (Table V) (List (Pair String V)) ! mut)))
    (define (table-entries table)
      (let ((buckets (ref-get (Table-buckets table))))
        (let loop ((index (- (array-length buckets) 1)) (entries (Nil)))
          (if (< index 0) entries (loop (- index 1) (append (array-ref buckets index) entries))))))

    (: table-keys (All (V) (-> (Table V) (List String) ! mut)))
    (define (table-keys table)
      (map Pair-first (table-entries table)))

    (: table-values (All (V) (-> (Table V) (List V) ! mut)))
    (define (table-values table)
      (map Pair-second (table-entries table)))

    ))
