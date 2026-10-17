;; The compiler's persistent subset of SRFI 146: constructors, lookup, update,
;; size, membership, comparator access and folding. No linear-update operations.
(define-library (lofi hashmap)
  (export hashmap hashmap? hashmap-ref hashmap-ref/default hashmap-set hashmap-fold
          hashmap-size hashmap-contains? hashmap-key-comparator)
  (import
   (scheme base)
   (scheme case-lambda)
   (scheme cxr)
   (scheme char)
   (only (srfi 128) comparator-hashable? comparator-hash-function
         comparator-equality-predicate comparator-test-type)
   (only (srfi 151) bitwise-and bitwise-xor)
   (only (srfi 69) hash hash-by-identity string-hash string-ci-hash))
  (begin

    ;; ---- Persistent compressed hash trie ----

    ;; A leaf holds one complete hash and a nonempty collision bucket. A branch
    ;; splits at one bit; every descendant shares the prefix below that bit.
    ;; Both children exist, and branch masks increase along each path. Skipping
    ;; unused bit positions keeps large hash gaps from creating unary chains.
    (define-record-type <hashmap>
      (make-hashmap comparator hasher root size) hashmap?
      (comparator hashmap-key-comparator)
      (hasher hashmap-hasher)
      (root hashmap-root)
      (size hashmap-size))
    (define-record-type <leaf>
      (make-leaf hash entries) leaf?
      (hash leaf-hash)
      (entries leaf-entries))
    (define-record-type <branch>
      (make-branch mask prefix zero one) branch?
      (mask branch-mask)
      (prefix branch-prefix)
      (zero branch-zero)
      (one branch-one))
    (define (hash-bit? hash mask) (not (zero? (bitwise-and hash mask))))
    (define (prefix-matches? branch hash)
      (= (bitwise-and hash (- (branch-mask branch) 1)) (branch-prefix branch)))
    (define (branch-child branch hash)
      (if (hash-bit? hash (branch-mask branch)) (branch-one branch) (branch-zero branch)))

    ;; SRFI 146 also accepts the standard equality predicates without a supplied
    ;; hash function. The map retains the original comparator in either case.
    (define (comparator-hasher comparator)
      (let ((same? (comparator-equality-predicate comparator)))
        (cond ((comparator-hashable? comparator) (comparator-hash-function comparator))
              ((eq? same? eq?) hash-by-identity)
              ((or (eq? same? eqv?) (eq? same? equal?)) hash)
              ((eq? same? string=?) string-hash)
              ((eq? same? string-ci=?) string-ci-hash)
              (else (error "hashmap comparator requires a hash function")))))
    (define (key-hash map key)
      (let ((hash ((hashmap-hasher map) key)))
        (unless (and (exact-integer? hash) (>= hash 0))
          (error "hashmap hash must be an exact nonnegative integer" hash)) hash))

    ;; ---- Lookup returns an association, so a false value remains present ----

    (define (bucket-entry entries key same?)
      (let find ((entries entries))
        (cond ((null? entries) #f)
              ((same? key (caar entries)) (car entries))
              (else (find (cdr entries))))))
    (define (lookup-entry map key)
      (let ((hash (key-hash map key)) (same? (comparator-equality-predicate (hashmap-key-comparator map))))
        (let find ((node (hashmap-root map)))
          (cond ((not node) #f)
                ((leaf? node) (and (= hash (leaf-hash node)) (bucket-entry (leaf-entries node) key same?)))
                ((prefix-matches? node hash) (find (branch-child node hash)))
                (else #f)))))
    ;; Failure and success are called directly in tail context, including when
    ;; they return multiple values. Lookup never captures the caller's stack.
    (define hashmap-ref
      (case-lambda
       ((map key)
        (let ((entry (lookup-entry map key)))
          (if entry (cdr entry) (error "hashmap-ref: key not in hashmap" key))))
       ((map key failure)
        (let ((entry (lookup-entry map key))) (if entry (cdr entry) (failure))))
       ((map key failure success)
        (let ((entry (lookup-entry map key))) (if entry (success (cdr entry)) (failure))))))
    (define (hashmap-ref/default map key default)
      (let ((entry (lookup-entry map key))) (if entry (cdr entry) default)))
    (define (hashmap-contains? map key) (and (lookup-entry map key) #t))

    ;; ---- Collision buckets preserve earlier snapshots ----

    (define (restore-prefix reversed tail)
      (if (null? reversed) tail (restore-prefix (cdr reversed) (cons (car reversed) tail))))
    (define (put-bucket entries entry same? replace?)
      (let find ((remaining entries) (before '()))
        (cond ((null? remaining) (values (cons entry entries) 1))
              ((same? (car entry) (caar remaining))
               (values (if replace? (restore-prefix before (cons entry (cdr remaining))) entries) 0))
              (else (find (cdr remaining) (cons (car remaining) before))))))

    ;; ---- Insertion descends once and rebuilds only the recorded path ----

    ;; For a branch prefix mismatch, the lowest differing bit lies below its
    ;; mask. For two leaves it is the first differing full-hash bit. Either way
    ;; the new branch belongs above the old node and below all visited parents.
    ;; Hashes are unbounded exact integers; no high bits are discarded.
    (define (join-node node hash entry)
      (let* ((prior (if (leaf? node) (leaf-hash node) (branch-prefix node)))
             (difference (bitwise-xor hash prior)) (mask (bitwise-and difference (- difference)))
             (prefix (bitwise-and hash (- mask 1))) (added (make-leaf hash (list entry))))
        (if (hash-bit? hash mask) (make-branch mask prefix node added)
            (make-branch mask prefix added node))))
    (define (replace-child parent hash child)
      (if (hash-bit? hash (branch-mask parent))
          (make-branch (branch-mask parent) (branch-prefix parent) (branch-zero parent) child)
          (make-branch (branch-mask parent) (branch-prefix parent) child (branch-one parent))))
    (define (rebuild-path path child hash)
      (if (null? path) child
          (rebuild-path (cdr path) (replace-child (car path) hash child) hash)))
    ;; Descent stops at an empty root, a leaf, or a mismatching branch prefix.
    ;; A matching hash updates only its bucket; every other insertion adds a leaf.
    (define (insert-at-boundary node hash entry same? replace?)
      (cond ((not node) (values (make-leaf hash (list entry)) 1))
            ((and (leaf? node) (= hash (leaf-hash node)))
             (let-values (((entries added) (put-bucket (leaf-entries node) entry same? replace?)))
               (values (make-leaf hash entries) added)))
            (else (values (join-node node hash entry) 1))))
    (define (insert-root root hash entry same? replace?)
      (let descend ((node root) (path '()))
        (if (and (branch? node) (prefix-matches? node hash))
            (descend (branch-child node hash) (cons node path))
            (let-values (((child added) (insert-at-boundary node hash entry same? replace?)))
              (values (rebuild-path path child hash) added)))))
    (define (insert-association map key value replace?)
      (let ((comparator (hashmap-key-comparator map)))
        (unless (comparator-test-type comparator key) (error "hashmap key fails comparator type test" key))
        (let-values (((root added) (insert-root (hashmap-root map) (key-hash map key) (cons key value)
                                                (comparator-equality-predicate comparator) replace?)))
          (make-hashmap comparator (hashmap-hasher map) root (+ (hashmap-size map) added)))))
    (define (insert-pairs map pairs replace?)
      (cond ((null? pairs) map)
            ((null? (cdr pairs)) (error "hashmap requires alternating keys and values"))
            (else (insert-pairs (insert-association map (car pairs) (cadr pairs) replace?) (cddr pairs) replace?))))
    ;; Construction keeps the first association; set replaces from left to right.
    ;; Replacement stores the new representative key as well as its new value.
    (define (hashmap comparator . pairs)
      (insert-pairs (make-hashmap comparator (comparator-hasher comparator) #f 0) pairs #f))
    (define (hashmap-set map . pairs) (insert-pairs map pairs #t))

    ;; ---- Folding owns an explicit pending-node list ----

    (define (fold-bucket proc result entries)
      (if (null? entries) result
          (fold-bucket proc (proc (caar entries) (cdar entries) result) (cdr entries))))
    (define (hashmap-fold proc seed map)
      (let visit ((pending (list (hashmap-root map))) (result seed))
        (if (null? pending) result
            (let ((node (car pending)) (rest (cdr pending)))
              (cond ((not node) (visit rest result))
                    ((leaf? node) (visit rest (fold-bucket proc result (leaf-entries node))))
                    (else (visit (cons (branch-zero node) (cons (branch-one node) rest)) result))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-hashmap)
    (import
     (wasm-native test-utils)
     (only (srfi 128) make-comparator make-eq-comparator))
    (begin
      (define (collision-comparator)
        (make-comparator string? string-ci=? #f (lambda (key) 7)))
      (define (test-collisions-and-replacement)
        (let* ((comparator (collision-comparator))
               (first (hashmap comparator "first" #f "SECOND" 0 "FIRST" 'ignored))
               (second (hashmap-set first "fIrSt" 9 "second" 10 "THIRD" 30 "second" 11))
               (entries (hashmap-fold (lambda (key value entries) (cons (cons key value) entries)) '() second)))
          (expect (hashmap-size first) 2) (expect (hashmap-size second) 3)
          (expect (hashmap-ref first "FIRST") #f) (expect (hashmap-ref first "second") 0)
          (expect (hashmap-ref/default first "third" 'missing) 'missing)
          (expect (hashmap-ref second "FIRST") 9) (expect (hashmap-ref second "SECOND") 11)
          (expect (assoc "fIrSt" entries) '("fIrSt" . 9))
          (expect (assoc "first" entries) #f)
          (expect (hashmap-fold (lambda (key value sum) (+ value sum)) 0 second) 50)
          (expect (eq? (hashmap-key-comparator second) comparator) #t)))
      (define (test-lookup-handlers)
        (let ((map (hashmap (make-eq-comparator) #f #f 0 'zero)))
          (expect (hashmap-contains? map #f) #t) (expect (hashmap-contains? map 'missing) #f)
          (expect (hashmap-ref map #f (lambda () (error "unexpected failure"))) #f)
          (expect (hashmap-ref/default map 'missing #f) #f)
          (let-values (((first second) (hashmap-ref map 'missing (lambda () (values 1 2)))))
            (expect (list first second) '(1 2)))
          (let-values (((first second) (hashmap-ref map 0 (lambda () (error "unexpected failure"))
                                                    (lambda (value) (values value 2)))))
            (expect (list first second) '(zero 2)))
          (expect (guard (failure (else #t)) (hashmap-ref map 'missing) #f) #t)))
      (define (test-tail-handlers)
        (let ((map (hashmap (make-eq-comparator) 'present #f)))
          (expect (let loop ((remaining 10000))
                    (if (= remaining 0) 'done
                        (hashmap-ref map (if (odd? remaining) 'present 'missing)
                                     (lambda () (loop (- remaining 1)))
                                     (lambda (value) (loop (- remaining 1)))))) 'done)))
      (define (test-unbounded-hash-prefixes)
        (let* ((high (expt 2 130)) (comparator (make-comparator exact-integer? = #f (lambda (key) key)))
               (first (hashmap comparator 3 'low (+ 3 high) 'high))
               (second (hashmap-set first 5 'five 2 'two (+ 3 (* high 2)) 'higher (+ 3 high) 'replaced)))
          (expect (branch-mask (hashmap-root first)) high)
          (expect (hashmap-size first) 2) (expect (hashmap-size second) 5)
          (expect (hashmap-ref first (+ 3 high)) 'high)
          (expect (hashmap-ref second (+ 3 high)) 'replaced)
          (expect (map (lambda (key) (hashmap-ref second key)) (list 3 5 2 (+ 3 (* high 2)))) '(low five two higher))
          (expect (hashmap-ref/default second (+ 3 (quotient high 2)) 'missing) 'missing)
          (expect (hashmap-fold (lambda (key value count) (+ count 1)) 0 second) 5)))
      (define (test-comparator-boundaries)
        (let* ((comparator (make-comparator string? string-ci=? #f #f))
               (map (hashmap comparator "Alpha" 42)))
          (expect (hashmap-ref map "ALPHA") 42)
          (expect (eq? (hashmap-key-comparator map) comparator) #t)
          (expect (guard (failure (else #t)) (hashmap-set map 12 'invalid) #f) #t)
          (expect (guard (failure (else #t)) (hashmap-set map "missing-value") #f) #t)
          (expect (guard (failure (else #t))
                    (hashmap (make-comparator (lambda (key) #t) eq? #f (lambda (key) -1)) 'key 1) #f) #t)))
      (define (test-hashmap)
        (run-test test-collisions-and-replacement)
        (run-test test-lookup-handlers)
        (run-test test-tail-handlers)
        (run-test test-unbounded-hash-prefixes)
        (run-test test-comparator-boundaries))))
   (else)))
