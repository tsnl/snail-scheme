;; Storage and callback contracts for the original compiler's collection
;; algorithms. compiler_port.py adapts their complete source forms in place;
;; this module does not substitute a different sort, set or graph algorithm.

;; ---- Proper-list storage and fixed identity callbacks ----

(define-syntax compiler-cond
  (syntax-rules (else)
    ((_ (else body ...)) (begin body ...))
    ((_ (test body ...) rest ...)
     (if test (begin body ...) (compiler-cond rest ...)))))
(define (compiler-pair? value) (not (compiler-null? value)))
(define (compiler-cddr value) (compiler-cdr (compiler-cdr value)))
(define (compiler-length values)
  (let loop ((values values) (count 0))
    (if (compiler-null? values) count (loop (compiler-cdr values) (+ count 1)))))
(define (compiler-reverse values)
  (let loop ((values values) (reversed (compiler-empty)))
    (if (compiler-null? values) reversed
        (loop (compiler-cdr values) (compiler-cons (compiler-car values) reversed)))))
(define (compiler-list-ref values index)
  (if (< index 0) (datum-fail "list-ref: negative index")
      (compiler-car (nth-after values index))))
(define (compiler-cadr values) (compiler-car (compiler-cdr values)))
(define (compiler-caddr values) (compiler-car (compiler-cddr values)))
(define (compiler-cdddr values) (compiler-cdr (compiler-cddr values)))
(define (compiler-cadddr values) (compiler-car (compiler-cdddr values)))

;; All append call sites over these homogeneous spines have proper tails.
;; Fold right so only the last input spine is shared; zero inputs returns empty.
(: compiler-append-lists (All (T) (-> (CompilerList (CompilerList T)) (CompilerList T))))
(define (compiler-append-lists lists)
  (if (compiler-null? lists) (compiler-empty)
      (if (compiler-null? (compiler-cdr lists)) (compiler-car lists)
          (compiler-append (compiler-car lists) (compiler-append-lists (compiler-cdr lists))))))

;; A hit carries the actual matching tail, not a copied list or a Boolean.
;; Equality arguments retain memq's needle/element roles. The callbacks used by
;; the compiler are pure identity comparisons selected for each concrete type.
(: compiler-memq (All (T)
                      (-> (-> T T Bool) T (CompilerList T) (CompilerOption (CompilerList T)))))
(define (compiler-memq same? value values)
  (if (compiler-null? values) (compiler-none)
      (if (same? value (compiler-car values)) (compiler-some values)
          (compiler-memq same? value (compiler-cdr values)))))

;; Association searches return the first actual entry, preserving mutable
;; value aliases. The compiler selects pure identity/equivalence predicates;
;; it does not expose a user callback from Scheme assq/assv/assoc.
(: compiler-assoc (All (K V)
                       (-> (-> K K Bool) K (CompilerList (CompilerPair K V))
                           (CompilerOption (CompilerPair K V)))))
(define (compiler-assoc same? key entries)
  (if (compiler-null? entries) (compiler-none)
      (let ((entry (compiler-car entries)))
        (if (same? key (compiler-pair-first entry)) (compiler-some entry)
            (compiler-assoc same? key (compiler-cdr entries))))))

(: pos-in-list (All (T)
                    (-> (-> T T Bool) T (CompilerList T) (CompilerOption I64))))
(: string-pos-in-list (-> String (CompilerList String) (CompilerOption I64)))
(: nth-after (All (T) (-> (CompilerList T) I64 (CompilerList T))))
(: pair-up (All (A B)
                (-> (CompilerList A) (CompilerList B) (CompilerList (CompilerPair A B)))))
(: my-last-pair (All (T) (-> (CompilerList T) (CompilerList T))))
(: sort-list (All (T) (-> (CompilerList T) (-> T T Bool) (CompilerList T))))
(: lst->vector (All (T) (-> (CompilerList T) (Vector T))))
(: vector->lst (All (T) (-> (Vector T) (CompilerList T))))
(: lst->string (-> (CompilerList Char) String))
(: string->lst (-> String (CompilerList Char)))

;; ---- Ordered occurrence sets keep their original folds and scans ----

(: list->set (All (T) (-> (CompilerList T) (CompilerList T))))
(: set->list (All (T) (-> (CompilerList T) (CompilerList T))))
(: set-empty (All (T) (-> (CompilerList T))))
(: set-empty? (All (T) (-> (CompilerList T) Bool)))
(: set-member? (All (T)
                    (-> (-> T T Bool) T (CompilerList T) (CompilerOption (CompilerList T)))))
(: set-singleton (All (T) (-> T (CompilerList T))))
(: set-adjoin (All (T) (-> (-> T T Bool) (CompilerList T) T (CompilerList T))))
(: set-remove (All (T) (-> (-> T T Bool) (CompilerList T) T (CompilerList T))))
(: set-equal? (All (T) (-> (-> T T Bool) (CompilerList T) (CompilerList T) Bool)))
;; Source rest arguments become an explicit list. Dynamic apply passes its
;; existing list to the same left fold; it never dispatches arbitrary arities.
(: set-union (All (T)
                  (-> (-> T T Bool) (CompilerList (CompilerList T)) (CompilerList T))))
(: set-difference (All (T)
                       (-> (-> T T Bool) (CompilerList T) (CompilerList (CompilerList T)) (CompilerList T))))
(: set-intersection (All (T)
                         (-> (-> T T Bool) (CompilerList T) (CompilerList (CompilerList T)) (CompilerList T))))
