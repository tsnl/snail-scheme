;; Whether a struct can be built, as the old compiler's `contains-itself?`
;; (src/snail/shell/compiler/capabilities.sld) decides it. A struct whose
;; every value would hold another value of itself, through struct fields
;; and cells, which are structs, can never be built: no finite program
;; constructs one. The backend relies on the rule, since a call that may
;; yield returns a placeholder of its type, a constant it could not write
;; for such a struct. The search follows the fields of each struct a field's
;; type names, at that type's arguments, and stops at every other type,
;; each of which has a value that holds no struct: an enum's tag, a
;; builtin's empty array or string, an Any, a function. A struct is entered
;; once on each path: one that reached its own name would itself contain
;; itself, and is refused where it is declared. An empty type is an enum
;; with no cases.
(define-library (snail compiler declare buildable)
  (export
   struct-problem)
  (import
   (snail core base)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler types equality)
   (only (snail compiler names globals) Global same-global?)
   (snail compiler declare schemes)
   (snail compiler types type)
   (only (snail compiler types substitution) substituted))
  (begin

    ;; ---- Structs ----

    ;; `data` is a struct, and `known` knows every data type its fields
    ;; can name: the library's own, every declaration being reached, and
    ;; those of its import closure.
    (: struct-problem (impl (Fn Known Data -> (Option String))))
    (define (struct-problem known data)
      (if (any? (lambda (type) (reaches? known (::global data) type (Nil)))
                (field-types data (map (lambda (name) (Var (Written name))) (::parameters data))))
          (Some (string-append "the struct "
                               (::name (::global data))
                               " can never be built: each of its values would contain another"))
          (None)))

    ;; Whether every value of `type` holds a value of the struct `target`,
    ;; the structs in `entered` being those the path has entered. A
    ;; builtin is no data type, so the search stops there.
    (: reaches? (impl (Fn Known Global Type (List Global) -> Bool)))
    (define (reaches? known target type entered)
      (match type
        ((Con global arguments)
         (cond ((same-global? global target) #t)
               ((any? (lambda (other) (same-global? other global)) entered) #f)
               (else (match (known-data known global)
                       ((Some data)
                        (and (struct? data)
                             (any? (lambda (field)
                                     (reaches? known target field (Cons global entered)))
                                   (field-types data arguments))))
                       ((None) #f)))))
        (_ #f)))

    (: struct? (impl (Fn Data -> Bool)))
    (define (struct? data)
      (match (::kind data)
        ((StructData) #t)
        ((EnumData) #f)))

    ;; The types of a struct's fields, those of its one case, at the
    ;; type's `arguments`.
    (: field-types (impl (Fn Data (List Type) -> (List Type))))
    (define (field-types data arguments)
      (let ((bindings (zip (map Written (::parameters data)) arguments)))
        (concatenate (map (lambda (case)
                            (map (lambda (field) (substituted bindings (::type field)))
                                 (::fields case)))
                          (::cases data)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-buildable)
    (import
     (snail core table)
     (snail compiler source)
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-buildable)
        (test-cycles)
        (test-stops))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define lib (list "lib"))

      (define (global library name)
        (Global library name 0))

      (define (field type)
        (DataField "f" #f type (list) loc))

      (define (struct-of library name parameters types)
        (Data (global library name)
              parameters
              (list (DataCase (global library name) 0 (map field types) (list) loc))
              (StructData)
              #f
              #f
              (list)
              loc))

      (define (con library name arguments)
        (Con (global library name) arguments))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      ;; (lib) offers the struct (Ref a), a cell, and the enum (Option a).
      (define ref (struct-of lib "Ref" (list "a") (list (Var (Written "a")))))
      (define option
        (Data (global lib "Option")
              (list "a")
              (list (DataCase (global lib "None") 0 (list) (list) loc)
                    (DataCase (global lib "Some") 1 (list (field (Var (Written "a")))) (list) loc))
              (EnumData)
              #f
              #f
              (list)
              loc))

      ;; What is known once each of `types` of (main) is reached.
      (define (known-of types)
        (fold-left known-with-data
                   (Known main
                          (Scanned empty-table empty-table)
                          (Declarations main empty-table empty-table empty-table)
                          (list (Declarations lib
                                              (by-name (by-name empty-table "Ref" ref)
                                                       "Option"
                                                       option)
                                              empty-table
                                              empty-table)))
                   types))

      (define (never name)
        (Some (string-append "the struct "
                             name
                             " can never be built: each of its values would contain another")))

      ;; Read off error-struct-contains-itself.sld: through a cell of
      ;; another library, at the struct's argument; through another struct
      ;; of the library; through a struct's argument.
      (define (test-cycles)
        (let ((node (struct-of main
                               "Node"
                               (list)
                               (list (con lib "Ref" (list (con main "Node" (list)))))))
              (a (struct-of main "A" (list) (list i64 (con main "B" (list)))))
              (b (struct-of main "B" (list) (list (con main "A" (list)))))
              (wrap (struct-of main "Wrap" (list "t") (list (Var (Written "t")))))
              (loop (struct-of main
                               "Loop"
                               (list "t")
                               (list (con main
                                          "Wrap"
                                          (list (con main "Loop" (list (Var (Written "t"))))))))))
          (expect (struct-problem (known-of (list node)) node) (never "Node"))
          (expect (struct-problem (known-of (list a b)) a) (never "A"))
          (expect (struct-problem (known-of (list a b)) b) (never "B"))
          (expect (struct-problem (known-of (list wrap loop)) loop) (never "Loop"))
          (expect (struct-problem (known-of (list wrap loop)) wrap) (None))))

      ;; An enum, a builtin, a function and a variable each have a value
      ;; that holds no struct; a struct entered once on a path is not
      ;; entered again, so one that contains another that contains itself
      ;; is buildable itself.
      (define (test-stops)
        (let* ((list-node (struct-of main
                                     "ListNode"
                                     (list)
                                     (list (con lib "Option" (list (con main "ListNode" (list)))))))
               (in-array (struct-of main
                                    "Grid"
                                    (list)
                                    (list (Con (Global forms-library "Array" 0)
                                               (list (con main "Grid" (list)))))))
               (in-function (struct-of main
                                       "Thunk"
                                       (list)
                                       (list (Callable (Dyn)
                                                       (FnContract)
                                                       (Arrow (list)
                                                              (con main "Thunk" (list))
                                                              (Effects (list) (None)))))))
               (self (struct-of main "Self" (list) (list (con main "Self" (list)))))
               (holder (struct-of main "Holder" (list) (list (con main "Self" (list))))))
          (expect (struct-problem (known-of (list list-node)) list-node) (None))
          (expect (struct-problem (known-of (list in-array)) in-array) (None))
          (expect (struct-problem (known-of (list in-function)) in-function) (None))
          (expect (struct-problem (known-of (list self holder)) holder) (None))
          (expect (struct-problem (known-of (list self holder)) self) (never "Self"))))))
   (else)))
