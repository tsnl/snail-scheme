;; Adapt folded backend instructions to the allocation graph. The graph owns
;; placement; this adapter owns Wasm evaluation order, locals, and labels.
(define-library (snail shell compiler allocation-wat)
  (export place-allocations)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler wat)
   (snail shell compiler allocation))
  (begin

    ;; ---- Folded instructions ----

    (: text (impl (Fn Wat -> String)))
    (define (text tree)
      (match tree ((Word value) value) (_ "")))

    (: op (impl (Fn Wat -> String)))
    (define (op tree)
      (match tree ((Node (Cons first _)) (text first)) (_ "")))

    (: args (impl (Fn Wat -> (List Wat))))
    (define (args tree)
      (match tree ((Node (Cons _ rest)) rest) (_ (Nil))))

    (: item (impl (Fn (List Wat) I64 -> Wat)))
    (define (item trees index)
      (match (list-drop trees index)
        ((Cons tree _) tree)
        (_ (panic "internal error: allocation-flow operand missing"))))

    (: decimal (impl (Fn String -> I64)))
    (define (decimal value)
      (fold-left (lambda (n c) (+ (* n 10) (- (char->integer c) 48))) 0 (string->list value)))

    (: named? (impl (Fn Wat -> Bool)))
    (define (named? tree)
      (let ((value (text tree)))
        (and (> (string-length value) 0) (char=? (string-ref value 0) #\$))))

    (: declaration? (impl (Fn Wat -> Bool)))
    (define (declaration? tree)
      (or (named? tree) (member? (op tree) (list "type" "param" "result" "local" "export"))))

    (: code (impl (Fn Wat -> (List Wat))))
    (define (code tree) (filter (lambda (child) (not (declaration? child))) (args tree)))

    (: reference? (impl (Fn Wat -> Bool)))
    (define (reference? type)
      (if (string=? (op type) "mut") (reference? (item (args type) 0))
          (or (string=? (op type) "ref")
              (member? (text type) (list "eqref" "anyref" "funcref" "externref")))))

    (: field-references (impl (Fn (Table Wat) String -> (List Bool))))
    (define (field-references types name)
      (match (table-ref types name)
        ((Some declaration)
         (let* ((body (item (args declaration) 1))
                (body (if (string=? (op body) "sub") (item (reverse (args body)) 0) body)))
           (map (lambda (field)
                  (reference? (if (string=? (op field) "field")
                                  (item (reverse (args field)) 0) field))) (args body))))
        (_ (panic "internal error: allocation-flow type missing"))))

    ;; ---- Graph construction ----

    ;; Build backwards from known continuations. Operand values are reserved
    ;; first, then their evaluations are prepended right to left, preserving
    ;; Wasm's left-to-right evaluation. Each node is one basic-block instruction.
    (struct GraphBuild
      ((next I64)
       (nodes (List FlowNode))
       (allocations (List FlowAllocation))
       (complete? Bool)))

    (struct Built
      ((build GraphBuild)
       (entry I64)
       (tree Wat)))

    (struct BuiltSequence
      ((build GraphBuild)
       (entry I64)
       (trees (List Wat))))

    (struct FlowLabel
      ((name String)
       (target I64)
       (result I64)))

    (struct FlowContext
      ((types (Table Wat))
       (locals (Table I64))
       (labels (List FlowLabel))
       (returned I64)
       (exit I64)))

    (: reserve (impl (Fn GraphBuild I64 -> GraphBuild)))
    (define (reserve build count) (GraphBuild-next-set build (+ (::next build) count)))

    (: add-node
       (impl (Fn GraphBuild I64 FlowOperation (List I64) (List I64) (List I64) -> GraphBuild)))
    (define (add-node build point operation uses defines successors)
      (GraphBuild-nodes-set build
                            (Cons (FlowNode point operation uses defines successors)
                                  (::nodes build))))

    (: numbered (impl (Fn I64 I64 -> (List I64))))
    (define (numbered first count) (map (lambda (index) (+ first index)) (iota count)))

    (: local-id (impl (Fn FlowContext Wat -> I64)))
    (define (local-id context name)
      (match (table-ref (::locals context) (text name))
        ((Some id) id)
        (_ (panic "internal error: allocation-flow local missing"))))

    (: label-for (impl (Fn FlowContext Wat -> FlowLabel)))
    (define (label-for context name)
      (let ((labels (if (named? name)
                        (filter (lambda (label) (string=? (::name label) (text name)))
                                (::labels context))
                        (list-drop (::labels context) (decimal (text name))))))
        (match labels
          ((Cons label _) label)
          (_ (panic "internal error: allocation-flow label missing")))))

    (: inside-label (impl (Fn FlowContext Wat I64 I64 -> FlowContext)))
    (define (inside-label context tree target result)
      (FlowContext-labels-set context
                              (Cons (FlowLabel (match (args tree)
                                                 ((Cons name _) (if (named? name) (text name) ""))
                                                 (_ ""))
                                               target result) (::labels context))))

    (: build-arguments
       (impl (Fn FlowContext (List Wat) (List I64) I64 GraphBuild -> BuiltSequence)))
    (define (build-arguments context trees values next build)
      (fold-left (lambda (built pair)
                   (let ((child (build-expression context (::first pair) (::second pair)
                                                  (::entry built) (::build built))))
                     (BuiltSequence (::build child)
                                    (::entry child)
                                    (Cons (::tree child) (::trees built)))))
                 (BuiltSequence build next (Nil)) (reverse (zip trees values))))

    (: build-body (impl (Fn FlowContext (List Wat) I64 I64 GraphBuild -> BuiltSequence)))
    (define (build-body context trees result next build)
      (let* ((count (length trees)) (values (append (numbered (::next build) (max 0 (- count 1)))
                                                    (if (= count 0) (Nil) (list result)))))
        (build-arguments context trees values next (reserve build (max 0 (- count 1))))))

    ;; ---- Ordinary instructions ----

    (: pointer-fields (impl (Fn (List Bool) (List I64) -> (List I64))))
    (define (pointer-fields flags values)
      (map ::second (filter (lambda (pair) (::first pair)) (zip flags values))))

    (: element-reference? (impl (Fn FlowContext Wat -> Bool)))
    (define (element-reference? context type)
      (match (field-references (::types context) (text type)) ((Cons flag _) flag) (_ #f)))

    (: value-at (impl (Fn (List I64) I64 -> I64)))
    (define (value-at values index)
      (match (list-drop values index)
        ((Cons value _) value)
        (_ (panic "internal error: allocation-flow value missing"))))

    ;; Scalars produce no reference origins. Reference reads use the declared
    ;; field type, so reading a number cannot spuriously alias the container.
    ;; Calls have no borrowing contract yet: their arguments may be retained.
    (: operation (impl (Fn FlowContext Wat I64 I64 (List I64) -> FlowOperation)))
    (define (operation context tree result point values)
      (let ((name (op tree)) (parts (args tree)))
        (cond
         ((string=? name "local.get") (FlowCopy result (list (local-id context (item parts 0)))))
         ((member? name (list "local.set" "local.tee"))
          (FlowCopy (local-id context (item parts 0)) values))
         ((string=? name "struct.new")
          (FlowConstruct result
                         point
                         (pointer-fields (field-references (::types context) (text (item parts 0)))
                                         values)))
         ((member? name (list "array.new" "array.new_fixed" "array.new_default" "array.new_data"))
          (FlowConstruct result
                         point
                         (if (element-reference? context (item parts 0)) values (Nil))))
         ((string=? name "struct.get")
          (if (list-ref (field-references (::types context) (text (item parts 0)))
                        (decimal (text (item parts 1))))
              (FlowRead result (value-at values 0)) (FlowPlain)))
         ((member? name (list "array.get" "array.get_u" "array.get_s"))
          (if (element-reference? context (item parts 0))
              (FlowRead result (value-at values 0))
              (FlowPlain)))
         ((string=? name "struct.set") (FlowWrite (value-at values 0) (value-at values 1)))
         ((string=? name "array.set") (FlowWrite (value-at values 0) (value-at values 2)))
         ((member? name (list "ref.cast" "ref.as_non_null")) (FlowCopy result values))
         ((string=? name "select") (FlowCopy result (take values 2)))
         ((member? name (list "global.get" "ref.func")) (FlowOpaque result (Nil)))
         ((string=? name "global.set") (FlowEscape values))
         ((or (member? name
                       (list "ref.eq" "ref.test" "ref.is_null" "ref.null" "array.len" "nop" "drop"))
              (and (>= (string-length name) 4)
                   (member? (substring name 0 4) (list "i32." "i64." "f32." "f64.")))) (FlowPlain))
         (else (FlowOpaque result values)))))

    (: operand? (impl (Fn Wat -> Bool)))
    (define (operand? tree)
      (and (not (string=? (op tree) ""))
           (not (member? (op tree) (list "ref" "result" "type" "param")))))

    (: with-operands (impl (Fn Wat (List Wat) -> Wat)))
    (define (with-operands tree operands)
      (let loop ((old (args tree)) (new operands) (taken (Nil)))
        (match old
          ((Nil) (wat* (op tree) (reverse taken)))
          ((Cons part rest)
           (if (operand? part)
               (loop rest (list-drop new 1) (Cons (item new 0) taken))
               (loop rest new (Cons part taken)))))))

    (: allocation? (impl (Fn String -> Bool)))
    (define (allocation? name)
      (member? name
               (list "struct.new"
                     "array.new"
                     "array.new_fixed"
                     "array.new_default"
                     "array.new_data")))

    (: constructed (impl (Fn GraphBuild Wat I64 -> GraphBuild)))
    (define (constructed build tree point)
      (if (allocation? (op tree))
          (GraphBuild-allocations-set build
                                      (Cons (FlowAllocation point
                                                            point
                                                            (string=? (op tree) "struct.new"))
                                            (::allocations build)))
          build))

    (: ordinary (impl (Fn FlowContext Wat I64 I64 GraphBuild -> Built)))
    (define (ordinary context tree result next build)
      (let* ((operands (filter operand? (args tree)))
             (values (numbered (::next build) (length operands)))
             (point (+ (::next build) (length operands)))
             (build (reserve build (+ (length operands) 1)))
             (tee? (string=? (op tree) "local.tee"))
             (build (if tee?
                        (add-node (reserve build 1)
                                  (::next build)
                                  (FlowCopy result values)
                                  values
                                  (list result)
                                  (list next))
                        build))
             (after (if tee? (- (::next build) 1) next))
             (defines (if (member? (op tree) (list "local.set" "local.tee"))
                          (list (local-id context (item (args tree) 0))) (list result)))
             (uses (if (string=? (op tree) "local.get")
                       (list (local-id context (item (args tree) 0)))
                       values))
             (build (add-node (constructed build tree point)
                              point
                              (operation context tree result point values)
                              uses
                              defines
                              (if (member? (op tree)
                                           (list "return_call"
                                                 "return_call_ref"
                                                 "return_call_indirect"
                                                 "unreachable"))
                                  (Nil)
                                  (list after))))
             (built (build-arguments context operands values point build))
             (tree (with-operands tree (::trees built))))
        (Built (::build built) (::entry built)
               (if (string=? (op tree) "struct.new")
                   (wat* "flow.struct.new"
                         (Cons (item (args tree) 0) (Cons (int point) (list-drop (args tree) 1))))
                   tree))))

    ;; ---- Structured control flow ----

    ;; Current emission uses zero block parameters and at most one result.
    ;; Future multi-value control needs explicit merge values before placement.
    (: supported-control? (impl (Fn Wat -> Bool)))
    (define (supported-control? tree)
      (not (any? (lambda (part)
                   (or (member? (op part) (list "param" "type"))
                       (and (string=? (op part) "result") (> (length (args part)) 1))))
                 (args tree))))

    (: block-flow (impl (Fn FlowContext Wat I64 I64 GraphBuild -> Built)))
    (define (block-flow context tree result next build)
      (let* ((loop? (string=? (op tree) "loop")) (header (::next build))
             (build (if loop? (reserve build 1) build))
             (inner (inside-label context tree (if loop? header next) (if loop? -1 result)))
             (body (build-body inner (code tree) result next build))
             (build (if loop?
                        (add-node (::build body)
                                  header
                                  (FlowPlain)
                                  (Nil)
                                  (Nil)
                                  (list (::entry body)))
                        (::build body))))
        (Built build (if loop? header (::entry body))
               (wat* (op tree) (append (filter declaration? (args tree)) (::trees body))))))

    (: conditional (impl (Fn FlowContext Wat I64 I64 GraphBuild -> Built)))
    (define (conditional context tree result next build)
      (let* ((parts (code tree)) (condition (item parts 0))
             (inner (inside-label context tree next result))
             (yes (build-body inner (args (item parts 1)) result next build))
             (no (build-body inner
                             (if (> (length parts) 2) (args (item parts 2)) (Nil))
                             result
                             next
                             (::build yes)))
             (value (::next (::build no))) (point (+ value 1))
             (build (add-node (reserve (::build no) 2)
                              point
                              (FlowPlain)
                              (list value)
                              (Nil)
                              (list (::entry yes) (::entry no))))
             (condition (build-expression context condition value point build)))
        (Built (::build condition) (::entry condition)
               (wat* "if" (concatenate (list (filter declaration? (args tree))
                                             (list (::tree condition) (wat* "then" (::trees yes)))
                                             (if (> (length parts) 2)
                                                 (list (wat* "else" (::trees no)))
                                                 (Nil))))))))

    (: branch-edge (impl (Fn GraphBuild FlowLabel (List I64) -> (Pair GraphBuild I64))))
    (define (branch-edge build label values)
      (if (null? values) (Pair build (::target label))
          (let* ((point (::next build))
                 (build (if (< (::result label) 0) (GraphBuild-complete?-set build #f) build)))
            (Pair (add-node (reserve build 1) point (FlowCopy (::result label) values) values
                            (list (::result label)) (list (::target label))) point))))

    (: branch (impl (Fn FlowContext Wat I64 I64 GraphBuild -> Built)))
    (define (branch context tree result next build)
      (let* ((parts (args tree)) (operands (filter operand? parts))
             (values (numbered (::next build) (length operands)))
             (build (reserve build (length operands)))
             (conditional? (string=? (op tree) "br_if"))
             (payload (if conditional? (take values (- (length values) 1)) values))
             (edge (branch-edge build (label-for context (item parts 0)) payload))
             (point (::next (::first edge)))
             (build (if conditional?
                        (add-node (reserve (::first edge) 2)
                                  (+ point 1)
                                  (FlowCopy result payload)
                                  payload
                                  (list result)
                                  (list next))
                        (reserve (::first edge) 1)))
             (build (add-node build
                              point
                              (FlowPlain)
                              (if conditional? (list (value-at (reverse values) 0)) (Nil))
                              (Nil)
                              (if conditional?
                                  (list (::second edge) (+ point 1))
                                  (list (::second edge)))))
             (built (build-arguments context operands values point build)))
        (Built (::build built) (::entry built) (with-operands tree (::trees built)))))

    (: table-edges
       (impl (Fn FlowContext (List Wat) (List I64) GraphBuild -> (Pair GraphBuild (List I64)))))
    (define (table-edges context labels payload build)
      (fold-left (lambda (state label)
                   (let ((edge (branch-edge (::first state) (label-for context label) payload)))
                     (Pair (::first edge) (Cons (::second edge) (::second state)))))
                 (Pair build (Nil)) labels))

    (: branch-table (impl (Fn FlowContext Wat I64 GraphBuild -> Built)))
    (define (branch-table context tree next build)
      (let* ((operands (filter operand? (args tree)))
             (values (numbered (::next build) (length operands)))
             (labels (filter (lambda (part) (not (operand? part))) (args tree)))
             (edges (table-edges context
                                 labels
                                 (take values (- (length values) 1))
                                 (reserve build (length operands))))
             (point (::next (::first edges)))
             (build (add-node (reserve (::first edges) 1)
                              point
                              (FlowPlain)
                              (list (value-at (reverse values) 0))
                              (Nil)
                              (::second edges)))
             (built (build-arguments context operands values point build)))
        (Built (::build built) (::entry built) (with-operands tree (::trees built)))))

    (: build-expression (impl (Fn FlowContext Wat I64 I64 GraphBuild -> Built)))
    (define (build-expression context tree result next build)
      (cond
       ((and (member? (op tree) (list "block" "loop" "if")) (not (supported-control? tree)))
        (Built (GraphBuild-complete?-set build #f) next tree))
       ((member? (op tree) (list "block" "loop")) (block-flow context tree result next build))
       ((string=? (op tree) "if") (conditional context tree result next build))
       ((member? (op tree) (list "br" "br_if")) (branch context tree result next build))
       ((string=? (op tree) "br_table") (branch-table context tree next build))
       ((string=? (op tree) "return")
        (let ((body (build-body context (args tree) (::returned context) (::exit context) build)))
          (Built (::build body) (::entry body) (wat* "return" (::trees body)))))
       ((or (string=? (op tree) "")
            (member? (op tree)
                     (list "try"
                           "try_table"
                           "throw"
                           "throw_ref"
                           "rethrow"
                           "br_on_cast"
                           "br_on_cast_fail"
                           "br_on_null"
                           "br_on_non_null")))
        (ordinary context tree result next (GraphBuild-complete?-set build #f)))
       (else (ordinary context tree result next build))))

    ;; ---- Placement annotations ----

    (: local-names (impl (Fn (List Wat) -> (Table I64))))
    (define (local-names declarations)
      (fold-left (lambda (names pair)
                   (let ((names (table-set names (i64->string (::second pair)) (::second pair))))
                     (if (named? (item (args (::first pair)) 0))
                         (table-set names (text (item (args (::first pair)) 0)) (::second pair))
                         names)))
                 empty-table (zip declarations (iota (length declarations)))))

    (: has-construction? (impl (Fn Wat -> Bool)))
    (define (has-construction? tree)
      (or (string=? (op tree) "struct.new") (any? has-construction? (args tree))))

    (: annotate-placement (impl (Fn (List I64) Wat -> Wat)))
    (define (annotate-placement frames tree)
      (if (string=? (op tree) "flow.struct.new")
          (let* ((parts (args tree)) (frame? (member? (decimal (text (item parts 1))) frames)))
            (wat* (if frame? "frame.struct.new" "struct.new")
                  (append (if frame? (take parts 2) (list (item parts 0)))
                          (map (lambda (child) (annotate-placement frames child))
                               (list-drop parts 2)))))
          (match tree
            ((Node items) (Node (map (lambda (child) (annotate-placement frames child)) items)))
            (_ tree))))

    (: analyze-function (impl (Fn (Table Wat) Wat -> (Option Wat))))
    (define (analyze-function types function)
      (let* ((parameters (filter (lambda (part) (string=? (op part) "param")) (args function)))
             (locals (append parameters
                             (filter (lambda (part) (string=? (op part) "local")) (args function))))
             (returned (+ (length locals) 1)) (exit (+ returned 1))
             (context (FlowContext types
                                   (local-names locals)
                                   (list (FlowLabel "" exit returned))
                                   returned
                                   exit))
             (build (GraphBuild (+ exit 1)
                                (list (FlowNode exit
                                                (FlowEscape (list returned))
                                                (list returned)
                                                (Nil)
                                                (Nil)))
                                (Nil)
                                #t))
             (body (build-body context (code function) returned exit build))
             (graph (FlowGraph (::entry body)
                               (::nodes (::build body))
                               (::allocations (::build body))
                               (iota (length parameters)))))
        (let ((frames (if (::complete? (::build body)) (frame-allocations graph) (Nil))))
          (if (null? frames) (None)
              (Some (annotate-placement frames
                                        (wat* "func" (append (filter declaration? (args function))
                                                             (::trees body)))))))))

    ;; None preserves the input without copying it or reserving object slots.
    ;; Some carries at least one construction requiring physical frame layout.
    (: place-allocations (impl (Fn (Table Wat) Wat -> (Option Wat))))
    (define (place-allocations types function)
      (if (has-construction? function) (analyze-function types function) (None)))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-allocation-wat)
    (import
     (snail stage0 testing))
    (begin
      (define (frame-count tree)
        (+ (if (string=? (op tree) "frame.struct.new") 1 0)
           (fold-left (lambda (count child) (+ count (frame-count child))) 0 (args tree))))

      (define (expect-frames body expected)
        (let ((types
               (table-set (table-set empty-table "$S" (parse-wat "(type $S (struct (field i64)))"))
                          "$P" (parse-wat "(type $P (struct (field (mut (ref null $S)))))"))))
          (expect (match (place-allocations types (parse-wat body))
                    ((Some tree) (frame-count tree)) ((None) 0)) expected)))

      (define (test-allocation-wat)
        (expect-frames "(func $f (result i64) (struct.get $S 0 (struct.new $S (i64.const 42))))" 1)
        (expect-frames "(func $f (result (ref $S)) (struct.new $S (i64.const 42)))" 0)
        (expect-frames "(func $f (result i64) (local $a (ref null $S)) (local $b (ref null $S))
          (local.set $a (struct.new $S (i64.const 42))) (local.set $b (local.get $a))
          (struct.get $S 0 (ref.as_non_null (local.get $b))))" 1)
        (expect-frames "(func $f (param $c i32) (result i64)
          (struct.get $S 0 (if (result (ref $S)) (local.get $c)
            (then (struct.new $S (i64.const 10))) (else (struct.new $S (i64.const 20))))))" 2)
        (expect-frames "(func $f (result i64) (struct.get $S 0
          (block $out (result (ref $S)) (br $out (struct.new $S (i64.const 42))))))" 1)
        (expect-frames "(func $f (result i64) (struct.get $S 0
          (block (result (ref $S)) (br 0 (struct.new $S (i64.const 42))))))" 1)
        (expect-frames "(func $f (result (ref $P))
          (struct.new $P (struct.new $S (i64.const 42))))" 0)
        (expect-frames "(func $f (result (ref null $S))
          (struct.get $P 0 (struct.new $P (struct.new $S (i64.const 42)))))" 1)
        (expect-frames "(func $f (param $p (ref $P))
          (struct.set $P 0 (local.get $p) (struct.new $S (i64.const 42))))" 0)
        (expect-frames "(func $f (return_call $g (struct.new $S (i64.const 42))))" 0)
        (expect-frames "(func $f (call $g (struct.new $S (i64.const 42))))" 0)
        (test-allocation-loops))

      (define (test-allocation-loops)
        (expect-frames "(func $f (param $again i32) (local $p (ref null $S))
          (loop $loop (local.set $p (struct.new $S (i64.const 42)))
            (drop (struct.get $S 0 (local.get $p))) (br_if $loop (local.get $again))))" 1)
        (expect-frames
         "(func $f (param $again i32) (local $p (ref null $S)) (local $old (ref null $S))
          (loop $loop (local.set $p (struct.new $S (i64.const 42)))
            (drop (ref.eq (local.get $p) (local.get $old)))
            (local.set $old (local.get $p)) (br_if $loop (local.get $again))))" 0)
        (expect-frames "(func $f (param $again i32) (local $p (ref null $P))
          (local.set $p (struct.new $P (ref.null $S)))
          (loop $loop (struct.set $P 0 (local.get $p) (struct.new $S (i64.const 42)))
            (br_if $loop (local.get $again))))" 1)))))
  )
