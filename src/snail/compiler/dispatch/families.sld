;; `dynamic-instances` forms: a form becomes the instances it generates,
;; one for each head, as the old compiler's `declare-dynamic-instances`
;; (src/snail/shell/compiler/expand.sld) and `generate-binary-instances`
;; (src/snail/shell/compiler/dynamic.sld) write them, every node at the
;; form. (snail compiler dispatch binary) checks the form and answers its
;; cases and heads, and any refusal stops the library, at the form, as the
;; old compiler stops when it declares the form; only then is anything
;; written.
;;
;; A head's instance has a Global of its own, named `dynamic`, then a method
;; for each method of the class, in order: an implementation Global named
;; for the member, and a ClosedLambda of `left` and `right` that tries each
;; of the head's cases in turn, as (snail compiler dispatch language) shows,
;; calling the case's source implementation directly. Each method's
;; numbers are its implementation's, its parameters', then each case's two
;; locals in turn.
(define-library (snail compiler dispatch families)
  (export
   family-instances)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare equality) same-type?)
   (only (snail compiler names globals) Local TopGlobal ClassRef ClassGlobal FieldClass)
   (only (snail compiler declare membership) member-name)
   (only (snail compiler dispatch language) Instance)
   (snail compiler dispatch runtime)
   (only (snail compiler builtins base) unsupported-instance-case dyn-cast-effect)
   (snail compiler dispatch known)
   (snail compiler dispatch binary)
   (snail compiler names numbering)
   (snail compiler dispatch conversions))
  (begin

    ;; ---- Forms ----

    ;; The instances the form `(dynamic-instances class pair ...)` at `loc`
    ;; generates, `class` as known there and `sources` the instances of the
    ;; class active there, written or generated before it, in the
    ;; program's order; or the form's problem.
    (: family-instances
       (impl (Fn Numbering KnownClass ClassRef (List (List declared-Type)) (List Instance) Loc
                 -> (Result (Pair (List Instance) Numbering) (List Feedback)))))
    (define (family-instances state class class-ref pairs sources loc)
      (result-let* ((checked (checked-families class class-ref pairs sources loc)))
        (Ok (map-with-state state
                            (lambda (state family)
                              (written-family state class-ref (::first checked) family loc))
                            (::second checked)))))

    ;; The class, the domain, each pair's case in order, then each head.
    (: checked-families
       (impl (Fn KnownClass ClassRef (List (List declared-Type)) (List Instance) Loc
                 -> (Result (Pair BinaryClass (List Family)) (List Feedback)))))
    (define (checked-families class class-ref pairs sources loc)
      (result-let* ((binary (at loc (binary-class class)))
                    (cases (match (domain-problem pairs)
                             ((Some problem) (fail loc problem))
                             ((None)
                              (map-results
                               (lambda (pair) (at loc (domain-pair-case binary sources pair)))
                               pairs)))))
        (let ((families (map (lambda (head) (head-family cases head)) (family-heads cases))))
          (match (families-problem (class-name class-ref) binary families)
            ((Some problem) (fail loc problem))
            ((None) (Ok (Pair binary families)))))))

    (: families-problem (impl (Fn String BinaryClass (List Family) -> (Option String))))
    (define (families-problem class binary families)
      (match families
        ((Nil) (None))
        ((Cons family rest)
         (match (family-problem class binary family)
           ((Some problem) (Some problem))
           ((None) (families-problem class binary rest))))))

    (: at (All (A) (impl (Fn Loc (Result A String) -> (Result A (List Feedback))))))
    (define (at loc answer)
      (match answer
        ((Ok value) (Ok value))
        ((Err message) (fail loc message))))

    ;; The name a message gives the class, as `declare` names it.
    (: class-name (impl (Fn ClassRef -> String)))
    (define (class-name class)
      (match class
        ((ClassGlobal global) (::name global))
        ((FieldClass label) label)))

    ;; ---- Instances ----

    (: written-family
       (impl (Fn Numbering ClassRef BinaryClass Family Loc -> (Pair Instance Numbering))))
    (define (written-family state class binary family loc)
      (state-let* ((global state (fresh-global state "dynamic"))
                   (methods state
                            (map-with-state state
                                            (lambda (state entry)
                                              (written-method state family entry loc))
                                            (zip (iota (length (::members binary)))
                                                 (::members binary)))))
        (Pair (Instance global
                        class
                        (Nil)
                        (family-types binary family)
                        (list (::output family))
                        (Nil)
                        (Nil)
                        methods
                        loc)
              state)))

    ;; ---- Methods ----

    ;; What each branch of one method's lambda shares: the family, the
    ;; member and its index among the class's methods, the lambda's two
    ;; parameters, and where it is.
    (struct Generating
      ((family Family)
       (member declared-Member)
       (index I64)
       (left Local)
       (right Local)
       (loc Loc)))

    ;; One case's branch: the case, and the locals its left and right
    ;; arguments are recovered as.
    (struct Branch
      ((case Case)
       (left Local)
       (right Local)))

    (: written-method
       (impl (Fn Numbering Family (Pair I64 declared-Member) Loc
                 -> (Pair declared-InstanceMethod Numbering))))
    (define (written-method state family entry loc)
      (state-let* ((implementation state (fresh-global state (member-name (::second entry))))
                   (left state (fresh-local state "left"))
                   (right state (fresh-local state "right"))
                   (branches state (map-with-state state case-branch (::cases family))))
        (let ((generating (Generating family (::second entry) (::first entry) left right loc)))
          (Pair (declared-InstanceMethod (::second entry)
                                         implementation
                                         (declared-ClosedLambda (list left right)
                                                                (tried generating branches)
                                                                loc)
                                         loc)
                state))))

    (: case-branch (impl (Fn Numbering Case -> (Pair Branch Numbering))))
    (define (case-branch state case)
      (state-let* ((left state (fresh-local state "left"))
                   (right state (fresh-local state "right")))
        (Pair (Branch case left right) state)))

    ;; Each case in turn, then the failure.
    (: tried (impl (Fn Generating (List Branch) -> declared-Expr)))
    (define (tried generating branches)
      (fold-right (lambda (branch rest) (attempt generating branch rest))
                  (family-failure generating)
                  branches))

    ;; The case's call, once each argument the head erases is recovered
    ;; as the case's type, or else `rest`.
    (: attempt (impl (Fn Generating Branch declared-Expr -> declared-Expr)))
    (define (attempt generating branch rest)
      (let ((case (::case branch))
            (call (case-call generating branch))
            (loc (::loc generating)))
        (match (::head (::family generating))
          ((ErasedLeft _)
           (recovered (left-ref generating) (::left case) (::left branch) call rest loc))
          ((ErasedRight _)
           (recovered (right-ref generating) (::right case) (::right branch) call rest loc))
          ((ErasedBoth)
           (recovered-both (left-ref generating)
                           (::left case)
                           (::left branch)
                           (right-ref generating)
                           (::right case)
                           (::right branch)
                           call
                           rest
                           loc)))))

    ;; The source's implementation called with each argument, recovered
    ;; where the head erases it; converted to Any when the instance's
    ;; output is Any and the case's is not. A case holds an implementation
    ;; for each of the class's methods, in order, as `domain-pair-case` makes it.
    (: case-call (impl (Fn Generating Branch -> declared-Expr)))
    (define (case-call generating branch)
      (let* ((loc (::loc generating))
             (family (::family generating))
             (case (::case branch))
             (head (::head family))
             (call (declared-Call (declared-TopRef (TopGlobal (list-ref (::implementations case)
                                                                        (::index generating)))
                                                   loc)
                                  (list (if (left-erased? head)
                                            (declared-LocalRef (::left branch) loc)
                                            (left-ref generating))
                                        (if (right-erased? head)
                                            (declared-LocalRef (::right branch) loc)
                                            (right-ref generating)))
                                  loc)))
        (if (and (any-type? (::output family)) (not (any-type? (::output case))))
            (declared-Convert call any-type loc)
            call)))

    (: left-erased? (impl (Fn Head -> Bool)))
    (define (left-erased? head)
      (match head
        ((ErasedRight _) #f)
        (_ #t)))

    (: right-erased? (impl (Fn Head -> Bool)))
    (define (right-erased? head)
      (match head
        ((ErasedLeft _) #f)
        (_ #t)))

    ;; ---- Failures ----

    ;; After the last case: a concrete left side fails the right, and a
    ;; concrete right side the left; with both erased, a left that some
    ;; case accepts fails the right over that left's cases, in the order
    ;; the lefts are first met, and any other left fails over every left.
    (: family-failure (impl (Fn Generating -> declared-Expr)))
    (define (family-failure generating)
      (let ((cases (::cases (::family generating)))
            (loc (::loc generating)))
        (match (::head (::family generating))
          ((ErasedLeft _) (left-failure generating cases))
          ((ErasedRight _) (right-failure generating cases))
          ((ErasedBoth)
           (fold-right (lambda (left rest)
                         (declared-If (declared-TypeTest (left-ref generating) left loc)
                                      (right-failure generating
                                                     (filter (lambda (case)
                                                               (same-type? left (::left case)))
                                                             cases))
                                      rest
                                      loc))
                       (left-failure generating cases)
                       (delete-duplicates same-type? (map ::left cases)))))))

    (: left-failure (impl (Fn Generating (List Case) -> declared-Expr)))
    (define (left-failure generating cases)
      (cast-failure unsupported-instance-case
                    (delete-duplicates same-type? (map ::left cases))
                    (left-ref generating)
                    (::member generating)
                    0
                    (::loc generating)))

    (: right-failure (impl (Fn Generating (List Case) -> declared-Expr)))
    (define (right-failure generating cases)
      (cast-failure unsupported-instance-case
                    (delete-duplicates same-type? (map ::right cases))
                    (right-ref generating)
                    (::member generating)
                    1
                    (::loc generating)))

    (: left-ref (impl (Fn Generating -> declared-Expr)))
    (define (left-ref generating)
      (declared-LocalRef (::left generating) (::loc generating)))

    (: right-ref (impl (Fn Generating -> declared-Expr)))
    (define (right-ref generating)
      (declared-LocalRef (::right generating) (::loc generating)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-families)
    (import
     (only (snail compiler expand language) Dyn FnContract)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler declare equality) effect-set)
     (only (snail compiler names globals) Global Label)
     (only (snail compiler literals constant) Integer Text)
     (snail stage0 testing))
    (begin
      (define (test-families)
        (test-subtract)
        (test-refusals))

      (define loc (Loc "t.sld" 22 19))
      (define main (list "main"))
      (define base (list "snail" "core" "base"))

      (define (builtin name)
        (declared-Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define (var name) (declared-Var (declared-Written name)))
      (define subtract (Global main "subtract" 0))
      (define log (Global main "log" 0))
      (define class-ref (ClassGlobal (Global main "Subtract" 0)))

      ;; (typeclass (Subtract e A B) (type Output) (: subtract (impl (Fn A B -> Output ! e)))).
      (define subtract-class
        (KnownClass (list (declared-RowParameter "e")
                          (declared-TypeParameter "A")
                          (declared-TypeParameter "B"))
                    (list (declared-Output (Label "Output" loc) (list)))
                    (list (Pair (declared-ClassMethod subtract)
                                (declared-Scheme (list)
                                                 (list)
                                                 (list)
                                                 (declared-Callable
                                                  (Dyn)
                                                  (FnContract)
                                                  (declared-Arrow (list (var "A") (var "B"))
                                                                  (var "Output")
                                                                  (declared-Effects (list)
                                                                                    (Some
                                                                                     (var
                                                                                      "e"))))))))))

      (define (row labels)
        (declared-Row (declared-Effects labels (None))))

      ;; tests/programs/binary-dispatch.sld's sources, in the set `ordinary`.
      (define (source serial labels a b output)
        (Instance (Global main "Subtract" serial)
                  class-ref
                  (list)
                  (list (row labels) a b)
                  (list output)
                  (list)
                  (list)
                  (list (declared-InstanceMethod (declared-ClassMethod subtract)
                                                 (Global main "subtract" serial)
                                                 (declared-Literal (Integer 0) loc)
                                                 loc))
                  loc))

      (define sources
        (list (source 1 (list) i64 i64 i64)
              (source 2 (list log) i64 f64 f64)
              (source 3 (list) f64 i64 f64)))

      ;; ---- The expected code, read off the old compiler's ----

      (define (top global)
        (declared-TopRef (TopGlobal global) loc))

      ;; The left and the right locals numbered `number`.
      (define (left number)
        (Local "left" number))

      (define (right number)
        (Local "right" number))

      (define (ref local)
        (declared-LocalRef local loc))

      (define (call callee arguments)
        (declared-Call callee arguments loc))

      (define (text value)
        (declared-Literal (Text value) loc))

      (define (ok local)
        (declared-Destructure (TopGlobal (Global base "Ok" 0))
                              (list (declared-Bind local loc))
                              loc))

      (define (expected-attempt value target local success failure)
        (declared-Match (declared-TryConvert value target loc)
                        (list (declared-Clause (ok local) success loc)
                              (declared-Clause (declared-Wild loc) failure loc))
                        loc))

      (define (expected-both left
                             left-target
                             right
                             right-target
                             left-local
                             right-local
                             success
                             failure)
        (declared-Match (call (top (Global base "Pair" 0))
                              (list (declared-TryConvert left left-target loc)
                                    (declared-TryConvert right right-target loc)))
                        (list
                         (declared-Clause (declared-Destructure (TopGlobal (Global base "Pair" 0))
                                                                (list (ok left-local)
                                                                      (ok right-local))
                                                                loc)
                                          success
                                          loc)
                         (declared-Clause (declared-Wild loc) failure loc))
                        loc))

      (define (failed expected value index)
        (declared-Match
         (call (top (Global base "conversion-failed" 0))
               (list (call (top (Global base "CastError" 0))
                           (list (call (top (Global base "UnsupportedInstance" 0)) (list))
                                 (fold-right (lambda (name rest)
                                               (call (top (Global base "Cons" 0))
                                                     (list (text name) rest)))
                                             (call (top (Global base "Nil" 0)) (list))
                                             expected)
                                 (call (top (Global (list "prim") "any-type-id" 0)) (list value))
                                 (text "t.sld:22:19")
                                 (text "main:subtract")
                                 (declared-Literal (Integer index) loc)))))
         (list)
         loc))

      (define (to-any expr)
        (declared-Convert expr any-type loc))

      (define (source-call serial left right)
        (call (top (Global main "subtract" serial)) (list left right)))

      ;; The method numbered `global`, whose parameters are numbered after it.
      (define (method global body)
        (declared-InstanceMethod (declared-ClassMethod subtract)
                                 (Global main "subtract" global)
                                 (declared-ClosedLambda
                                  (list (left (+ global 1)) (right (+ global 2)))
                                  body
                                  loc)
                                 loc))

      (define (instance global types output body)
        (Instance (Global main "dynamic" global)
                  class-ref
                  (list)
                  types
                  (list output)
                  (list)
                  (list)
                  (list body)
                  loc))

      (define dyn-row (row (list dyn-cast-effect)))
      (define logged-row (row (effect-set (list dyn-cast-effect log))))

      ;; The heads (Any I64) (I64 Any) (Any Any) (Any F64) (F64 Any), as the
      ;; old compiler writes their methods (build/dispatch-runs/
      ;; old-binary.txt): numbered from 10, each instance's Global, its
      ;; method's, the lambda's two parameters, then two locals a case.
      (define (test-subtract)
        (match (family-instances (Numbering main 10)
                                 subtract-class
                                 class-ref
                                 (list (list i64 i64) (list i64 f64) (list f64 i64))
                                 sources
                                 loc)
          ((Ok
            (Pair (Cons any-i64 (Cons i64-any (Cons any-any (Cons any-f64 (Cons f64-any (Nil))))))
                  next))
           ;; The cases (I64 I64) and (F64 I64), whose outputs differ.
           (expect any-i64
                   (instance 10
                     (list dyn-row any-type i64)
                     any-type
                     (method 11
                             (expected-attempt (ref (left 12))
                                               i64
                                               (left 14)
                                               (to-any
                                                (source-call 1 (ref (left 14)) (ref (right 13))))
                                               (expected-attempt (ref (left 12))
                                                                 f64
                                                                 (left 16)
                                                                 (to-any
                                                                  (source-call 3
                                                                               (ref (left 16))
                                                                               (ref (right 13))))
                                                                 (failed (list "I64" "F64")
                                                                         (ref (left 12))
                                                                         0))))))
           ;; The cases (I64 I64) and (I64 F64), whose source logs.
           (expect i64-any
                   (instance 18
                     (list logged-row i64 any-type)
                     any-type
                     (method 19
                             (expected-attempt (ref (right 21))
                                               i64
                                               (right 23)
                                               (to-any
                                                (source-call 1 (ref (left 20)) (ref (right 23))))
                                               (expected-attempt (ref (right 21))
                                                                 f64
                                                                 (right 25)
                                                                 (to-any
                                                                  (source-call 2
                                                                               (ref (left 20))
                                                                               (ref (right 25))))
                                                                 (failed (list "I64" "F64")
                                                                         (ref (right 21))
                                                                         1))))))
           ;; Every case; after the last, a left some case accepts fails the
           ;; right over that left's cases.
           (expect any-any
                   (instance 26
                     (list logged-row any-type any-type)
                     any-type
                     (method 27
                             (expected-both
                              (ref (left 28))
                              i64
                              (ref (right 29))
                              i64
                              (left 30)
                              (right 31)
                              (to-any (source-call 1 (ref (left 30)) (ref (right 31))))
                              (expected-both
                               (ref (left 28))
                               i64
                               (ref (right 29))
                               f64
                               (left 32)
                               (right 33)
                               (to-any (source-call 2 (ref (left 32)) (ref (right 33))))
                               (expected-both
                                (ref (left 28))
                                f64
                                (ref (right 29))
                                i64
                                (left 34)
                                (right 35)
                                (to-any (source-call 3 (ref (left 34)) (ref (right 35))))
                                (declared-If (declared-TypeTest (ref (left 28)) i64 loc)
                                             (failed (list "I64" "F64") (ref (right 29)) 1)
                                             (declared-If
                                              (declared-TypeTest (ref (left 28)) f64 loc)
                                              (failed (list "I64") (ref (right 29)) 1)
                                              (failed (list "I64" "F64") (ref (left 28)) 0)
                                              loc)
                                             loc)))))))
           ;; One case: its output, F64, is the instance's, so no conversion.
           (expect any-f64
                   (instance 36
                     (list logged-row any-type f64)
                     f64
                     (method 37
                             (expected-attempt (ref (left 38))
                                               i64
                                               (left 40)
                                               (source-call 2 (ref (left 40)) (ref (right 39)))
                                               (failed (list "I64") (ref (left 38)) 0)))))
           (expect (::types f64-any) (list dyn-row f64 any-type))
           (expect next (Numbering main 48)))
          (other (expect other "five generated instances"))))

      ;; Every refusal is at the form, the first in the old order.
      (define (test-refusals)
        (let ((refused (lambda (class pairs sources)
                         (family-instances (Numbering main 1) class class-ref pairs sources loc))))
          (expect (refused (KnownClass (list) (list) (list)) (list (list i64 i64)) sources)
                  (fail loc
                        "dynamic-instances needs a binary class with one effect row and one associated output"))
          (expect (refused subtract-class (list) sources)
                  (fail loc "dynamic-instances needs a nonempty domain of distinct type pairs"))
          ;; error-binary-domain.sld: an Any entry, though a later pair has
          ;; no source.
          (expect (refused subtract-class (list (list any-type i64) (list f64 f64)) sources)
                  (fail loc "dynamic-instances domain entries are two concrete, non-Any types"))
          ;; error-binary-source-inactive.sld: no source is active.
          (expect (refused subtract-class (list (list i64 i64)) (list))
                  (fail loc "dynamic-instances has no active source instance for a domain pair"))
          (expect (refused subtract-class
                           (list (list (row (list)) i64))
                           (list (Instance (Global main "Subtract" 9)
                                           class-ref
                                           (list (declared-Written "a"))
                                           (list (row (list)) (var "a") i64)
                                           (list i64)
                                           (list)
                                           (list)
                                           (list
                                            (declared-InstanceMethod (declared-ClassMethod subtract)
                                                                     (Global main "subtract" 9)
                                                                     (declared-Literal (Integer 0)
                                                                                       loc)
                                                                     loc))
                                           loc)))
                  (fail loc "a Subtract instance gives its type parameter A a row, not a type"))))))
   (else)))
