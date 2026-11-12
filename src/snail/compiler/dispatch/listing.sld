;; Query: every instance a dispatched library declares, in the order the
;; old compiler enters them into its program, and what the passes that
;; compare or choose instances read of one. Instances are global: the
;; integrator keeps this listing of each library, and hands `dispatch` and
;; `cohere`, and later `solve`, the listings of every library before the
;; one they work on, in the program's order, whether or not it imports
;; them.
;;
;;   Listed ::= ListedInstance Instance set?          no Loc but its instance's
;;            | FieldInstance Data DataField          no Loc
;;
;; A ListedInstance is an Instance node of the tree, written, derived,
;; written with a dispatch clause or generated, with the set it is in when
;; it is in one. A FieldInstance is the instance a struct with no mutable
;; field implies for each of its fields, `(::label (S p ...) type)` at the
;; struct's parameters, read by the field's accessor; the old compiler
;; names it `lib:::label@S` and enters it at the struct's declaration,
;; where it is never compared with the instances before it. Both are listed
;; where they are declared: an instance at its place, a field instance at
;; its struct, in field order; an instance scope's declarations in turn,
;; an instance set's in order.
;;
;; The selecting types of an instance are the types its head gives the
;; class's parameters that are no rows, which Declared says are exactly the
;; types that are no Row; a field instance's are its record type and its
;; field's type. Outputs and rows never select. The old compiler drops a
;; row parameter's type by the class as it is when it looks, so the two
;; differ only for an instance written before its class in its library
;; that gives a type to a parameter the class later makes a row, which
;; implements no method. An instance is active under a list of sets when
;; it is in no set or in one of them.
(define-library (snail compiler dispatch listing)
  (export
   Listed
   ListedInstance
   FieldInstance
   library-instances
   tops-instances
   listed-class
   listed-variables
   listed-types
   listed-outputs
   listed-requirements
   listed-copied
   listed-set
   selecting-types
   instance-selecting-types
   same-class?
   active?)
  (import
   (snail core base)
   (only (snail compiler declare language)
         Data
         DataField
         Type
         Con
         Row
         Var
         Written
         TypeVariable
         Requirement)
   (only (snail compiler names globals) Global ClassRef ClassGlobal FieldClass same-global?)
   (only (snail compiler declare schemes) pure-struct?)
   (snail compiler dispatch language))
  (begin

    ;; ---- Listings ----

    (enum Listed
      (ListedInstance
       ((instance Instance)
        (set (Option Global))))
      (FieldInstance
       ((data Data)
        (field DataField))))

    ;; Every instance the library declares, in order.
    (: library-instances (impl (Fn Dispatched -> (List Listed))))
    (define (library-instances library)
      (match library
        ((Defined _ tops _ _) (tops-instances tops))
        ((Program tops _) (tops-instances tops))))

    ;; The instances `tops` declare, in order, those of a set in that set.
    (: tops-instances (impl (Fn (List Top) -> (List Listed))))
    (define (tops-instances tops)
      (concatenate (map top-instances tops)))

    (: top-instances (impl (Fn Top -> (List Listed))))
    (define (top-instances top)
      (match top
        ((TopData data) (field-instances data))
        ((TopInstance instance) (list (ListedInstance instance (None))))
        ((InstanceSet global instances _)
         (map (lambda (instance) (ListedInstance instance (Some global))) instances))
        ((InstanceScope _ tops _) (tops-instances tops))
        (_ (Nil))))

    ;; A struct with no mutable field implies an instance for each field.
    (: field-instances (impl (Fn Data -> (List Listed))))
    (define (field-instances data)
      (concatenate (map (lambda (case)
                          (if (pure-struct? data case)
                              (map (lambda (field) (FieldInstance data field)) (::fields case))
                              (Nil)))
                        (::cases data))))

    ;; ---- One instance ----

    ;; A field instance's class is its label's, its variables its
    ;; struct's parameters, its types the struct at them and the field's
    ;; type; it has no outputs, requirements, Copy variables or set.
    (: listed-class (impl (Fn Listed -> ClassRef)))
    (define (listed-class listed)
      (match listed
        ((ListedInstance instance _) (::class instance))
        ((FieldInstance _ field) (FieldClass (::label field)))))

    (: listed-variables (impl (Fn Listed -> (List TypeVariable))))
    (define (listed-variables listed)
      (match listed
        ((ListedInstance instance _) (::variables instance))
        ((FieldInstance data _) (map Written (::parameters data)))))

    (: listed-types (impl (Fn Listed -> (List Type))))
    (define (listed-types listed)
      (match listed
        ((ListedInstance instance _) (::types instance))
        ((FieldInstance data field)
         (list (Con (::global data)
                    (map (lambda (parameter) (Var (Written parameter))) (::parameters data)))
               (::type field)))))

    (: listed-outputs (impl (Fn Listed -> (List Type))))
    (define (listed-outputs listed)
      (match listed
        ((ListedInstance instance _) (::outputs instance))
        ((FieldInstance _ _) (Nil))))

    (: listed-requirements (impl (Fn Listed -> (List Requirement))))
    (define (listed-requirements listed)
      (match listed
        ((ListedInstance instance _) (::requirements instance))
        ((FieldInstance _ _) (Nil))))

    (: listed-copied (impl (Fn Listed -> (List TypeVariable))))
    (define (listed-copied listed)
      (match listed
        ((ListedInstance instance _) (::copied instance))
        ((FieldInstance _ _) (Nil))))

    (: listed-set (impl (Fn Listed -> (Option Global))))
    (define (listed-set listed)
      (match listed
        ((ListedInstance _ set) set)
        ((FieldInstance _ _) (None))))

    ;; The types the instance is chosen by: its head's types that are no
    ;; row.
    (: selecting-types (impl (Fn Listed -> (List Type))))
    (define (selecting-types listed)
      (no-rows (listed-types listed)))

    ;; An instance node's, as `selecting-types` reads it when it is listed.
    (: instance-selecting-types (impl (Fn Instance -> (List Type))))
    (define (instance-selecting-types instance)
      (no-rows (::types instance)))

    (: no-rows (impl (Fn (List Type) -> (List Type))))
    (define (no-rows types)
      (filter (lambda (type)
                (match type
                  ((Row _) #f)
                  (_ #t)))
              types))

    ;; A class is one Global, or one label's field class.
    (: same-class? (impl (Fn ClassRef ClassRef -> Bool)))
    (define (same-class? class other)
      (match (Pair class other)
        ((Pair (ClassGlobal global) (ClassGlobal other-global)) (same-global? global other-global))
        ((Pair (FieldClass label) (FieldClass other-label)) (string=? label other-label))
        (_ #f)))

    ;; Whether the instance is active under `sets`: in no set, or in one.
    (: active? (impl (Fn (List Global) Listed -> Bool)))
    (define (active? sets listed)
      (match (listed-set listed)
        ((None) #t)
        ((Some set) (any? (lambda (active) (same-global? active set)) sets))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-listing)
    (import
     (snail compiler source)
     (only (snail compiler declare language)
           DataCase
           StructData
           EnumData
           Effects
           InstanceMethod
           ClassMethod
           Literal)
     (only (snail compiler literals constant) UnitValue)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-listing)
        (test-order)
        (test-instances)
        (test-classes))

      (define (at line)
        (Loc "t.sld" line 1))

      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define (field label mutable?)
        (DataField label mutable? i64 (list) (at 1)))

      (define (struct-of name parameters fields line)
        (Data (global name)
              parameters
              (list (DataCase (global name) 0 fields (list) (at line)))
              (StructData)
              #f
              #f
              (list)
              (at line)))

      ;; (Show a) at `types`, written at `line`, implementing show.
      (define (show-at types line)
        (Instance (Global main "Show" line)
                  (ClassGlobal (global "Show"))
                  (list)
                  types
                  (list)
                  (list)
                  (list)
                  (list (InstanceMethod (ClassMethod (global "show"))
                                        (Global main "show" (+ line 100))
                                        (Literal (UnitValue) (at line))
                                        (at line)))
                  (at line)))

      (define point (struct-of "Point" (list "a") (list (field "x" #f) (field "y" #f)) 1))
      (define cell (struct-of "Cell" (list) (list (field "value" #t)) 2))
      (define shape
        (Data (global "Shape")
              (list)
              (list (DataCase (global "Circle") 0 (list (field "r" #f)) (list) (at 3)))
              (EnumData)
              #f
              #f
              (list)
              (at 3)))

      ;; A pure struct's field instances where it is declared, in field
      ;; order; none for a struct with a mutable field or an enum; an
      ;; instance scope's in turn; a set's in order, in that set.
      (define (test-order)
        (let* ((plain (show-at (list i64) 4))
               (in-set (show-at (list (Var (Written "t"))) 5))
               (second-in-set (show-at (list (Con (global "Point") (list i64))) 6))
               (scoped (show-at (list (Con (global "Cell") (list))) 8))
               (listed
                (library-instances
                 (Defined main
                   (list (TopData cell)
                         (TopInstance plain)
                         (TopData shape)
                         (InstanceSet (global "set") (list in-set second-in-set) (at 5))
                         (InstanceScope (list (global "set"))
                                        (list (TopData point) (TopInstance scoped))
                                        (at 7))
                         (Statement (Literal (UnitValue) (at 9))))
                   900
                   (at 1)))))
          (expect listed
                  (list (ListedInstance plain (None))
                        (ListedInstance in-set (Some (global "set")))
                        (ListedInstance second-in-set (Some (global "set")))
                        (FieldInstance point (field "x" #f))
                        (FieldInstance point (field "y" #f))
                        (ListedInstance scoped (None))))
          (expect (library-instances (Program (list (TopInstance plain)) 900))
                  (list (ListedInstance plain (None))))))

      ;; What each kind of entry gives: a field instance is its struct at
      ;; its parameters and its field's type, of its label's class, in no
      ;; set; a row never selects.
      (define (test-instances)
        (let* ((row (Row (Effects (list (global "io")) (None))))
               (store (Instance (Global main "Store" 1)
                                (ClassGlobal (global "Store"))
                                (list (Written "t"))
                                (list row (Var (Written "t")))
                                (list i64)
                                (list)
                                (list (Written "t"))
                                (list)
                                (at 1)))
               (listed (ListedInstance store (Some (global "set"))))
               (implied (FieldInstance point (field "x" #f))))
          (expect (map (lambda (entry)
                         (list (listed-class entry)
                               (listed-variables entry)
                               (listed-types entry)
                               (listed-outputs entry)
                               (listed-copied entry)
                               (listed-set entry)))
                       (list listed implied))
                  (list (list (ClassGlobal (global "Store"))
                              (list (Written "t"))
                              (list row (Var (Written "t")))
                              (list i64)
                              (list (Written "t"))
                              (Some (global "set")))
                        (list (FieldClass "x")
                              (list (Written "a"))
                              (list (Con (global "Point") (list (Var (Written "a")))) i64)
                              (list)
                              (list)
                              (None))))
          (expect (selecting-types listed) (list (Var (Written "t"))))
          (expect (selecting-types implied)
                  (list (Con (global "Point") (list (Var (Written "a")))) i64))
          (expect (listed-requirements implied) (list))
          (expect (map (lambda (sets) (active? sets listed))
                       (list (list) (list (global "other")) (list (global "other") (global "set"))))
                  (list #f #f #t))
          (expect (active? (list) implied) #t)))

      (define (test-classes)
        (expect (same-class? (ClassGlobal (global "Show")) (ClassGlobal (global "Show"))) #t)
        (expect (same-class? (ClassGlobal (global "Show")) (ClassGlobal (Global main "Show" 3))) #f)
        (expect (same-class? (FieldClass "x") (FieldClass "x")) #t)
        (expect (same-class? (FieldClass "x") (ClassGlobal (global "x"))) #f))))
   (else)))
