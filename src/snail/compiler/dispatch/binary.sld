;; What a `dynamic-instances` form generates, as the old compiler's
;; `generate-binary-instances` and the functions it calls (src/snail/shell/
;; compiler/dynamic.sld) decide it, each refusal the old message. Every
;; check refuses the library, in this order, as the old compiler makes them
;; while it declares the form.
;;
;; - The class, as known where the form is, is binary: one row parameter,
;;   two type parameters, one output and a method at least. Each method, in
;;   the class's order, is a function with no requirement of its own, and
;;   then of type (dyn (Fn A B -> Output ! e)) over the class's own
;;   parameters, with no variable of its own.
;; - The domain is a pair at least, no two the same.
;; - Each pair, in order: two concrete types; then exactly one source, an
;;   instance of the class active at the form, whose selecting types the
;;   pair matches; the source has no requirements, and at the match its
;;   output and row are ground, the row closed. That is the pair's case.
;; - Each head, in order: no type parameter of the class given a row.
;;
;; The heads are, for each pair (L R) in order, (Any R), (L Any) and
;; (Any Any), each once, in the order first met. A head's cases are those
;; it accepts, each side Any or the case's; its output the one output its
;; cases share, or Any; its row dyn-cast and every effect of its cases'
;; rows.
(define-library (snail compiler dispatch binary)
  (export
   BinaryClass
   Case
   Head
   ErasedLeft
   ErasedRight
   ErasedBoth
   Family
   binary-class
   domain-problem
   domain-pair-case
   family-heads
   head-family
   family-types
   family-problem)
  (import
   (snail core base)
   (only (snail compiler expand language) Global Dyn FnContract)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare equality) same-type? same-types? effect-set)
   (only (snail compiler declare schemes) substituted)
   (only (snail compiler declare membership) same-member?)
   (only (snail compiler declare misplaced-rows) misplaced-row-problem)
   (only (snail compiler dispatch language) Instance)
   (only (snail compiler dispatch listing) instance-selecting-types)
   (only (snail compiler dispatch matching) matched-types)
   (snail compiler dispatch runtime)
   (snail compiler dispatch known)
   (only (snail compiler dispatch domains) ground? concrete?))
  (begin

    ;; ---- Classes ----

    ;; A binary class: its parameters as written, the row `row` among them
    ;; at `row-index`; its two type parameters, `left` and `right`, in
    ;; order; its output; and its methods, in order.
    (struct BinaryClass
      ((parameters (List declared-ClassParameter))
       (row String)
       (row-index I64)
       (left String)
       (right String)
       (output String)
       (members (List declared-Member))))

    (: binary-class (impl (Fn KnownClass -> (Result BinaryClass String))))
    (define (binary-class class)
      (match (Pair (Pair (class-rows class) (class-types class)) (::outputs class))
        ((Pair (Pair (Cons row (Nil)) (Cons left (Cons right (Nil)))) (Cons output (Nil)))
         (if (null? (::members class))
             (Err binary-class-problem)
             (let ((binary (BinaryClass (::parameters class)
                                        (::second row)
                                        (::first row)
                                        left
                                        right
                                        (::name (::label output))
                                        (map ::first (::members class)))))
               (match (methods-problem binary class)
                 ((Some problem) (Err problem))
                 ((None) (Ok binary))))))
        (_ (Err binary-class-problem))))

    (: binary-class-problem String)
    (define binary-class-problem
      "dynamic-instances needs a binary class with one effect row and one associated output")

    ;; Each row parameter, with its index among the class's parameters.
    (: class-rows (impl (Fn KnownClass -> (List (Pair I64 String)))))
    (define (class-rows class)
      (concatenate (map (lambda (entry)
                          (match (::second entry)
                            ((declared-RowParameter name) (list (Pair (::first entry) name)))
                            ((declared-TypeParameter _) (Nil))))
                        (zip (iota (length (::parameters class))) (::parameters class)))))

    (: class-types (impl (Fn KnownClass -> (List String))))
    (define (class-types class)
      (concatenate (map (lambda (parameter)
                          (match parameter
                            ((declared-TypeParameter name) (list name))
                            ((declared-RowParameter _) (Nil))))
                        (::parameters class))))

    ;; The problem of the first method, in the class's order, that is no
    ;; binary method.
    (: methods-problem (impl (Fn BinaryClass KnownClass -> (Option String))))
    (define (methods-problem binary class)
      (let loop ((members (::members class)))
        (match members
          ((Nil) (None))
          ((Cons member rest)
           (match (method-problem binary (::second member))
             ((Some problem) (Some problem))
             ((None) (loop rest)))))))

    ;; `own` is the method's own scheme, over the class's parameters.
    (: method-problem (impl (Fn BinaryClass declared-Scheme -> (Option String))))
    (define (method-problem binary own)
      (match (Pair (::requirements own) (::type own))
        ((Pair (Nil) (declared-Callable (Dyn) (FnContract) arrow))
         (if (and (null? (::variables own)) (binary-arrow? binary arrow))
             (None)
             (Some "dynamic-instances needs methods of type (dyn (Fn A B -> Output ! e))")))
        (_ (Some "dynamic-instances does not support independent method requirements"))))

    (: binary-arrow? (impl (Fn BinaryClass declared-Arrow -> Bool)))
    (define (binary-arrow? binary arrow)
      (and (same-types? (::parameters arrow)
                        (list (written (::left binary)) (written (::right binary))))
           (same-type? (::result arrow) (written (::output binary)))
           (same-type? (declared-Row (::effects arrow))
                       (declared-Row (declared-Effects (Nil) (Some (written (::row binary))))))))

    (: written (impl (Fn String -> declared-Type)))
    (define (written name)
      (declared-Var (declared-Written name)))

    ;; ---- Domains ----

    (: domain-problem (impl (Fn (List (List declared-Type)) -> (Option String))))
    (define (domain-problem pairs)
      (if (or (null? pairs) (not (= (length pairs) (length (delete-duplicates same-types? pairs)))))
          (Some "dynamic-instances needs a nonempty domain of distinct type pairs")
          (None)))

    ;; ---- Cases ----

    ;; A pair the domain names, with its source's output and row effects at
    ;; the pair, and the source's implementation of each of the class's
    ;; methods, in the class's order.
    (struct Case
      ((left declared-Type)
       (right declared-Type)
       (output declared-Type)
       (effects (List Global))
       (implementations (List Global))))

    ;; `sources` are the instances of the class active at the form,
    ;; written or generated before it, in the program's order.
    (: domain-pair-case
       (impl (Fn BinaryClass (List Instance) (List declared-Type) -> (Result Case String))))
    (define (domain-pair-case binary sources pair)
      (match pair
        ((Cons left (Cons right (Nil)))
         (if (and (concrete? left) (concrete? right))
             (match (matching-sources sources pair)
               ((Cons (Pair source bindings) (Nil)) (source-case binary source bindings left right))
               ((Nil) (Err "dynamic-instances has no active source instance for a domain pair"))
               (_ (Err "dynamic-instances has overlapping source instances")))
             (Err entries-problem)))
        (_ (Err entries-problem))))

    (: entries-problem String)
    (define entries-problem
      "dynamic-instances domain entries are two concrete, non-Any types")

    (: matching-sources
       (impl (Fn (List Instance) (List declared-Type)
                 -> (List (Pair Instance (List (Pair declared-TypeVariable declared-Type)))))))
    (define (matching-sources sources pair)
      (concatenate (map (lambda (source)
                          (match (matched-types (::variables source)
                                                (instance-selecting-types source)
                                                pair)
                            ((Some bindings) (list (Pair source bindings)))
                            ((None) (Nil))))
                        sources)))

    ;; Declared gives an instance a type for each of its class's written
    ;; parameters and an output for each of its outputs, which the scan
    ;; knows of a class before its declaration, so the source has its row
    ;; at the class's row index and one output.
    (: source-case
       (impl (Fn BinaryClass
                 Instance
                 (List (Pair declared-TypeVariable declared-Type))
                 declared-Type
                 declared-Type
                 ->
                 (Result Case String))))
    (define (source-case binary source bindings left right)
      (if (null? (::requirements source))
          (let ((output (substituted bindings (only-output source)))
                (row (substituted bindings (list-ref (::types source) (::row-index binary)))))
            (if (and (ground? output) (ground? row))
                (match row
                  ((declared-Row effects)
                   (Ok (Case left
                             right
                             output
                             (::labels effects)
                             (map (lambda (member) (implementation source member))
                                  (::members binary)))))
                  (_ (Err "dynamic-instances source effect rows must be closed")))
                (Err "dynamic-instances source outputs and rows must be determined")))
          (Err "dynamic-instances source instances must have no class prerequisites")))

    (: only-output (impl (Fn Instance -> declared-Type)))
    (define (only-output source)
      (match (::outputs source)
        ((Cons output (Nil)) output)
        (_ (panic "dispatch: a binary class's instance has its one output"))))

    ;; A source passing every check was written after its class, since one
    ;; written before could not give the class's row parameter a closed
    ;; row: its selecting types would hold the type there. `declare` makes
    ;; an instance written after its class implement each of its methods.
    (: implementation (impl (Fn Instance declared-Member -> Global)))
    (define (implementation source member)
      (match (find (lambda (method) (same-member? (::member method) member)) (::methods source))
        ((Some method) (::implementation method))
        ((None) (panic "dispatch: a source instance implements each method of its class"))))

    ;; ---- Heads ----

    ;; A generated head erases one argument or both: (Any R), (L Any) or
    ;; (Any Any).
    (enum Head
      (ErasedLeft
       ((right declared-Type)))
      (ErasedRight
       ((left declared-Type)))
      (ErasedBoth))

    (: family-heads (impl (Fn (List Case) -> (List Head))))
    (define (family-heads cases)
      (delete-duplicates same-head?
                         (concatenate (map (lambda (case)
                                             (list (ErasedLeft (::right case))
                                                   (ErasedRight (::left case))
                                                   (ErasedBoth)))
                                           cases))))

    (: same-head? (impl (Fn Head Head -> Bool)))
    (define (same-head? head other)
      (match (Pair head other)
        ((Pair (ErasedLeft right) (ErasedLeft other-right)) (same-type? right other-right))
        ((Pair (ErasedRight left) (ErasedRight other-left)) (same-type? left other-left))
        ((Pair (ErasedBoth) (ErasedBoth)) #t)
        (_ #f)))

    ;; ---- Families ----

    ;; One generated instance: its head, the cases it accepts in the
    ;; domain's order, its output and its row's effects.
    (struct Family
      ((head Head)
       (cases (List Case))
       (output declared-Type)
       (effects (List Global))))

    (: head-family (impl (Fn (List Case) Head -> Family)))
    (define (head-family cases head)
      (let* ((accepted (filter (lambda (case) (accepts? head case)) cases))
             (outputs (delete-duplicates same-type? (map ::output accepted))))
        (Family head
                accepted
                (match outputs
                  ((Cons output (Nil)) output)
                  (_ any-type))
                (effect-set (Cons dyn-cast-effect (concatenate (map ::effects accepted)))))))

    (: accepts? (impl (Fn Head Case -> Bool)))
    (define (accepts? head case)
      (match head
        ((ErasedLeft right) (same-type? right (::right case)))
        ((ErasedRight left) (same-type? left (::left case)))
        ((ErasedBoth) #t)))

    ;; The head the family's instance gives each of the class's written
    ;; parameters: its row, and each type parameter its side.
    (: family-types (impl (Fn BinaryClass Family -> (List declared-Type))))
    (define (family-types binary family)
      (map (lambda (parameter)
             (match parameter
               ((declared-RowParameter _)
                (declared-Row (declared-Effects (::effects family) (None))))
               ((declared-TypeParameter name)
                (if (string=? name (::left binary))
                    (left-type (::head family))
                    (right-type (::head family))))))
           (::parameters binary)))

    (: left-type (impl (Fn Head -> declared-Type)))
    (define (left-type head)
      (match head
        ((ErasedRight left) left)
        (_ any-type)))

    (: right-type (impl (Fn Head -> declared-Type)))
    (define (right-type head)
      (match head
        ((ErasedLeft right) right)
        (_ any-type)))

    ;; The refusal of a family's instance, of the class named `class`,
    ;; that gives a type parameter a row: a domain type that is a closed
    ;; row, or a source's output that is one.
    (: family-problem (impl (Fn String BinaryClass Family -> (Option String))))
    (define (family-problem class binary family)
      (let loop ((pairs (zip (append (::parameters binary)
                                     (list (declared-TypeParameter (::output binary))))
                             (append (family-types binary family) (list (::output family))))))
        (match pairs
          ((Nil) (None))
          ((Cons pair rest)
           (match (misplaced-row-problem class (::first pair) (::second pair))
             ((Some problem) (Some problem))
             ((None) (loop rest)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-binary)
    (import
     (snail compiler source)
     (only (snail compiler expand language) Label ClassGlobal Integer)
     (only (snail compiler declare forms) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-binary)
        (test-classes)
        (test-methods)
        (test-domains)
        (test-cases)
        (test-heads)
        (test-families))

      (define loc (Loc "t.sld" 4 1))
      (define main (list "main"))

      (define (builtin name)
        (declared-Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define (var name) (declared-Var (declared-Written name)))
      (define log (Global main "log" 0))
      (define op (Global main "op" 0))

      (define (arrow parameters result effects)
        (declared-Callable (Dyn) (FnContract) (declared-Arrow parameters result effects)))

      (define open-row (declared-Effects (list) (Some (var "e"))))

      (define (own type)
        (declared-Scheme (list) (list) (list) type))

      ;; (typeclass (Op e A B) (type Output) (: op (impl (Fn A B -> Output ! e)))).
      (define (op-class members)
        (KnownClass (list (declared-RowParameter "e")
                          (declared-TypeParameter "A")
                          (declared-TypeParameter "B"))
                    (list (declared-Output (Label "Output" loc) (list)))
                    members))

      (define op-method
        (Pair (declared-ClassMethod op)
              (own (arrow (list (var "A") (var "B")) (var "Output") open-row))))

      (define op-binary
        (BinaryClass (list (declared-RowParameter "e")
                           (declared-TypeParameter "A")
                           (declared-TypeParameter "B"))
                     "e"
                     0
                     "A"
                     "B"
                     "Output"
                     (list (declared-ClassMethod op))))

      (define (test-classes)
        (let ((problem
               "dynamic-instances needs a binary class with one effect row and one associated output"))
          (expect (binary-class (op-class (list op-method))) (Ok op-binary))
          (expect (binary-class (op-class (list))) (Err problem))
          ;; A class of the library not reached has no row
          ;; (build/dispatch-design/probes/class-later-dynamic.sld).
          (expect (binary-class (KnownClass (list (declared-TypeParameter "e")
                                                  (declared-TypeParameter "A")
                                                  (declared-TypeParameter "B"))
                                            (list (declared-Output (Label "Output" loc) (list)))
                                            (list)))
                  (Err problem))
          (expect (binary-class (KnownClass (list (declared-RowParameter "e")
                                                  (declared-TypeParameter "A")
                                                  (declared-TypeParameter "B"))
                                            (list)
                                            (list op-method)))
                  (Err problem))))

      ;; A method that is no function, or has a requirement of its own, is
      ;; refused before one of the wrong type.
      (define (test-methods)
        (let ((requirements "dynamic-instances does not support independent method requirements")
              (shape "dynamic-instances needs methods of type (dyn (Fn A B -> Output ! e))")
              (class (lambda (scheme)
                       (binary-class
                        (op-class (list op-method (Pair (declared-ClassMethod log) scheme)))))))
          (expect (class (own i64)) (Err requirements))
          (expect (class (declared-Scheme (list)
                                          (list (declared-ClassRequirement (ClassGlobal op) (list)))
                                          (list)
                                          (arrow (list (var "A") (var "B"))
                                                 (var "Output")
                                                 open-row)))
                  (Err requirements))
          (expect (class (declared-Scheme (list (declared-Written "c"))
                                          (list)
                                          (list)
                                          (arrow (list (var "A") (var "B"))
                                                 (var "Output")
                                                 open-row)))
                  (Err shape))
          (expect (class (own (arrow (list (var "B") (var "A")) (var "Output") open-row)))
                  (Err shape))
          (expect (class (own (arrow (list (var "A") (var "B")) (var "A") open-row))) (Err shape))
          (expect (class (own (arrow (list (var "A") (var "B"))
                                     (var "Output")
                                     (declared-Effects (list) (None)))))
                  (Err shape))
          (expect (class (own (arrow (list (var "A") (var "B"))
                                     (var "Output")
                                     (declared-Effects (list log) (Some (var "e"))))))
                  (Err shape))))

      (define (test-domains)
        (expect (domain-problem (list))
                (Some "dynamic-instances needs a nonempty domain of distinct type pairs"))
        (expect (domain-problem (list (list i64 i64) (list i64 i64)))
                (Some "dynamic-instances needs a nonempty domain of distinct type pairs"))
        (expect (domain-problem (list (list i64 i64) (list i64))) (None))
        (expect (domain-problem (list (list i64 i64) (list i64 f64))) (None)))

      ;; (instance (Op row A B) (type Output output) (define op ...)).
      (define (source serial variables row a b output requirements)
        (Instance (Global main "Op" serial)
                  (ClassGlobal (Global main "Op" 0))
                  variables
                  (list row a b)
                  (list output)
                  requirements
                  (list)
                  (list (declared-InstanceMethod (declared-ClassMethod op)
                                                 (Global main "op" serial)
                                                 (declared-Literal (Integer 0) loc)
                                                 loc))
                  loc))

      (define closed (declared-Row (declared-Effects (list) (None))))
      (define logged (declared-Row (declared-Effects (list log) (None))))

      ;; Read off error-binary-domain.sld and error-binary-source-inactive.sld,
      ;; and the old `binary-case`'s order.
      (define (test-cases)
        (let ((entries "dynamic-instances domain entries are two concrete, non-Any types")
              (ints (source 1 (list) closed i64 i64 i64 (list)))
              (any-left (source 2 (list (declared-Written "a")) logged (var "a") f64 f64 (list))))
          (expect (domain-pair-case op-binary (list ints) (list any-type i64)) (Err entries))
          (expect (domain-pair-case op-binary (list ints) (list i64)) (Err entries))
          (expect (domain-pair-case op-binary (list ints) (list i64 (var "a"))) (Err entries))
          (expect (domain-pair-case op-binary (list) (list i64 i64))
                  (Err "dynamic-instances has no active source instance for a domain pair"))
          (expect (domain-pair-case op-binary (list ints ints) (list i64 i64))
                  (Err "dynamic-instances has overlapping source instances"))
          (expect (domain-pair-case op-binary (list ints) (list i64 i64))
                  (Ok (Case i64 i64 i64 (list) (list (Global main "op" 1)))))
          ;; A source's variable binds to the pair's type, which its output
          ;; and row see.
          (expect (domain-pair-case op-binary (list ints any-left) (list i64 f64))
                  (Ok (Case i64 f64 f64 (list log) (list (Global main "op" 2)))))
          (expect (domain-pair-case op-binary
                                    (list (source 3 (list) closed i64 i64 i64
                                                  (list
                                                   (declared-ClassRequirement (ClassGlobal op)
                                                                              (list)))))
                                    (list i64 i64))
                  (Err "dynamic-instances source instances must have no class prerequisites"))
          (expect (domain-pair-case op-binary
                                    (list (source 4
                                                  (list (declared-Written "o"))
                                                  closed
                                                  i64
                                                  i64
                                                  (var "o")
                                                  (list)))
                                    (list i64 i64))
                  (Err "dynamic-instances source outputs and rows must be determined"))
          (expect (domain-pair-case op-binary
                                    (list
                                     (source 5 (list) (declared-Row open-row) i64 i64 i64 (list)))
                                    (list i64 i64))
                  (Err "dynamic-instances source outputs and rows must be determined"))
          ;; An instance that gives the row parameter a type, as one written
          ;; before its class may, selects by that type too, so it is no
          ;; pair's source, where the old compiler refuses it as not closed.
          (expect
           (domain-pair-case op-binary
                             (list (source 6 (list) i64 i64 i64 i64 (list)))
                             (list i64 i64))
           (Err "dynamic-instances has no active source instance for a domain pair"))))

      ;; For (I64 I64) (I64 F64) (F64 I64), as tests/programs/binary-dispatch.sld
      ;; has them: (Any I64) (I64 Any) (Any Any) (Any F64) (F64 Any).
      (define (case-of left right output)
        (Case left right output (list) (list op)))

      (define cases
        (list (case-of i64 i64 i64) (case-of i64 f64 f64) (case-of f64 i64 f64)))

      (define (test-heads)
        (expect (family-heads cases)
                (list (ErasedLeft i64)
                      (ErasedRight i64)
                      (ErasedBoth)
                      (ErasedLeft f64)
                      (ErasedRight f64))))

      ;; A head's cases, the output they share or Any, and the row with
      ;; dyn-cast and each case's effects; and the head at the class's
      ;; parameters.
      (define (test-families)
        (let ((left-erased (head-family cases (ErasedLeft i64)))
              (both
               (head-family (list (case-of i64 i64 i64) (Case i64 f64 i64 (list log) (list op)))
                            (ErasedBoth))))
          (expect left-erased
                  (Family (ErasedLeft i64)
                          (list (case-of i64 i64 i64) (case-of f64 i64 f64))
                          any-type
                          (list dyn-cast-effect)))
          (expect (::output (head-family cases (ErasedRight f64))) f64)
          (expect both
                  (Family (ErasedBoth)
                          (list (case-of i64 i64 i64) (Case i64 f64 i64 (list log) (list op)))
                          i64
                          (effect-set (list dyn-cast-effect log))))
          (expect (family-types op-binary left-erased)
                  (list (declared-Row (declared-Effects (list dyn-cast-effect) (None)))
                        any-type
                        i64))
          (expect (family-problem "Op" op-binary left-erased) (None))
          (expect (family-problem "Op"
                                  op-binary
                                  (head-family (list (case-of closed i64 i64))
                                               (ErasedRight closed)))
                  (Some "a Op instance gives its type parameter A a row, not a type"))
          (expect (family-problem "Op"
                                  op-binary
                                  (head-family (list (case-of i64 i64 closed)) (ErasedLeft i64)))
                  (Some "a Op instance gives its type parameter Output a row, not a type"))))))
   (else)))
