;; Immutable tables from strings to values: a Patricia trie on each key's
;; 64-bit FNV-1a hash, after Okasaki and Gill's "Fast Mergeable Integer Maps".
;; A branch splits its keys on the lowest bit where their hashes differ; keys
;; whose hashes collide share a leaf. An update copies the path to one leaf
;; and shares every other node with the table it came from.
(define-library (snail core table)
  (export
   Table
   empty-table
   table-ref
   table-set
   table-contains?
   table-count
   table-keys
   table-values)
  (import
   (snail core base))
  (begin

    ;; A branch's `prefix` is the hash bits below `bit` that all its keys
    ;; share; `zero` holds the keys whose hash has `bit` clear.
    (enum (Table V)
      (Empty)
      (Leaf
       ((hash I64)
        (entries (List (Pair String V)))))
      (Branch
       ((prefix I64)
        (bit I64)
        (zero (Table V))
        (one (Table V)))))

    (define empty-table (→ (Table V)) (∀ V) (Empty))

    ;; FNV-1a over the code points, wrapping in 64 bits.

    (define (string-hash (key String)) (→ I64)
      (let loop ((index 0) (hash -3750763034362895579))
        (if (= index (string-length key))
            hash
            (loop (+ index 1)
                  (* (i64-xor hash (char->integer (string-ref key index))) 1099511628211)))))

    (define (below (hash I64) (bit I64)) (→ I64)
      (i64-and hash (- bit 1)))

    (define (table-ref (table (Table V)) (key String))
      (→ (Option V))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (let ((hash (string-hash key)))
        (let loop ((table table))
          (match table
            ((Empty) (None))
            ((Leaf leaf-hash entries) (if (= leaf-hash hash) (assoc-ref entries key) (None)))
            ((Branch _ bit zero one) (loop (if (= (i64-and hash bit) 0) zero one)))))))

    (define (table-contains? (table (Table V)) (key String))
      (→ Bool)
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (match (table-ref table key)
        ((Some _) #t)
        ((None) #f)))

    (define (table-set (table (Table V)) (key String) (value V))
      (→ (Table V))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (let ((hash (string-hash key)))
        (let insert ((table table))
          (match table
            ((Empty) (Leaf hash (list (Pair key value))))
            ((Leaf leaf-hash entries)
             (if (= leaf-hash hash)
                 (Leaf hash
                       (Cons (Pair key value)
                             (filter (lambda (entry) (not (string=? (● entry first) key)))
                                     entries)))
                 (join hash (Leaf hash (list (Pair key value))) leaf-hash table)))
            ((Branch prefix bit zero one)
             (cond ((not (= (below hash bit) prefix))
                    (join hash (Leaf hash (list (Pair key value))) prefix table))
                   ((= (i64-and hash bit) 0) (Branch prefix bit (insert zero) one))
                   (else (Branch prefix bit zero (insert one)))))))))

    ;; A branch over two tries whose hashes, `a` and `b`, differ. It splits
    ;; on their lowest differing bit.

    (define (join (a I64) (a-table (Table V)) (b I64) (b-table (Table V))) (→ (Table V)) (∀ V)
      (let* ((difference (i64-xor a b)) (bit (i64-and difference (negate difference))))
        (if (= (i64-and a bit) 0)
            (Branch (below a bit) bit a-table b-table)
            (Branch (below a bit) bit b-table a-table))))

    ;; Entries in trie order, which depends only on the keys.

    (define (table-fold (f (Fn A (Pair String V) → A ! e)) (initial A) (table (Table V)))
      (→ A)
      (! e)
      (∀ V A e)
      (match table
        ((Empty) initial)
        ((Leaf _ entries) (fold-left f initial entries))
        ((Branch _ _ zero one) (table-fold f (table-fold f initial zero) one))))

    (define (table-count (table (Table V)))
      (→ I64)
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (table-fold (lambda (count entry) (+ count 1)) 0 table))

    (define (table-keys (table (Table V)))
      (→ (List String))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (reverse (table-fold (lambda (keys entry) (Cons (● entry first) keys)) (Nil) table)))

    (define (table-values (table (Table V)))
      (→ (List V))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (reverse (table-fold (lambda (values entry) (Cons (● entry second) values)) (Nil) table)))

    ))