(: n-ary (All (T) (-> (-> T T T) T (CompilerList T) T)))
(: set-keep (All (T) (-> (-> T Bool) (CompilerList T) (CompilerList T))))
(: set-every? (All (T) (-> (-> T Bool) (CompilerList T) Bool)))
(: set-map (All (A B) (-> (-> A B) (CompilerList A) (CompilerList B))))

;; ---- Dependency labels and graph wrapper identities are distinct ----

;; Only pt-recursive-let constructs this graph. Its labels are variables, and
;; edges are variable lists. The source never mutates either graph-node field.
;; A fresh label cell retains the identity of each original vector wrapper;
;; different graph nodes may still refer to the same variable label.
(define-data CompilerDependencyNode
  (compiler-dependency-node
   (label (Ref CompilerVariable) compiler-dependency-label-cell)
   (edges (CompilerList CompilerVariable) compiler-dependency-edges)))
(define (compiler-dependency-eq? left right)
  (ref-eq? (compiler-dependency-label-cell left) (compiler-dependency-label-cell right)))
(: make-gnode (-> CompilerVariable (CompilerList CompilerVariable) CompilerDependencyNode))
(: gnode-label (-> CompilerDependencyNode CompilerVariable))
(: gnode-edges (-> CompilerDependencyNode (CompilerList CompilerVariable)))
(: gnode-find (-> CompilerVariable (CompilerList CompilerDependencyNode)
                  (CompilerOption CompilerDependencyNode)))
(: transitive-closure (-> (CompilerList CompilerDependencyNode) (CompilerList CompilerDependencyNode)))
(: topological-sort (-> (CompilerList CompilerDependencyNode) (CompilerList (CompilerList CompilerVariable))))
(: remove-no-edges (-> (CompilerList CompilerDependencyNode)
                       (CompilerOption (CompilerList CompilerDependencyNode))))
(: remove-cycle (-> (CompilerList CompilerDependencyNode) (CompilerList CompilerDependencyNode)))

;; ---- Counter and queue failures use the existing compiler abort result ----

(: make-counter (-> I64 I64 (-> (CompilerResult I64)) (-> (CompilerResult I64))))
(: list->queue (All (T)
                    (-> (CompilerList T) (CompilerPair (CompilerList T) (CompilerList T)))))
(: queue->list (All (T)
                    (-> (CompilerPair (CompilerList T) (CompilerList T)) (CompilerList T))))
(: queue-empty (All (T) (-> (CompilerPair (CompilerList T) (CompilerList T)))))
(: queue-empty? (All (T) (-> (CompilerPair (CompilerList T) (CompilerList T)) Bool)))
(: queue-get! (All (T)
                   (-> (CompilerPair (CompilerList T) (CompilerList T)) (CompilerResult T))))
(: queue-put! (All (T) (-> (CompilerPair (CompilerList T) (CompilerList T)) T T)))

;; ---- Fallible callbacks stop before later callbacks and spine reads ----

;; The pure helpers above remain pure. These counterparts are used only where
;; an actual callback can abort. Left-to-right callback evaluation is explicit
;; in both targets; source Scheme does not require that order for map or cons.
(: compiler-result-cons (All (T)
                             (-> T (CompilerResult (CompilerList T)) (CompilerResult (CompilerList T)))))
(define (compiler-result-cons first result)
  (match result
    ((compiler-success rest) (compiler-success (compiler-cons first rest)))
    ((compiler-failure) (compiler-failure))))
(: compiler-result-map (All (A B)
                            (-> (-> A (CompilerResult B)) (CompilerList A) (CompilerResult (CompilerList B)))))
(define (compiler-result-map procedure values)
  (if (compiler-null? values) (compiler-success (compiler-empty))
      (match (procedure (compiler-car values))
        ((compiler-failure) (compiler-failure))
        ((compiler-success first)
         (compiler-result-cons first (compiler-result-map procedure (compiler-cdr values)))))))
(: compiler-result-keep (All (T)
                             (-> (-> T (CompilerResult Bool)) (CompilerList T) (CompilerResult (CompilerList T)))))
(define (compiler-result-keep predicate values)
  (if (compiler-null? values) (compiler-success (compiler-empty))
      (match (predicate (compiler-car values))
        ((compiler-failure) (compiler-failure))
        ((compiler-success keep?)
         (if keep?
             (let ((first (compiler-car values)))
               (compiler-result-cons first (compiler-result-keep predicate (compiler-cdr values))))
             (compiler-result-keep predicate (compiler-cdr values)))))))
(: compiler-result-every? (All (T)
                               (-> (-> T (CompilerResult Bool)) (CompilerList T) (CompilerResult Bool))))
(define (compiler-result-every? predicate values)
  (if (compiler-null? values) (compiler-success #t)
      (match (predicate (compiler-car values))
        ((compiler-failure) (compiler-failure))
        ((compiler-success keep?)
         (if keep? (compiler-result-every? predicate (compiler-cdr values))
             (compiler-success #f))))))
(: compiler-result-for-each (All (A B)
                                 (-> (-> A (CompilerResult B)) (CompilerList A) (CompilerResult Unit))))
(define (compiler-result-for-each procedure values)
  (if (compiler-null? values) (compiler-success (unit))
      (match (procedure (compiler-car values))
        ((compiler-failure) (compiler-failure))
        ((compiler-success ignored) (compiler-result-for-each procedure (compiler-cdr values))))))
