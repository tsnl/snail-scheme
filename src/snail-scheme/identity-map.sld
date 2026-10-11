;; Persistent eq?-keyed evidence indexes. Only the association path is copied;
;; published records, pairs, and child vectors are never mutated.
(define-library (snail-scheme identity-map)
  (export empty-identity-map identity-map-ref identity-map-set)
  (import (scheme base) (only (scheme hash-table) hash-by-identity))
  (begin

    ;; ---- Nodes and bitmap positions ----

    (define empty-identity-map #f)
    ;; A leaf's hash is the suffix remaining after its ancestor digits. This
    ;; avoids shifts/divisors that could overflow the host's bounded integers.
    (define-record-type <leaf>
      (make-leaf hash entries) leaf? (hash leaf-hash) (entries leaf-entries))
    (define-record-type <branch>
      (make-branch bitmap children) branch?
      (bitmap branch-bitmap) (children branch-children))

    ;; Eight children keep the bitmap in one byte. Portable arithmetic and a
    ;; byte population-count table suffice without a runtime bitwise library.
    (define digit-bits '#(1 2 4 8 16 32 64 128))
    (define byte-populations
      '#(0 1 1 2 1 2 2 3 1 2 2 3 2 3 3 4
           1 2 2 3 2 3 3 4 2 3 3 4 3 4 4 5
           1 2 2 3 2 3 3 4 2 3 3 4 3 4 4 5
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           1 2 2 3 2 3 3 4 2 3 3 4 3 4 4 5
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7
           1 2 2 3 2 3 3 4 2 3 3 4 3 4 4 5
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7
           2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6
           3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7
           3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7
           4 5 5 6 5 6 6 7 5 6 6 7 6 7 7 8))

    (define (hash-bit hash) (vector-ref digit-bits (remainder hash 8)))
    (define (occupied? bitmap bit) (= (remainder (quotient bitmap bit) 2) 1))
    (define (child-index bitmap bit) (vector-ref byte-populations (remainder bitmap bit)))

    ;; ---- Lookup ----

    (define (identity-map-ref root key default)
      (node-ref root key (hash-by-identity key) default))

    (define (node-ref node key hash default)
      (cond ((not node) default)
            ((leaf? node)
             (let ((entry (and (= hash (leaf-hash node)) (assq key (leaf-entries node)))))
               (if entry (cdr entry) default)))
            (else
             (let ((bit (hash-bit hash)) (bitmap (branch-bitmap node)))
               (if (occupied? bitmap bit)
                   (node-ref (vector-ref (branch-children node) (child-index bitmap bit))
                             key (quotient hash 8) default)
                   default)))))

    ;; ---- Persistent association ----

    (define (identity-map-set root key value)
      (node-set root key value (hash-by-identity key)))

    (define (replace-entry entries key value)
      (cond ((null? entries) (list (cons key value)))
            ((eq? key (caar entries)) (cons (cons key value) (cdr entries)))
            (else (cons (car entries) (replace-entry (cdr entries) key value)))))

    (define (node-set node key value hash)
      (cond ((not node) (make-leaf hash (list (cons key value))))
            ((leaf? node)
             (if (= hash (leaf-hash node))
                 (make-leaf hash (replace-entry (leaf-entries node) key value))
                 (join-leaves node (make-leaf hash (list (cons key value))))))
            (else (associate-child node key value hash))))

    ;; Equal hashes have already formed one collision leaf. Unequal suffixes
    ;; must differ at a finite digit, even for aligned address-like hashes.
    (define (join-leaves left right)
      (let ((left-bit (hash-bit (leaf-hash left))) (right-bit (hash-bit (leaf-hash right)))
            (left-child (make-leaf (quotient (leaf-hash left) 8) (leaf-entries left)))
            (right-child (make-leaf (quotient (leaf-hash right) 8) (leaf-entries right))))
        (if (= left-bit right-bit)
            (make-branch left-bit (vector (join-leaves left-child right-child)))
            (make-branch (+ left-bit right-bit)
                         (if (< left-bit right-bit) (vector left-child right-child)
                             (vector right-child left-child))))))

    (define (associate-child node key value hash)
      (let* ((bitmap (branch-bitmap node)) (children (branch-children node))
             (bit (hash-bit hash)) (index (child-index bitmap bit))
             (present? (occupied? bitmap bit))
             (child (node-set (and present? (vector-ref children index)) key value (quotient hash 8))))
        (make-branch (if present? bitmap (+ bitmap bit))
                     (copy-children children index child present?))))

    ;; Mutation initializes a fresh unpublished vector only. Every old child
    ;; remains shared, except for the path replaced by this association.
    (define (copy-children old index child replace?)
      (let* ((extra (if replace? 0 1)) (size (+ (vector-length old) extra))
             (new (make-vector size)))
        (let loop ((position 0))
          (if (= position size) new
              (begin
                (vector-set! new position
                             (cond ((= position index) child)
                                   ((< position index) (vector-ref old position))
                                   (else (vector-ref old (- position extra)))))
                (loop (+ position 1))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-identity-map)
    (import (snail-scheme test-utils))
    (begin
      (define (test-identity-and-persistence)
        (let* ((a (cons 1 2)) (b (cons 1 2))
               (first (identity-map-set empty-identity-map a #f))
               (second (identity-map-set first b '()))
               (third (identity-map-set second a 'changed)))
          (expect (identity-map-ref empty-identity-map a 'missing) 'missing)
          (expect (identity-map-ref first b 'missing) 'missing)
          (expect (identity-map-ref second a 'missing) #f)
          (expect (identity-map-ref second b 'missing) '())
          (expect (identity-map-ref third a 'missing) 'changed)
          (set-car! a 99)
          (expect (identity-map-ref third a 'missing) 'changed)))

      (define (test-controlled-hashes)
        (let* ((a (cons 1 2)) (b (cons 1 2)) (c (cons 1 2))
               (largest (string->number "9223372036854775807"))
               (one (node-set #f a 'first largest))
               (two (node-set one b #f largest))
               (three (node-set two c '() (- largest 1)))
               (four (node-set three a 'latest largest)))
          (expect (node-ref one b largest 'missing) 'missing)
          (expect (node-ref four b largest 'missing) #f)
          (expect (node-ref four c (- largest 1) 'missing) '())
          (expect (node-ref four a largest 'missing) 'latest)
          (expect (node-ref three a largest 'missing) 'first)
          (expect (node-ref four a 0 'missing) 'missing)
          (let ((deep (node-set (node-set #f a 1 0) b 2
                                (string->number "4611686018427387904"))))
            (expect (node-ref deep a 0 'missing) 1)
            (expect (node-ref deep b (string->number "4611686018427387904") 'missing) 2))))

      ;; Save every version, then compare every lookup with an alist model.
      ;; These hashes exercise collisions, aligned prefixes, and packed slots.
      (define (test-version-model)
        (let ((keys (list->vector (map (lambda (n) (cons n '())) '(0 1 2 3 4 5 6 7 8 9 10 11)))))
          (define (hash index) (* 512 (modulo index 9)))
          (let loop ((step 0) (root #f) (entries '()) (versions '()))
            (if (= step 100)
                (for-each
                 (lambda (version)
                   (let check ((index 0))
                     (unless (= index 12)
                       (let* ((key (vector-ref keys index)) (entry (assq key (cdr version))))
                         (expect (node-ref (car version) key (hash index) 'missing)
                                 (if entry (cdr entry) 'missing)))
                       (check (+ index 1)))))
                 versions)
                (let* ((index (modulo (* step 7) 12)) (key (vector-ref keys index))
                       (next (node-set root key step (hash index)))
                       (model (cons (cons key step) entries)))
                  (loop (+ step 1) next model (cons (cons next model) versions)))))))

      (define (test-identity-map)
        (run-test test-identity-and-persistence)
        (run-test test-controlled-hashes)
        (run-test test-version-model))))))

