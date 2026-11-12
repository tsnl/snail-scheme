;; The pass `cohere`: no two instances that can be active together overlap
;; on their selecting types, as (snail compiler dispatch overlap) decides,
;; so that the type checker's choice of an instance never has two answers.
;; It checks a dispatched library and writes nothing. It is handed the
;; library and the listing of every library compiled before it, in the
;; program's order, whether or not the library imports them, since
;; instances are global; it lists the library's own instances itself.
;;
;; It makes the old compiler's two checks, in its order. First, as the old
;; compiler declares each instance (`check-overlap`,
;; src/snail/shell/compiler/expand.sld), each instance the library
;; declares, written, derived or generated, against those of its class
;; declared before it in its set, or, when it is in none, in none. The
;; first instance that overlaps one is the library's only problem, at the
;; instance. Then, when none does, as the old compiler checks each
;; top-level `with-instances` once every declaration is reached
;; (`check-active-instances`, src/snail/shell/compiler/core.sld), each
;; instance scope, whether two instances active under it overlap: one
;; problem at each scope where two do, every scope's, in order.
(define-library (snail compiler cohere pass)
  (export
   cohere)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler expand language) Global)
   (only (snail compiler declare equality) same-global?)
   (prefix (snail compiler dispatch language) dispatched-)
   (only (snail compiler dispatch listing)
         Listed
         ListedInstance
         FieldInstance
         library-instances
         listed-set)
   (snail compiler dispatch overlap))
  (begin

    ;; ---- The pass ----

    ;; `earlier` holds the listing of each library before this one in the
    ;; program, in order, each library's instances in turn.
    (: cohere (impl (Fn dispatched-Dispatched (List Listed) -> (Result Unit (List Feedback)))))
    (define (cohere library earlier)
      (let ((own (library-instances library)))
        (match (first-overlapping earlier own)
          ((Some instance) (fail (::loc instance) overlap-problem))
          ((None)
           (match (scope-problems (append earlier own) (Nil) (library-tops library))
             ((Nil) (Ok (unit)))
             (problems (Err problems)))))))

    (: library-tops (impl (Fn dispatched-Dispatched -> (List dispatched-Top))))
    (define (library-tops library)
      (match library
        ((dispatched-Defined _ tops _ _) tops)
        ((dispatched-Program tops _ _) tops)))

    ;; ---- Instances ----

    ;; The first of `own`, the library's instances in order, that overlaps
    ;; an instance before it in its set, or in none when it is in none.
    ;; The old compiler compares each instance as it declares it, so an
    ;; instance sees only those declared before it: the earlier libraries',
    ;; then its own library's up to it, a struct's field instances from the
    ;; struct on, and a form's earlier instances among them. A field
    ;; instance joins there without being compared, so it is never the one
    ;; refused: an instance of a field class written before its struct is
    ;; accepted, and one written after it refused (tests/programs/
    ;; field-instance-before-struct.sld and error-field-instance-overlap.sld).
    ;; Since the relation is asymmetric, the later instance is the one
    ;; asked about.
    (: first-overlapping (impl (Fn (List Listed) (List Listed) -> (Option dispatched-Instance))))
    (define (first-overlapping earlier own)
      (let loop ((before earlier)
                 (own own))
        (match own
          ((Nil) (None))
          ((Cons listed rest)
           (match listed
             ((ListedInstance instance _)
              (if (overlaps-one? listed before)
                  (Some instance)
                  (loop (Cons listed before) rest)))
             ((FieldInstance _ _) (loop (Cons listed before) rest)))))))

    ;; Whether `listed` overlaps one of `before`, in no particular order,
    ;; that is in its set or, like it, in none. Two sets are compared
    ;; apart, though a scope may activate both, and one set's instances
    ;; are compared though none activates it.
    (: overlaps-one? (impl (Fn Listed (List Listed) -> Bool)))
    (define (overlaps-one? listed before)
      (any? (lambda (other) (and (same-set? listed other) (overlaps? listed other))) before))

    (: same-set? (impl (Fn Listed Listed -> Bool)))
    (define (same-set? listed other)
      (match (Pair (listed-set listed) (listed-set other))
        ((Pair (None) (None)) #t)
        ((Pair (Some set) (Some other-set)) (same-global? set other-set))
        (_ #f)))

    ;; ---- Scopes ----

    ;; One problem for each instance scope among `tops` under which two
    ;; of `instances` overlap, at the scope, in order, a scope before those
    ;; it holds. `around` holds the sets of the scopes around `tops`; a
    ;; scope activates its own sets and those, and a top-level scope is in
    ;; no set. Unlike an instance, a scope sees every instance of the
    ;; program so far, its own library's written after it too
    ;; (tests/programs/error-scope-later-overlap.sld), since the old
    ;; compiler checks scopes once every declaration is reached; and two
    ;; instances overlap there when either overlaps the other
    ;; (tests/programs/error-scope-asymmetric-overlap.sld).
    (: scope-problems
       (impl (Fn (List Listed) (List Global) (List dispatched-Top) -> (List Feedback))))
    (define (scope-problems instances around tops)
      (concatenate (map (lambda (top) (top-problems instances around top)) tops)))

    (: top-problems (impl (Fn (List Listed) (List Global) dispatched-Top -> (List Feedback))))
    (define (top-problems instances around top)
      (match top
        ((dispatched-InstanceScope sets tops loc)
         (let ((active (append sets around)))
           (append (if (active-overlap? active instances)
                       (list (Feedback loc overlap-problem))
                       (Nil))
                   (scope-problems instances active tops))))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-cohere)
    (import
     (only (snail compiler expand language) ClassGlobal FieldClass Dyn FnContract)
     (prefix (snail compiler declare language) declared-)
     (only (snail compiler declare forms) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-cohere)
        (test-asymmetric)
        (test-sets)
        (test-earlier)
        (test-fields)
        (test-generated)
        (test-first-only)
        (test-scope-symmetric)
        (test-scope-later)
        (test-scopes-all)
        (test-nested))

      (define main (list "main"))
      (define lib (list "lib"))

      (define (at line)
        (Loc "probe.sld" line 1))

      (define (builtin name)
        (declared-Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define any-type (builtin "Any"))

      ;; `(dyn (Fn I64 -> I64))`
      (define function
        (declared-Callable (Dyn)
                           (FnContract)
                           (declared-Arrow (list i64) i64 (declared-Effects (list) (None)))))

      (define (instance library class serial types line)
        (dispatched-Instance (Global library (::name class) serial)
                             (ClassGlobal class)
                             (list)
                             types
                             (list)
                             (list)
                             (list)
                             (list)
                             (at line)))

      ;; `(instance (Probe type) ...)` at `line`, of the class
      ;; `(typeclass (Probe T) (: probe (impl (Fn T -> I64))))`.
      (define (probe type line)
        (instance main (Global main "Probe" 0) line (list type) line))

      (define (top-probe type line)
        (dispatched-TopInstance (probe type line)))

      (define (set name line instances)
        (dispatched-InstanceSet (Global main name 0) instances (at line)))

      (define (scope names line tops)
        (dispatched-InstanceScope (map (lambda (name) (Global main name 0)) names) tops (at line)))

      (define (library tops)
        (dispatched-Defined main tops 0 (at 0)))

      (define (refused-at lines)
        (Err (map (lambda (line) (Feedback (at line) overlap-problem)) lines)))

      (define coheres (Ok (unit)))

      ;; tests/programs/error-asymmetric-overlap.sld and
      ;; asymmetric-overlap.sld: a bare function overlaps I64, and I64 does
      ;; not overlap it, so the same two instances are refused in one order,
      ;; at the second, and accepted in the other.
      (define (test-asymmetric)
        (expect (cohere (library (list (top-probe i64 6) (top-probe function 8))) (list))
                (refused-at (list 8)))
        (expect (cohere (library (list (top-probe function 6) (top-probe i64 8))) (list))
                coheres)
        (expect (cohere (dispatched-Program (list (top-probe i64 6) (top-probe function 8))
                                            (None)
                                            0)
                        (list))
                (refused-at (list 8))))

      ;; Instances of one set are compared though no scope activates it;
      ;; two sets, or a set and none, are not compared.
      (define (test-sets)
        (expect (cohere (library (list (set "policy" 3 (list (probe i64 4) (probe i64 5))))) (list))
                (refused-at (list 5)))
        (expect (cohere (library (list (set "first" 3 (list (probe i64 4)))
                                       (set "second" 5 (list (probe i64 6)))))
                        (list))
                coheres)
        (expect (cohere (library (list (top-probe i64 3) (set "policy" 4 (list (probe i64 5)))))
                        (list))
                coheres))

      ;; tests/programs/error-overlap.sld: an instance overlaps one of an
      ;; earlier library, in no set when it is in none; an earlier library's
      ;; set is another set; and the earlier libraries' instances are never
      ;; the ones asked about, being checked with their own libraries.
      (define (test-earlier)
        (let ((lib-probe (lambda (serial type set)
                           (ListedInstance
                            (instance lib (Global lib "Probe" 0) serial (list type) 1)
                            set)))
              (lib-set (Some (Global lib "policy" 0)))
              (own
               (lambda (type line) (instance main (Global lib "Probe" 0) line (list type) line))))
          (expect (cohere (library (list (dispatched-TopInstance (own i64 4))))
                          (list (lib-probe 1 i64 (None))))
                  (refused-at (list 4)))
          (expect (cohere (library (list (set "policy" 3 (list (own i64 4)))))
                          (list (lib-probe 1 i64 lib-set)))
                  coheres)
          (expect (cohere (library (list (dispatched-TopInstance (own f64 4))))
                          (list (lib-probe 1 i64 (None)) (lib-probe 2 i64 (None))))
                  coheres)))

      (define point-global (Global main "Point" 0))

      ;; `(struct Point ((x I64)))` at `line`.
      (define (point line)
        (dispatched-TopData
         (declared-Data point-global
                        (list)
                        (list (declared-DataCase point-global
                                                 0
                                                 (list
                                                  (declared-DataField "x" #f i64 (list) (at line)))
                                                 (list)
                                                 (at line)))
                        (declared-StructData)
                        #f
                        #f
                        (list)
                        (at line))))

      ;; `(instance (::x Point I64) ...)` at `line`.
      (define (x-instance line)
        (dispatched-TopInstance (dispatched-Instance (Global main "x" line)
                                                     (FieldClass "x")
                                                     (list)
                                                     (list (declared-Con point-global (list)) i64)
                                                     (list)
                                                     (list)
                                                     (list)
                                                     (list)
                                                     (at line))))

      ;; tests/programs/error-field-instance-overlap.sld and
      ;; field-instance-before-struct.sld: a struct's field instance is
      ;; compared with an instance written after it, but is never the one
      ;; asked about; at a scope, though, the two are paired.
      (define (test-fields)
        (expect (cohere (library (list (point 4) (x-instance 6))) (list)) (refused-at (list 6)))
        (expect (cohere (library (list (x-instance 4) (point 6))) (list)) coheres)
        (expect (cohere (library (list (x-instance 4) (point 6) (scope (list) 8 (list)))) (list))
                (refused-at (list 8))))

      ;; `(instance (Op (!) left right) (type Output I64) ...)`, generated or
      ;; written at `line`, of `(typeclass (Op e A B) (type Output) ...)`.
      (define (op left right serial line)
        (dispatched-Instance (Global main "dynamic" serial)
                             (ClassGlobal (Global main "Op" 0))
                             (list)
                             (list (declared-Row (declared-Effects (list) (None))) left right)
                             (list i64)
                             (list)
                             (list)
                             (list)
                             (at line)))

      ;; tests/programs/error-binary-head-overlap.sld: a form's instances,
      ;; all at the form, are each compared with those before it in its
      ;; set, the form's earlier ones among them, and the head (Any F) for a
      ;; bare function F overlaps (Any I64). The sources, in two sets, are
      ;; not compared, and the scope that activates both is not reached.
      (define (test-generated)
        (expect (cohere (library
                            (list (set "numbers" 7 (list (op i64 i64 1 8)))
                                  (set "functions" 11 (list (op i64 function 2 12)))
                                  (scope (list "numbers" "functions")
                                         15
                                         (list (set "dynamic"
                                                    16
                                                    (list (op any-type i64 3 17)
                                                          (op i64 any-type 4 17)
                                                          (op any-type any-type 5 17)
                                                          (op any-type function 6 17)))))))
                        (list))
                (refused-at (list 17)))
        (expect (cohere (library (list (set "numbers" 7 (list (op i64 i64 1 8)))
                                       (set "functions" 11 (list (op i64 function 2 12)))
                                       (scope (list "numbers" "functions") 15 (list))))
                        (list))
                (refused-at (list 15))))

      ;; The first instance that overlaps is the only problem, and no scope
      ;; is checked after it.
      (define (test-first-only)
        (expect (cohere (library (list (top-probe i64 3)
                                       (top-probe i64 4)
                                       (top-probe f64 5)
                                       (top-probe f64 6)
                                       (scope (list) 7 (list))))
                        (list))
                (refused-at (list 4))))

      ;; tests/programs/error-scope-asymmetric-overlap.sld: the two instances
      ;; accepted in this order are refused at a scope, which asks of each
      ;; pair both ways, though it activates an empty set.
      (define (test-scope-symmetric)
        (expect (cohere (library (list (top-probe function 6)
                                       (top-probe i64 8)
                                       (set "none" 10 (list))
                                       (scope (list "none") 11 (list))))
                        (list))
                (refused-at (list 11))))

      ;; tests/programs/error-scope-later-overlap.sld: a scope sees the
      ;; instances of a set declared after it; and the earlier libraries'.
      (define (test-scope-later)
        (expect (cohere (library (list (top-probe i64 6)
                                       (scope (list "later") 8 (list))
                                       (set "later" 9 (list (probe i64 10)))))
                        (list))
                (refused-at (list 8)))
        (expect (cohere (library (list (dispatched-TopInstance
                                        (instance main (Global lib "Probe" 0) 6 (list i64) 6))
                                       (dispatched-InstanceScope (list (Global lib "later" 0))
                                                                 (list)
                                                                 (at 8))))
                        (list (ListedInstance (instance lib (Global lib "Probe" 0) 1 (list i64) 1)
                                              (Some (Global lib "later" 0)))))
                (refused-at (list 8))))

      ;; tests/programs/error-scopes-overlap.sld: each scope's problem
      ;; is reported, in order.
      (define (test-scopes-all)
        (expect (cohere (library (list (set "first-policy" 6 (list (probe i64 7)))
                                       (set "second-policy" 9 (list (probe i64 10)))
                                       (scope (list "first-policy" "second-policy") 12 (list))
                                       (scope (list "second-policy" "first-policy") 13 (list))))
                        (list))
                (refused-at (list 12 13))))

      ;; tests/programs/error-instance-set-nested.sld: a scope activates
      ;; the sets of the scopes around it too, and is checked after them.
      (define (test-nested)
        (let ((policies (lambda (outer)
                          (library (list (set "first-policy" 8 (list (probe i64 9)))
                                         (set "second-policy" 12 (list (probe i64 13)))
                                         (scope outer
                                                16
                                                (list
                                                 (scope (list "second-policy") 17 (list)))))))))
          (expect (cohere (policies (list "first-policy")) (list)) (refused-at (list 17)))
          (expect (cohere (policies (list "first-policy" "second-policy")) (list))
                  (refused-at (list 16 17)))))))
   (else)))
