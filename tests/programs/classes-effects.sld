(import
 (snail core base)
 (snail core io))

;; A class whose instances each perform their own row. `Store`'s method
;; performs `e`, a row its instances write in their heads: reading a
;; directory prints, reading a table performs nothing, and a logged store
;; performs `log` and the row of the store it wraps. A generic function
;; requires the class at a row of its own, and performs that row; a
;; caller then performs whatever its store's instance does.
(effect log
  ((say (Fn String → Unit))))

;; ANCHOR: store
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Directory
  ((root String)))

(struct Table
  ((objects (List (Pair String String)))))

(instance (Store (! output-port) Directory)
  (define fetch-object
    (lambda (directory name) (write-line (string-append "reading " (● directory root) "/" name))
            (string-append "the bytes of " name))))

(instance (Store (!) Table)
  (define fetch-object
    (lambda (table name) (match (assoc-ref (● table objects) name)
                           ((Some text) text)
                           ((None) "missing")))))

(define (fetch-twice (store S) (name String))
  (→ String)
  (! e)
  (∀ (e S))
  (⊨ (Store e S) (Copy S) (Drop e S))
  (string-append (fetch-object store name) " / " (fetch-object store name)))

;; ANCHOR_END: store

;; A table's reads are total, so a total function may make them.
(define (from-table (table Table) (name String)) (→ String)
  (fetch-twice table name))

;; A requirement may bound the row instead: `peek` is total, and takes any
;; store whose reads are.
(define (peek (store S) (name String)) (→ String) (∀ (S)) (⊨ (Store (!) S))
  (fetch-object store name))

;; The row a generic function performs holds its other arguments' effects
;; too, a control effect among them: `ask` suspends the fetch between its
;; reads, whichever store it reads.
(effect Ask
  ((ctl ask (Fn String → String))))

(define (fetch-asked (store S) (choose (Fn String → String ! e)))
  (→ String)
  (! e)
  (∀ (e S))
  (⊨ (Store e S) (Copy S) (Drop e S))
  (let ((name (choose "which?")))
    (string-append (fetch-object store name) " then " (fetch-object store (choose "again?")))))

(define (answering (body (FnOnce → String ! Ask e))) (→ String) (! e) (∀ (e))
  (handle Ask ((ask (lambda (question resume) (resume (if (string=? question "which?") "a" "b")))))
    (body)))

;; ANCHOR: logged
(struct (Logged S)
  ((inner S)))

(instance (Store (! log e) (Logged S))
  (⊨ (Store e S))
  (define fetch-object
    (lambda (logged name) (say (string-append "fetching " name))
            (match logged
              ((Logged inner) (fetch-object inner name))))))

;; ANCHOR_END: logged

;; The log is printed here; what the inner store performs passes through.
(define (logging (body (FnOnce → String ! log e))) (→ String) (! output-port e) (∀ (e))
  (handle log
      ((say (lambda (line) (write-line (string-append "log: " line)))))
    (body)))

(define main
  (lambda ()
    (write-line (fetch-twice (Directory "assets") "hero"))
    (write-line (from-table (Table (list (Pair "hero" "held"))) "hero"))
    (write-line (peek (Table (list (Pair "villain" "kept"))) "villain"))
    (write-line
     (answering (lambda () (fetch-asked (Table (list (Pair "a" "A") (Pair "b" "B"))) ask))))
    (write-line (answering (lambda () (fetch-asked (Directory "d") ask))))
    (write-line (logging (lambda () (fetch-twice (Logged (Table (list (Pair "a" "b")))) "a"))))
    (write-line (logging (lambda () (fetch-object (Logged (Directory "pack")) "villain"))))
    (unit)))
