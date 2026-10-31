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
  ((say (-> String Unit))))

;; ANCHOR: store
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(struct Directory
  ((root String)))

(struct Table
  ((objects (List (Pair String String)))))

(instance (Store (! console) Directory)
  (define (fetch-object directory name)
    (write-line (string-append "reading " (Directory-root directory) "/" name))
    (string-append "the bytes of " name)))

(instance (Store (!) Table)
  (define (fetch-object table name)
    (match (assoc-ref (Table-objects table) name)
      ((Some text) text)
      ((None) "missing"))))

(: fetch-twice (All (e S) (requires (Store e S) (Copy S)) (-> S String String ! e)))
(define (fetch-twice store name)
  (string-append (fetch-object store name) " / " (fetch-object store name)))
;; ANCHOR_END: store

;; A table's reads are total, so a total function may make them.
(: from-table (-> Table String String))
(define (from-table table name)
  (fetch-twice table name))

;; A requirement may bound the row instead: `peek` is total, and takes any
;; store whose reads are.
(: peek (All (S) (requires (Store (!) S)) (-> S String String)))
(define (peek store name)
  (fetch-object store name))

;; The row a generic function performs holds its other arguments' effects
;; too, a control effect among them: `ask` suspends the fetch between its
;; reads, whichever store it reads.
(effect Ask
  ((ctl ask (-> String String))))

(: fetch-asked (All (e S) (requires (Store e S) (Copy S)) (-> S (-> String String ! e) String ! e)))
(define (fetch-asked store choose)
  (let ((name (choose "which?")))
    (string-append (fetch-object store name) " then " (fetch-object store (choose "again?")))))

(: answering (All (e) (-> (-> String ! Ask e) String ! e)))
(define (answering body)
  (handle Ask ((ask (lambda (question resume) (resume (if (string=? question "which?") "a" "b")))))
    (body)))

;; ANCHOR: logged
(struct (Logged S)
  ((inner S)))

(instance (Store (! log e) (Logged S))
  (requires (Store e S))
  (define (fetch-object logged name)
    (say (string-append "fetching " name))
    (match logged
      ((Logged inner) (fetch-object inner name)))))
;; ANCHOR_END: logged

;; The log is printed here; what the inner store performs passes through.
(: logging (All (e) (-> (-> String ! log e) String ! console e)))
(define (logging body)
  (handle log
      ((say (lambda (line) (write-line (string-append "log: " line)))))
    (body)))

(write-line (fetch-twice (Directory "assets") "hero"))
(write-line (from-table (Table (list (Pair "hero" "held"))) "hero"))
(write-line (peek (Table (list (Pair "villain" "kept"))) "villain"))
(write-line (answering (lambda () (fetch-asked (Table (list (Pair "a" "A") (Pair "b" "B"))) ask))))
(write-line (answering (lambda () (fetch-asked (Directory "d") ask))))
(write-line (logging (lambda () (fetch-twice (Logged (Table (list (Pair "a" "b")))) "a"))))
(write-line (logging (lambda () (fetch-object (Logged (Directory "pack")) "villain"))))
