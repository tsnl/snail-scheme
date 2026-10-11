;; SRFI 125 operations over collector-owned buckets. Hashes select candidates;
;; equality alone matches keys. Cached hashes make resizing callback-free.
(define-library (snail-scheme hash-table)
  (export make-hash-table hash-table hash-table-unfold alist->hash-table
          hash-table? hash-table-contains? hash-table-exists? hash-table-empty?
          hash-table=? hash-table-mutable? hash-table-ref hash-table-ref/default
          hash-table-set! hash-table-delete! hash-table-intern! hash-table-update!
          hash-table-update!/default hash-table-pop! hash-table-clear!
          hash-table-size hash-table-keys hash-table-values hash-table-entries
          hash-table-find hash-table-count hash-table-map hash-table-for-each
          hash-table-walk hash-table-map! hash-table-map->list hash-table-fold
          hash-table-prune! hash-table-copy hash-table-empty-copy hash-table->alist
          hash-table-union! hash-table-merge! hash-table-intersection!
          hash-table-difference! hash-table-xor! hash string-hash string-ci-hash
          hash-by-identity hash-table-equivalence-function hash-table-hash-function)
  (import (scheme base) (scheme cxr) (scheme char)
          (only (scheme comparator) comparator? comparator-type-test-predicate
                comparator-equality-predicate comparator-hash-function))
  (cond-expand
   (snail-scheme
    (import (only (snail-scheme core) %hash-by-identity %eqv-hash %equal-hash %string-hash %string-ci-hash)))
   (else
    (import (rename (only (srfi 69) hash hash-by-identity string-hash string-ci-hash)
                    (hash %equal-hash) (hash-by-identity %hash-by-identity)
                    (string-hash %string-hash) (string-ci-hash %string-ci-hash)))
    (begin
      (define (%eqv-hash key)
        (if (or (number? key) (char? key)) (%equal-hash key) (%hash-by-identity key))))))
  (begin

    ;; ---- Hashes and constructors ----

    ;; SRFI 125 accepts one legacy argument without interpreting it as a bound.
    (define (legacy-hash-result code optional)
      (when (> (length optional) 1) (error "expected at most one legacy hash argument"))
      code)
    (define (hash key . optional) (legacy-hash-result (%equal-hash key) optional))
    (define (hash-by-identity key . optional) (legacy-hash-result (%hash-by-identity key) optional))
    (define (string-hash key . optional) (legacy-hash-result (%string-hash key) optional))
    (define (string-ci-hash key . optional) (legacy-hash-result (%string-ci-hash key) optional))

    (define-record-type <table>
      (make-table equality hash type buckets size version mutable?) hash-table?
      (equality hash-table-equivalence-function) (hash hash-table-hash-function)
      (type table-key-type) (buckets table-buckets set-table-buckets!)
      (size hash-table-size set-table-size!) (version table-version set-table-version!)
      (mutable? hash-table-mutable? set-table-mutable!))
    (define-record-type <entry>
      (make-entry hash key value) entry?
      (hash entry-hash) (key entry-key set-entry-key!) (value entry-value set-entry-value!))

    (define (default-hash equality)
      (cond ((eq? equality eq?) %hash-by-identity) ((eq? equality eqv?) %eqv-hash)
            ((eq? equality equal?) %equal-hash) ((eq? equality string=?) %string-hash)
            ((eq? equality string-ci=?) %string-ci-hash)
            (else (error "custom equality requires a hash function"))))

    ;; Optional implementation hints are accepted without promising weakness or
    ;; synchronization. Every entry is a normal strong Scheme reference.
    (define (make-hash-table comparison . options)
      (let* ((comparator (and (comparator? comparison) comparison))
             (equality (if comparator (comparator-equality-predicate comparator) comparison))
             (hash (if comparator (comparator-hash-function comparator)
                       (if (and (pair? options) (procedure? (car options))) (car options) (default-hash equality))))
             (type (if comparator (comparator-type-test-predicate comparator) (lambda (key) #t))))
        (unless (and (procedure? equality) (procedure? hash)) (error "hashable comparator required"))
        (make-table equality hash type (make-vector 31 '()) 0 0 #t)))

    ;; ---- Callback boundaries and keyed lookup ----

    (define (check-version table version)
      (unless (= version (table-version table)) (error "hash table structurally changed during callback")))
    (define (require-mutable table)
      (unless (hash-table-mutable? table) (error "immutable hash table")))
    (define (changed! table) (set-table-version! table (+ 1 (table-version table))))

    (define (key-hash table key)
      (let ((version (table-version table)))
        (unless ((table-key-type table) key) (error "hash table key type mismatch" key))
        (check-version table version)
        (let ((hash ((hash-table-hash-function table) key)))
          (check-version table version)
          (unless (and (exact-integer? hash) (>= hash 0)) (error "invalid hash value" hash))
          hash)))

    (define (find-entry table key hash)
      (let* ((buckets (table-buckets table)) (version (table-version table))
             (equality (hash-table-equivalence-function table)))
        (let loop ((bucket (vector-ref buckets (modulo hash (vector-length buckets)))))
          (if (null? bucket) #f
              (let* ((entry (car bucket))
                     (found (and (= hash (entry-hash entry)) (equality key (entry-key entry)))))
                (check-version table version)
                (if found entry (loop (cdr bucket))))))))

    (define (hash-table-ref table key . optional)
      (when (> (length optional) 2) (error "expected failure and success procedures"))
      (let ((entry (find-entry table key (key-hash table key))))
        (if entry (if (< (length optional) 2) (entry-value entry) ((cadr optional) (entry-value entry)))
            (if (null? optional) (error "hash table key not found" key) ((car optional))))))
    (define (hash-table-ref/default table key default)
      (let ((entry (find-entry table key (key-hash table key)))) (if entry (entry-value entry) default)))
    (define (hash-table-contains? table key) (if (find-entry table key (key-hash table key)) #t #f))
    (define hash-table-exists? hash-table-contains?)
    (define (hash-table-empty? table) (zero? (hash-table-size table)))

    ;; ---- Insertion, deletion, and resizing ----

    (define (insert-bucket! buckets entry)
      (let ((index (modulo (entry-hash entry) (vector-length buckets))))
        (vector-set! buckets index (cons entry (vector-ref buckets index)))))

    (define (grow! table)
      (let ((old (table-buckets table)))
        (when (> (hash-table-size table) (* 2 (vector-length old)))
          (let ((buckets (make-vector (+ 1 (* 2 (vector-length old))) '())))
            (let loop ((index 0))
              (unless (= index (vector-length old))
                (for-each (lambda (entry) (insert-bucket! buckets entry)) (vector-ref old index))
                (loop (+ index 1))))
            (set-table-buckets! table buckets)))))

    (define (set-key! table key value)
      (require-mutable table)
      (let* ((hash (key-hash table key)) (entry (find-entry table key hash)))
        (if entry (begin (set-entry-key! entry key) (set-entry-value! entry value))
            (begin (insert-bucket! (table-buckets table) (make-entry hash key value))
                   (set-table-size! table (+ 1 (hash-table-size table)))
                   (changed! table) (grow! table)))))
    (define (hash-table-set! table . pairs)
      (require-mutable table)
      (let loop ((pairs pairs))
        (unless (null? pairs)
          (when (null? (cdr pairs)) (error "expected alternating keys and values"))
          (set-key! table (car pairs) (cadr pairs)) (loop (cddr pairs)))))

    ;; Locate first; equality callbacks must finish before retaining bucket links.
    (define (delete-key! table key)
      (require-mutable table)
      (let* ((hash (key-hash table key)) (entry (find-entry table key hash)))
        (if (not entry) 0
            (let* ((buckets (table-buckets table)) (index (modulo hash (vector-length buckets))))
              (vector-set! buckets index (remove-entry entry (vector-ref buckets index)))
              (set-table-size! table (- (hash-table-size table) 1)) (changed! table) 1))))
    (define (remove-entry entry bucket)
      (if (eq? entry (car bucket)) (cdr bucket)
          (let loop ((previous bucket) (rest (cdr bucket)))
            (if (eq? entry (car rest))
                (begin (set-cdr! previous (cdr rest)) bucket)
                (loop rest (cdr rest))))))
    (define (hash-table-delete! table . keys)
      (require-mutable table)
      (let loop ((keys keys) (count 0))
        (if (null? keys) count (loop (cdr keys) (+ count (delete-key! table (car keys)))))))
    (define (hash-table-clear! table)
      (require-mutable table)
      (set-table-buckets! table (make-vector 31 '())) (set-table-size! table 0) (changed! table))

    ;; User callbacks may add entries or grow the table. The subsequent set is a
    ;; fresh lookup, never a write through a slot saved across that callback.
    (define (hash-table-intern! table key failure)
      (hash-table-ref table key (lambda () (let ((value (failure))) (set-key! table key value) value))))
    (define (hash-table-update! table key updater . optional)
      (require-mutable table)
      (let ((value (apply hash-table-ref table key optional))) (set-key! table key (updater value))))
    (define (hash-table-update!/default table key updater default)
      (hash-table-update! table key updater (lambda () default)))

    ;; ---- Traversal and whole-table operations ----

    (define (hash-table-fold first second third)
      (if (hash-table? first) (fold-table second third first) (fold-table first second third)))
    (define (fold-table procedure initial table)
      (let ((version (table-version table)) (buckets (table-buckets table)))
        (let loop ((index 0) (bucket '()) (result initial))
          (cond ((pair? bucket)
                 (let* ((entry (car bucket)) (result (procedure (entry-key entry) (entry-value entry) result)))
                   (check-version table version) (loop index (cdr bucket) result)))
                ((= index (vector-length buckets)) result)
                (else (loop (+ index 1) (vector-ref buckets index) result))))))
    (define (hash-table-for-each procedure table)
      (hash-table-fold (lambda (key value ignored) (procedure key value) #f) #f table))
    (define (hash-table-walk table procedure) (hash-table-for-each procedure table))
    (define (hash-table->alist table) (hash-table-fold (lambda (key value result) (cons (cons key value) result)) '() table))
    (define (hash-table-keys table) (hash-table-fold (lambda (key value result) (cons key result)) '() table))
    (define (hash-table-values table) (hash-table-fold (lambda (key value result) (cons value result)) '() table))
    (define (hash-table-entries table)
      (let ((entries (hash-table->alist table))) (values (map car entries) (map cdr entries))))
    (define (hash-table-map->list procedure table)
      (hash-table-fold (lambda (key value result) (cons (procedure key value) result)) '() table))
    (define (hash-table-count predicate table)
      (hash-table-fold (lambda (key value result) (if (predicate key value) (+ result 1) result)) 0 table))

    (define (hash-table-find procedure table failure)
      (let ((version (table-version table)) (buckets (table-buckets table)))
        (let loop ((index 0) (bucket '()))
          (cond ((pair? bucket)
                 (let* ((entry (car bucket)) (result (procedure (entry-key entry) (entry-value entry))))
                   (check-version table version)
                   (if result result (loop index (cdr bucket)))))
                ((= index (vector-length buckets)) (failure))
                (else (loop (+ index 1) (vector-ref buckets index)))))))
    (define (hash-table-pop! table)
      (require-mutable table)
      (let ((entry (hash-table-find cons table (lambda () (error "empty hash table")))))
        (delete-key! table (car entry)) (values (car entry) (cdr entry))))
    (define (hash-table-map! procedure table)
      (require-mutable table)
      (hash-table-for-each (lambda (key value) (set-key! table key (procedure key value))) table))
    (define (hash-table-prune! predicate table)
      (require-mutable table)
      (let ((keys (hash-table-fold (lambda (key value keys) (if (predicate key value) (cons key keys) keys)) '() table)))
        (apply hash-table-delete! table keys)))

    ;; ---- Construction from entries and copying ----

    (define (hash-table comparison . pairs)
      (let ((table (make-hash-table comparison)))
        (let loop ((pairs pairs))
          (unless (null? pairs)
            (when (or (null? (cdr pairs)) (hash-table-contains? table (car pairs))) (error "invalid hash-table entries"))
            (set-key! table (car pairs) (cadr pairs)) (loop (cddr pairs))))
        (set-table-mutable! table #f) table))
    (define (alist->hash-table entries comparison . options)
      (let ((table (apply make-hash-table comparison options)))
        (for-each (lambda (entry)
                    (unless (hash-table-contains? table (car entry)) (set-key! table (car entry) (cdr entry)))) entries)
        table))
    (define (hash-table-unfold stop? mapper successor seed comparison . options)
      (let ((table (apply make-hash-table comparison options)))
        (let loop ((seed seed))
          (if (stop? seed) table
              (begin (call-with-values (lambda () (mapper seed)) (lambda (key value) (set-key! table key value)))
                     (loop (successor seed)))))))
    (define (hash-table-empty-copy table)
      (make-table (hash-table-equivalence-function table) (hash-table-hash-function table)
                  (table-key-type table) (make-vector 31 '()) 0 0 #t))
    (define (hash-table-copy table . optional)
      (when (> (length optional) 1) (error "expected at most one mutability argument"))
      (let ((copy (hash-table-empty-copy table)))
        (hash-table-for-each (lambda (key value) (set-key! copy key value)) table)
        (set-table-mutable! copy (and (pair? optional) (car optional))) copy))
    (define (hash-table-map procedure comparison table)
      (let ((copy (make-hash-table comparison)))
        (hash-table-for-each (lambda (key value) (set-key! copy key (procedure value))) table) copy))

    ;; ---- Tables as sets ----

    (define (hash-table=? comparator first second)
      (and (= (hash-table-size first) (hash-table-size second))
           (let loop ((entries (hash-table->alist first)))
             (or (null? entries)
                 (and (hash-table-ref second (caar entries) (lambda () #f)
                                      (lambda (value) ((comparator-equality-predicate comparator) (cdar entries) value)))
                      (loop (cdr entries)))))))
    (define (hash-table-union! first second)
      (require-mutable first)
      (hash-table-for-each (lambda (key value) (unless (hash-table-contains? first key) (set-key! first key value))) second)
      first)
    (define hash-table-merge! hash-table-union!)
    (define (hash-table-intersection! first second)
      (hash-table-prune! (lambda (key value) (not (hash-table-contains? second key))) first) first)
    (define (hash-table-difference! first second)
      (require-mutable first)
      (for-each (lambda (key) (delete-key! first key)) (hash-table-keys second)) first)
    (define (hash-table-xor! first second)
      (require-mutable first)
      (for-each (lambda (entry) (if (hash-table-contains? first (car entry)) (delete-key! first (car entry))
                                    (set-key! first (car entry) (cdr entry)))) (hash-table->alist second)) first))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-hash-table)
    (import (snail-scheme test-utils))
    (begin
      (define (test-identity-keys)
        (let ((table (make-hash-table eq?)) (keys (make-vector 2000)))
          (do-integers 2000 (lambda (i) (let ((key (cons 1 2))) (vector-set! keys i key) (hash-table-set! table key i))))
          (do-integers 2000 (lambda (i) (set-car! (vector-ref keys i) i)
                                    (expect (hash-table-ref table (vector-ref keys i)) i)))
          (expect (hash-table-size table) 2000)
          (hash-table-set! table #f #f table table)
          (expect (hash-table-contains? table #f) #t)
          (expect (hash-table-ref table table) table)
          (expect (hash-table-delete! table #f #f table) 2)))
      (define (do-integers count procedure)
        (let loop ((index 0)) (unless (= index count) (procedure index) (loop (+ index 1)))))
      (define (test-collisions-and-callbacks)
        (let ((table (make-hash-table equal? (lambda (key) 0))))
          (do-integers 100 (lambda (i) (hash-table-set! table (list i) i)))
          (expect (hash-table-ref table '(42) (lambda () 'missing) (lambda (value) (+ value 1))) 43)
          (hash-table-update! table '(42) (lambda (old) (hash-table-clear! table) (+ old 1)))
          (expect (hash-table->alist table) '(((42) . 43)))
          (expect (hash-table-intern! table '(9) (lambda () (hash-table-set! table '(9) 'during) 'after)) 'after)
          (expect (hash-table-ref table '(9)) 'after)))

      (define (test-traversal-and-representatives)
        (let ((table (make-hash-table equal?)) (first (list 'key)) (last (list 'key)))
          (hash-table-set! table first 1 last 2)
          (expect (eq? (car (hash-table-keys table)) last) #t)
          (hash-table-for-each (lambda (key value) (values)) table)
          (hash-table-for-each (lambda (key value) (values 1 2)) table)
          (expect (hash-table-find (lambda (key value) value) table (lambda () 'missing)) 2)
          (expect (hash first 'ignored) (hash last))
          (expect (guard (failure (else 'caught))
                    (hash-table-find (lambda (key value) (hash-table-clear! table) #t)
                                     table (lambda () #f))) 'caught)))

      (define (test-immutable-table)
        (let ((table (hash-table-copy (alist->hash-table '((a . 1)) eq?))))
          (expect (hash-table-ref table 'a) 1)
          (expect (hash-table-mutable? table) #f)
          (for-each (lambda (operation)
                      (expect (guard (failure (else 'caught)) (operation)) 'caught))
                    (list (lambda () (hash-table-set! table 'a 2))
                          (lambda () (hash-table-delete! table 'a))
                          (lambda () (hash-table-pop! table))
                          (lambda () (hash-table-clear! table))))))
      (define (test-hash-table)
        (run-test test-identity-keys)
        (run-test test-collisions-and-callbacks)
        (run-test test-traversal-and-representatives)
        (run-test test-immutable-table))))))
