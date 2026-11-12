;; Allocation placement on a control-flow graph. Every fixed-size allocation
;; starts as a frame candidate. Reference flow, escape, and overlapping dynamic
;; instances decide which sites require the heap. This graph has no Wasm ABI.
(define-library (snail shell compiler allocation)
  (export
   FlowOperation FlowPlain FlowCopy FlowConstruct FlowRead FlowWrite FlowOpaque FlowEscape
   FlowNode FlowAllocation FlowGraph frame-allocations)
  (import
   (snail core base)
   (snail core table))
  (begin

    ;; ---- Graph contract ----

    ;; Values and program points have separate integer identities. Origin zero
    ;; denotes external memory; positive origins name allocation sites. Copies
    ;; include local assignments and values merged at control-flow joins.
    (enum FlowOperation
      (FlowPlain)
      (FlowCopy
       ((result I64)
        (sources (List I64))))
      (FlowConstruct
       ((result I64)
        (site I64)
        (fields (List I64))))
      (FlowRead
       ((result I64)
        (object I64)))
      (FlowWrite
       ((object I64)
        (value I64)))
      (FlowOpaque
       ((result I64)
        (arguments (List I64))))
      (FlowEscape
       ((values (List I64)))))

    (struct FlowNode
      ((point I64)
       (operation FlowOperation)
       (uses (List I64))
       (defines (List I64))
       (successors (List I64))))

    (struct FlowAllocation
      ((site I64)
       (point I64)
       (fixed? Bool)))

    (struct FlowGraph
      ((entry I64)
       (nodes (List FlowNode))
       (allocations (List FlowAllocation))
       (parameters (List I64))))

    ;; ---- Finite sets ----

    (: union (impl (Fn (List I64) (List I64) -> (List I64))))
    (define (union left right)
      (fold-left (lambda (set item) (if (member? item set) set (Cons item set))) left right))

    (: entries (impl (Fn (Table (List I64)) I64 -> (List I64))))
    (define (entries table key)
      (match (table-ref table (i64->string key)) ((Some items) items) (_ (Nil))))

    (: gather (impl (Fn (Table (List I64)) (List I64) -> (List I64))))
    (define (gather table keys)
      (fold-left (lambda (items key) (union items (entries table key))) (Nil) keys))

    ;; ---- Reference flow ----

    ;; Local assignments are flow insensitive: a value contains every origin it
    ;; can hold on any path. Each object has one set for all pointer fields.
    ;; These conservative unions terminate even for aliases and cyclic objects.
    ;; Scalars must have no local allocation origins in the graph adapter.
    (struct Reachability
      ((values (Table (List I64)))
       (contents (Table (List I64)))
       (changes I64)))

    (: add-values (impl (Fn Reachability I64 (List I64) -> Reachability)))
    (define (add-values state value origins)
      (let* ((old (entries (::values state) value)) (next (union old origins)))
        (if (= (length old) (length next)) state
            (Reachability (table-set (::values state) (i64->string value) next)
                          (::contents state) (+ (::changes state) 1)))))

    (: add-contents (impl (Fn Reachability I64 (List I64) -> Reachability)))
    (define (add-contents state site origins)
      (let* ((old (entries (::contents state) site)) (next (union old origins)))
        (if (= (length old) (length next)) state
            (Reachability (::values state)
                          (table-set (::contents state) (i64->string site) next)
                          (+ (::changes state) 1)))))

    (: read-origins (impl (Fn Reachability (List I64) -> (List I64))))
    (define (read-origins state objects)
      (fold-left (lambda (origins object)
                   (union origins (if (= object 0) (list 0)
                                      (entries (::contents state) object)))) (Nil) objects))

    (: follow-operation (impl (Fn Reachability FlowNode -> Reachability)))
    (define (follow-operation state node)
      (match (::operation node)
        ((FlowCopy result sources) (add-values state result (gather (::values state) sources)))
        ((FlowConstruct result site fields)
         (add-contents (add-values state result (list site)) site (gather (::values state) fields)))
        ((FlowRead result object)
         (add-values state result (read-origins state (entries (::values state) object))))
        ((FlowWrite object value)
         (fold-left (lambda (state site)
                      (if (= site 0) state
                          (add-contents state site (entries (::values state) value))))
                    state (entries (::values state) object)))
        ((FlowOpaque result _) (add-values state result (list 0)))
        (_ state)))

    (: reference-flow (impl (Fn FlowGraph -> Reachability)))
    (define (reference-flow graph)
      (let loop ((state (fold-left (lambda (state parameter) (add-values state parameter (list 0)))
                                   (Reachability empty-table empty-table 0) (::parameters graph))))
        (let ((next (fold-left follow-operation state (::nodes graph))))
          (if (= (::changes state) (::changes next)) next (loop next)))))

    ;; ---- Values live at each point ----

    (struct LiveValues
      ((values (Table (List I64)))
       (changes I64)))

    (: live-before (impl (Fn LiveValues FlowNode -> LiveValues)))
    (define (live-before state node)
      (let* ((after (gather (::values state) (::successors node)))
             (before (union (::uses node)
                            (filter (lambda (value) (not (member? value (::defines node)))) after)))
             (old (entries (::values state) (::point node))))
        (if (= (length before) (length old)) state
            (LiveValues (table-set (::values state) (i64->string (::point node)) before)
                        (+ (::changes state) 1)))))

    (: live-values (impl (Fn FlowGraph -> (Table (List I64)))))
    (define (live-values graph)
      (let loop ((state (LiveValues empty-table 0)))
        (let ((next (fold-left live-before state (reverse (::nodes graph)))))
          (if (= (::changes state) (::changes next)) (::values next) (loop next)))))

    ;; ---- Escape and containment ----

    (: escaping-values (impl (Fn Reachability FlowNode -> (List I64))))
    (define (escaping-values state node)
      (match (::operation node)
        ((FlowEscape values) (gather (::values state) values))
        ((FlowOpaque _ arguments) (gather (::values state) arguments))
        ((FlowWrite object value)
         (if (member? 0 (entries (::values state) object))
             (entries (::values state) value) (Nil)))
        (_ (Nil))))

    ;; A heap object cannot contain a frame address. Promotion therefore follows
    ;; containment transitively, including aliases and closure/continuation
    ;; captures. Reading a field of external memory remains external; a prior
    ;; store of a local object into it already requires promotion.
    (: reachable-objects (impl (Fn Reachability (List I64) -> (List I64))))
    (define (reachable-objects state roots)
      (let loop ((pending roots) (seen (Nil)))
        (match pending
          ((Nil) seen)
          ((Cons site rest)
           (if (member? site seen) (loop rest seen)
               (loop (append (entries (::contents state) site) rest) (Cons site seen)))))))

    ;; ---- Repeated allocations ----

    (: node-table (impl (Fn FlowGraph -> (Table FlowNode))))
    (define (node-table graph)
      (fold-left (lambda (table node) (table-set table (i64->string (::point node)) node))
                 empty-table (::nodes graph)))

    (: successors (impl (Fn (Table FlowNode) I64 -> (List I64))))
    (define (successors nodes point)
      (match (table-ref nodes (i64->string point))
        ((Some node) (::successors node))
        (_ (panic "internal error: missing allocation-flow point"))))

    (: repeats? (impl (Fn (Table FlowNode) I64 -> Bool)))
    (define (repeats? nodes point)
      (let loop ((pending (successors nodes point)) (seen empty-table))
        (match pending
          ((Nil) #f)
          ((Cons next rest)
           (cond ((= next point) #t)
                 ((table-contains? seen (i64->string next)) (loop rest seen))
                 (else (loop (append (successors nodes next) rest)
                             (table-set seen (i64->string next) #t))))))))

    ;; Reusing a site is unsafe if an earlier instance can still be reached at
    ;; its next execution. Liveness must include objects reachable through live
    ;; containers, not just direct local references. Each recursive invocation
    ;; has a separate frame, so calls are not intraprocedural backedges.
    (: overlapping? (impl (Fn Reachability (Table (List I64)) FlowAllocation -> Bool)))
    (define (overlapping? state live allocation)
      (member? (::site allocation)
               (reachable-objects state
                                  (gather (::values state) (entries live (::point allocation))))))

    ;; ---- Placement ----

    (: frame-allocations (impl (Fn FlowGraph -> (List I64))))
    (define (frame-allocations graph)
      (let* ((state (reference-flow graph))
             (escaped (fold-left (lambda (sites node) (union sites (escaping-values state node)))
                                 (Nil) (::nodes graph)))
             (heap (reachable-objects state
                                      (append escaped
                                              (map ::site
                                                   (filter (lambda (allocation)
                                                             (not (::fixed? allocation)))
                                                           (::allocations graph))))))
             (candidates (filter (lambda (allocation) (not (member? (::site allocation) heap)))
                                 (::allocations graph))))
        (if (null? candidates) (Nil) (exclude-overlaps graph state candidates))))

    ;; Most functions have no repeated candidate. Avoid building liveness sets
    ;; for those functions, and for allocations already promoted by escape.
    (: exclude-overlaps (impl (Fn FlowGraph Reachability (List FlowAllocation) -> (List I64))))
    (define (exclude-overlaps graph state candidates)
      (let* ((nodes (node-table graph))
             (repeated
              (filter (lambda (allocation) (repeats? nodes (::point allocation))) candidates))
             (live (if (null? repeated) empty-table (live-values graph)))
             (heap (reachable-objects state
                                      (map ::site
                                           (filter (lambda (allocation)
                                                     (overlapping? state live allocation))
                                                   repeated)))))
        (filter (lambda (site) (not (member? site heap))) (map ::site candidates))))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-allocation)
    (import
     (snail stage0 testing))
    (begin
      (define (placed nodes allocations parameters)
        (frame-allocations (FlowGraph 1 nodes allocations parameters)))

      (define (test-allocation)
        ;; A returned field promotes the child, not its local container.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2
                                        (FlowConstruct 20 2 (list 10))
                                        (list 10)
                                        (list 20)
                                        (list 3))
                              (FlowNode 3 (FlowRead 30 20) (list 20) (list 30) (list 4))
                              (FlowNode 4 (FlowEscape (list 30)) (list 30) (Nil) (Nil)))
                        (list (FlowAllocation 1 1 #t) (FlowAllocation 2 2 #t)) (Nil)) (list 2))
        ;; Capturing that same child in an escaping closure promotes both.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2
                                        (FlowConstruct 20 2 (list 10))
                                        (list 10)
                                        (list 20)
                                        (list 3))
                              (FlowNode 3 (FlowEscape (list 20)) (list 20) (Nil) (Nil)))
                        (list (FlowAllocation 1 1 #t) (FlowAllocation 2 2 #t)) (Nil)) (Nil))
        ;; Dynamic extents use the heap, so their contained objects must too.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2 (FlowConstruct 20 2 (list 10)) (list 10) (list 20) (Nil)))
                        (list (FlowAllocation 1 1 #t) (FlowAllocation 2 2 #f)) (Nil)) (Nil))
        ;; Stores through an incoming pointer and unknown calls can retain.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2 (FlowWrite 0 10) (list 0 10) (Nil) (Nil)))
                        (list (FlowAllocation 1 1 #t)) (list 0)) (Nil))
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2 (FlowOpaque 20 (list 10)) (list 10) (list 20) (Nil)))
                        (list (FlowAllocation 1 1 #t)) (Nil)) (Nil))
        (test-repeated-allocations))

      (define (test-repeated-allocations)
        ;; Killing the previous local before its next use permits slot reuse.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2 (FlowCopy 20 (list 10)) (list 10) (list 20) (list 3))
                              (FlowNode 3 (FlowPlain) (list 20) (Nil) (list 1)))
                        (list (FlowAllocation 1 1 #t)) (Nil)) (list 1))
        ;; A previous instance consumed by the next construction overlaps it.
        (expect
         (placed (list (FlowNode 1 (FlowConstruct 10 1 (list 20)) (list 20) (list 10) (list 2))
                       (FlowNode 2 (FlowCopy 20 (list 10)) (list 10) (list 20) (list 1)))
                 (list (FlowAllocation 1 1 #t)) (Nil)) (Nil))
        ;; A live container also keeps its old child alive across the backedge.
        (expect (placed (list (FlowNode 1 (FlowConstruct 10 1 (Nil)) (Nil) (list 10) (list 2))
                              (FlowNode 2 (FlowConstruct 20 2 (Nil)) (Nil) (list 20) (list 3))
                              (FlowNode 3 (FlowWrite 10 20) (list 10 20) (Nil) (list 2)))
                        (list (FlowAllocation 1 1 #t) (FlowAllocation 2 2 #t)) (Nil)) (list 1))))))
  )
