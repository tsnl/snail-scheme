;; The entities `declare` makes beside the old expander's program: the
;; conversions from Declared to the old compiler's data, which milestone A
;; hands the old checker, and the comparison of each library's entities
;; with the old program's, which (snail compiler adapter expansion) runs
;; for every program both compilers expand.
;;
;; A Global is the old compiler's unique name: its library's parts joined
;; by dots, a colon and its name, or a builtin's name alone; one a macro's
;; template wrote is `name%m.serial`, in the form of the old compiler's
;; marked names, whose stamp no new pass has. The texts compared drop the
;; number after each `%m.`, so a macro-written name is compared by the
;; name written. A row's labels are compared as a set, since the old
;; compiler writes an operation's own effect first.
;;
;; For each library, the comparison holds, sorted by name: its data types,
;; with whether each is owned, which deriving Move or a Drop instance
;; makes it; its classes, with their rows, outputs and methods; its
;; effects, with each default by its operation; and every value it
;; declares by its kind and scheme, but those the old compiler names
;; afresh, an implementation, a default, a generated dispatch method, and
;; a linked file's handle. Then, class by class, its listing, as
;; (snail compiler dispatch listing) lists the library dispatched, beside
;; the old program's instances of the class the library declares, in the
;; old order: written, derived, written with a dispatch clause, generated
;; by `dynamic-instances` and implied by a struct's fields, by their heads,
;; variables, requirements, sets, the members their methods implement and
;; each implementation's scheme.
(define-library (snail compiler adapter declaration)
  (export
   old-name
   old-type
   old-scheme
   old-data
   old-class
   old-effect
   old-instance
   normal-type-text
   declaration-differences)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (only (snail compiler outline names) same-library? library-key)
   (only (snail compiler expand language)
         Global
         TopGlobal
         FieldFunction
         FieldRole
         Accessor
         Replacer
         Setter
         Swapper
         ClassRef
         ClassGlobal
         FieldClass
         Former
         Impl
         Dyn
         Contract
         FnContract
         FnMutContract
         FnOnceContract)
   (except (snail compiler declare language)
           Defined
           Program
           Top
           LinkImport
           Define
           Statement
           Expose
           TopData
           Alias
           TopClass
           TopInstance
           InstanceSet
           InstanceScope
           Extern
           TopEffect
           Primitive
           Instance)
   (prefix (only (snail compiler declare language) Instance) declared-)
   (snail compiler declare offer)
   (snail compiler declare forms)
   (snail compiler declare equality)
   (snail compiler declare schemes)
   (snail compiler dispatch language)
   (snail compiler dispatch listing)
   (only (snail compiler integrate compile) CompiledFile)
   (prefix (only (snail shell compiler read) Loc) old:)
   (prefix (only (snail shell compiler core)
                 Type
                 TCon
                 TFun
                 TRow
                 TVar
                 TRigid
                 Constraint
                 Scheme
                 DataType
                 Case
                 Field
                 Class
                 Instance
                 Effect
                 Import
                 Value
                 Defined
                 Constructor
                 Accessor
                 Replacer
                 Setter
                 Swapper
                 Method
                 Operation
                 Primitive
                 Foreign
                 Program
                 label-union
                 class-instances)
           old:))
  (begin

    ;; ---- Names ----

    (: old-name (impl (Fn Global -> String)))
    (define (old-name global)
      (cond ((and (same-library? (::library global) forms-library) (= (::serial global) 0))
             (::name global))
            ((= (::serial global) 0)
             (string-append (library-key (::library global)) ":" (::name global)))
            (else
             (string-append (library-key (::library global))
                            ":"
                            (::name global)
                            "%m."
                            (i64->string (::serial global))))))

    (: old-class-name (impl (Fn ClassRef -> String)))
    (define (old-class-name class)
      (match class
        ((ClassGlobal global) (old-name global))
        ((FieldClass label) (string-append "::" label))))

    (: old-variable (impl (Fn TypeVariable -> String)))
    (define (old-variable variable)
      (match variable
        ((Written name) name)
        ((Associated number label) (string-append "$associated." (i64->string number) "." label))
        ((CallableArgument number) (string-append "$callable-argument." (i64->string number)))
        ((Own inner) (string-append "$method." (old-variable inner)))))

    ;; ---- Types ----

    ;; A function is the old bare arrow, and any other callable that arrow
    ;; under its kind's name.
    (: old-type (impl (Fn Type -> old:Type)))
    (define (old-type type)
      (match type
        ((Con global arguments) (old:TCon (old-name global) (map old-type arguments)))
        ((Callable (Dyn) (FnContract) arrow) (old-arrow arrow))
        ((Callable (Dyn) contract arrow)
         (old:TCon (contract-name contract) (list (old-arrow arrow))))
        ((Callable (Impl) contract arrow)
         (old:TCon (string-append "$impl." (contract-name contract)) (list (old-arrow arrow))))
        ((Code arrow) (old:TCon "fn" (list (old-arrow arrow))))
        ((Row effects) (old-row effects))
        ((Var variable) (old:TRigid (old-variable variable)))))

    (: contract-name (impl (Fn Contract -> String)))
    (define (contract-name contract)
      (match contract
        ((FnContract) "Fn")
        ((FnMutContract) "FnMut")
        ((FnOnceContract) "FnOnce")))

    (: old-arrow (impl (Fn Arrow -> old:Type)))
    (define (old-arrow arrow)
      (old:TFun (map old-type (::parameters arrow))
                (old-type (::result arrow))
                (old-row (::effects arrow))))

    (: old-row (impl (Fn Effects -> old:Type)))
    (define (old-row effects)
      (old:TRow (old:label-union (Nil) (map old-name (::labels effects)))
                (match (::tail effects)
                  ((Some tail) (Some (old-type tail)))
                  ((None) (None)))))

    (: old-constraint (impl (Fn Requirement -> old:Constraint)))
    (define (old-constraint requirement)
      (match requirement
        ((ClassRequirement class types)
         (old:Constraint (old-class-name class) (map old-type types)))
        ((CallableRequirement contract receiver arrow)
         (old:Constraint (string-append "snail.core.base:" (contract-name contract))
                         (list (old-type receiver) (old-arrow arrow))))))

    (: old-scheme (impl (Fn Scheme -> old:Scheme)))
    (define (old-scheme scheme)
      (old:Scheme (map old-variable (::variables scheme))
                  (map old-constraint (::requirements scheme))
                  (map old-variable (::copied scheme))
                  (old-type (::type scheme))))

    ;; ---- Entities ----

    (: old-data (impl (Fn Data -> old:DataType)))
    (define (old-data data)
      (old:DataType (old-name (::global data))
                    (::parameters data)
                    (map (lambda (case)
                           (old:Case (old-name (::global case))
                                     (old-name (::global data))
                                     (::tag case)
                                     (map (lambda (field)
                                            (old:Field (::label field)
                                                       (old-type (::type field))
                                                       (::mutable? field)))
                                          (::fields case))))
                         (::cases data))
                    (match (::kind data)
                      ((EnumData) #t)
                      ((StructData) #f))
                    (or (::move? data) (::drop? data))))

    (: old-class (impl (Fn Class -> old:Class)))
    (define (old-class class)
      (old:Class (old-name (::global class))
                 (append (map parameter-name (::parameters class)) (output-names class))
                 (concatenate (map (lambda (parameter)
                                     (match parameter
                                       ((RowParameter name) (list name))
                                       ((TypeParameter _) (Nil))))
                                   (::parameters class)))
                 (output-names class)
                 (map (lambda (method) (old-name (::global method))) (::methods class))))

    (: parameter-name (impl (Fn ClassParameter -> String)))
    (define (parameter-name parameter)
      (match parameter
        ((TypeParameter name) name)
        ((RowParameter name) name)))

    (: output-names (impl (Fn Class -> (List String))))
    (define (output-names class)
      (map (lambda (output) (::name (::label output))) (::outputs class)))

    (: old-effect (impl (Fn Effect -> old:Effect)))
    (define (old-effect effect)
      (old:Effect (old-name (::global effect))
                  (map (lambda (operation) (old-name (::global operation))) (::operations effect))
                  (map (lambda (operation) (old-name (::global operation)))
                       (filter ::control? (::operations effect)))
                  (map (lambda (default)
                         (Pair (old-name (::operation default))
                               (old-name (::implementation default))))
                       (::defaults effect))
                  (::around-main? effect)))

    ;; An instance, in the named set `set` if it is in one.
    (: old-instance (impl (Fn Instance (Option Global) -> old:Instance)))
    (define (old-instance instance set)
      (old:Instance (old-name (::global instance))
                    (old-class-name (::class instance))
                    (map old-variable (::variables instance))
                    (map old-type (append (::types instance) (::outputs instance)))
                    (map old-constraint (::requirements instance))
                    (map old-variable (::copied instance))
                    (map (lambda (method)
                           (Pair (member-name (::member method))
                                 (old-name (::implementation method))))
                         (::methods instance))
                    (match set
                      ((Some global) (Some (old-name global)))
                      ((None) (None)))))

    (: member-name (impl (Fn Member -> String)))
    (define (member-name member)
      (match member
        ((ClassMethod global) (old-name global))
        ((FieldReader label) (string-append "::" label))))

    ;; ---- Texts ----

    ;; A name with each `%m.` mark's number dropped.
    (: name-text (impl (Fn String -> String)))
    (define (name-text name)
      (list->string (unmarked (string->list name))))

    (: unmarked (impl (Fn (List Char) -> (List Char))))
    (define (unmarked chars)
      (match chars
        ((Nil) (Nil))
        ((Cons #\% (Cons #\m (Cons #\. rest))) (Cons #\% (unmarked (drop-digits rest))))
        ((Cons char rest) (Cons char (unmarked rest)))))

    (: drop-digits (impl (Fn (List Char) -> (List Char))))
    (define (drop-digits chars)
      (match chars
        ((Cons char rest) (if (char-numeric? char) (drop-digits rest) chars))
        ((Nil) (Nil))))

    (: form (impl (Fn String (List String) -> String)))
    (define (form head items)
      (string-append "(" (string-join (Cons head items) " ") ")"))

    (: names-text (impl (Fn (List String) -> String)))
    (define (names-text names)
      (form "" (map name-text names)))

    ;; A type as both compilers' trees are compared by it, (snail compiler
    ;; adapter expansion)'s normal form among them.
    (: normal-type-text (impl (Fn old:Type -> String)))
    (define (normal-type-text type)
      (type-text type))

    (: type-text (impl (Fn old:Type -> String)))
    (define (type-text type)
      (match type
        ((old:TCon name arguments) (form (name-text name) (map type-text arguments)))
        ((old:TFun parameters result row)
         (form "->" (list (form "" (map type-text parameters)) (type-text result) (type-text row))))
        ((old:TRow labels tail)
         (form "!"
               (append (list-sort string<? (map name-text labels))
                       (match tail
                         ((Some rest) (list (type-text rest)))
                         ((None) (Nil))))))
        ((old:TVar number) (string-append "?" (i64->string number)))
        ((old:TRigid name) (string-append "'" name))))

    (: constraint-text (impl (Fn old:Constraint -> String)))
    (define (constraint-text constraint)
      (form (name-text (::class constraint)) (map type-text (::types constraint))))

    (: scheme-text (impl (Fn old:Scheme -> String)))
    (define (scheme-text scheme)
      (form "scheme"
            (list (form "" (::vars scheme))
                  (form "" (map constraint-text (::constraints scheme)))
                  (form "" (::copy scheme))
                  (type-text (::type scheme)))))

    (: data-text (impl (Fn old:DataType -> String)))
    (define (data-text data)
      (form (name-text (::name data))
            (list (form "" (::params data))
                  (form "" (map case-text (::cases data)))
                  (if (::enum? data) "enum" "struct")
                  (if (::owned? data) "owned" "copied"))))

    (: case-text (impl (Fn old:Case -> String)))
    (define (case-text case)
      (form (name-text (::name case))
            (Cons (name-text (::type case))
                  (Cons (i64->string (::tag case))
                        (map (lambda (field)
                               (form (::name field)
                                     (list (type-text (::type field))
                                           (if (::mutable? field) "mut" "fixed"))))
                             (::fields case))))))

    (: class-text (impl (Fn old:Class -> String)))
    (define (class-text class)
      (form (name-text (::name class))
            (list (form "" (::params class))
                  (form "" (::rows class))
                  (form "" (::outputs class))
                  (names-text (::methods class)))))

    ;; Each default by its operation, since its implementation is named
    ;; afresh.
    (: effect-text (impl (Fn old:Effect -> String)))
    (define (effect-text effect)
      (form (name-text (::name effect))
            (list (names-text (::operations effect))
                  (names-text (::control effect))
                  (names-text (map ::first (::defaults effect)))
                  (if (::around-main effect) "around-main" "-"))))

    ;; An instance without its name and its implementations' names, which
    ;; are fresh; `schemes` gives each implementation's scheme in order.
    (: instance-text (impl (Fn old:Instance (List String) -> String)))
    (define (instance-text instance schemes)
      (form (name-text (::class instance))
            (list (form "" (map type-text (::types instance)))
                  (form "" (::vars instance))
                  (form "" (map constraint-text (::requires instance)))
                  (form "" (::copy instance))
                  (match (::set instance)
                    ((Some set) (name-text set))
                    ((None) "-"))
                  (names-text (map ::first (::methods instance)))
                  (form "" schemes))))

    (: value-text (impl (Fn old:Value -> String)))
    (define (value-text value)
      (match value
        ((old:Defined scheme signature function?)
         (form "defined"
               (list (match scheme
                       ((Some found) (scheme-text found))
                       ((None) "-"))
                     (match signature
                       ((Some _) "signed")
                       ((None) "-"))
                     (if function? "function" "-"))))
        ((old:Constructor case scheme)
         (form "constructor" (list (name-text (::name case)) (scheme-text scheme))))
        ((old:Accessor case index scheme) (field-text "accessor" case index scheme))
        ((old:Replacer case index scheme) (field-text "replacer" case index scheme))
        ((old:Setter case index scheme) (field-text "setter" case index scheme))
        ((old:Swapper case index scheme) (field-text "swapper" case index scheme))
        ((old:Method class scheme) (form "method" (list (name-text class) (scheme-text scheme))))
        ((old:Operation effect scheme)
         (form "operation" (list (name-text effect) (scheme-text scheme))))
        ((old:Primitive scheme) (form "primitive" (list (scheme-text scheme))))
        ((old:Foreign import scheme)
         (form "foreign" (list (::module import) (::symbol import) (scheme-text scheme))))))

    (: field-text (impl (Fn String old:Case I64 old:Scheme -> String)))
    (define (field-text kind case index scheme)
      (form kind (list (name-text (::name case)) (i64->string index) (scheme-text scheme))))

    ;; ---- Libraries ----

    ;; The differences between what `declare` made of the library `file`
    ;; holds and what the old program holds of it; `files` are every
    ;; library compiled, whose classes an instance may implement.
    (: declaration-differences
       (impl (Fn (List CompiledFile) CompiledFile old:Program -> (List String))))
    (define (declaration-differences files file program)
      (let* ((key (library-key (::library file)))
             (tops (library-tops (::dispatched file))))
        (concatenate
         (list (listed-difference key
                                  "data types"
                                  (map (lambda (data) (data-text (old-data data))) (tops-data tops))
                                  (map data-text
                                       (filter (lambda (data) (in-library? key (::name data)))
                                               (table-values (::types program)))))
               (listed-difference key
                                  "classes"
                                  (map (lambda (class) (class-text (old-class class)))
                                       (tops-classes tops))
                                  (map class-text
                                       (filter (lambda (class) (in-library? key (::name class)))
                                               (table-values (::classes program)))))
               (listed-difference key
                                  "effects"
                                  (map (lambda (effect) (effect-text (old-effect effect)))
                                       (tops-effects tops))
                                  (map effect-text
                                       (filter (lambda (effect) (in-library? key (::name effect)))
                                               (table-values (::effects program)))))
               (listed-difference key "values" (new-values tops) (old-values program key))
               (instance-differences files key (::listing file) program)))))

    (: library-tops (impl (Fn Dispatched -> (List Top))))
    (define (library-tops library)
      (match library
        ((Defined _ tops _ _) tops)
        ((Program tops _ _) tops)))

    ;; Whether an old name is of the library `key`: it starts with the
    ;; key and a colon.
    (: in-library? (impl (Fn String String -> Bool)))
    (define (in-library? key name)
      (let ((prefix (string-append key ":")))
        (and (> (string-length name) (string-length prefix))
             (string=? (substring name 0 (string-length prefix)) prefix))))

    ;; Two lists of texts, each sorted, the same.
    (: listed-difference (impl (Fn String String (List String) (List String) -> (List String))))
    (define (listed-difference key what new old)
      (let ((new-sorted (list-sort string<? new))
            (old-sorted (list-sort string<? old)))
        (if (and (= (length new-sorted) (length old-sorted))
                 (every? (lambda (pair) (string=? (::first pair) (::second pair)))
                         (zip new-sorted old-sorted)))
            (Nil)
            (list (string-append key
                                 ": the "
                                 what
                                 " differ: new "
                                 (string-join (texts-apart new-sorted old-sorted) " ")
                                 "; old " (string-join (texts-apart old-sorted new-sorted) " "))))))

    ;; The texts of `texts` that `others` lacks.
    (: texts-apart (impl (Fn (List String) (List String) -> (List String))))
    (define (texts-apart texts others)
      (filter (lambda (text) (not (member? text others))) texts))

    ;; ---- Declarations ----

    ;; Each top, those of an instance scope in place.
    (: flat-tops (impl (Fn (List Top) -> (List Top))))
    (define (flat-tops tops)
      (concatenate (map (lambda (top)
                          (match top
                            ((InstanceScope _ inner _) (flat-tops inner))
                            (_ (list top))))
                        tops)))

    (: tops-data (impl (Fn (List Top) -> (List Data))))
    (define (tops-data tops)
      (concatenate (map (lambda (top)
                          (match top
                            ((TopData data) (list data))
                            (_ (Nil))))
                        (flat-tops tops))))

    (: tops-classes (impl (Fn (List Top) -> (List Class))))
    (define (tops-classes tops)
      (concatenate (map (lambda (top)
                          (match top
                            ((TopClass class) (list class))
                            (_ (Nil))))
                        (flat-tops tops))))

    (: tops-effects (impl (Fn (List Top) -> (List Effect))))
    (define (tops-effects tops)
      (concatenate (map (lambda (top)
                          (match top
                            ((TopEffect effect) (list effect))
                            (_ (Nil))))
                        (flat-tops tops))))

    ;; ---- Values ----

    ;; Each value the library declares, as the old program holds it, by its
    ;; name. A primitive's library is never compared.
    (: new-values (impl (Fn (List Top) -> (List String))))
    (define (new-values tops)
      (map (lambda (entry) (form (name-text (::first entry)) (list (value-text (::second entry)))))
           (concatenate (map top-values (flat-tops tops)))))

    (: top-values (impl (Fn Top -> (List (Pair String old:Value)))))
    (define (top-values top)
      (match top
        ((Define global value signature _ _)
         (list (Pair (old-name global)
                     (old:Defined (match signature
                                    ((Some signed) (Some (old-scheme (::scheme signed))))
                                    ((None) (None)))
                                  (match signature
                                    ((Some signed) (Some (old-loc (::loc signed))))
                                    ((None) (None)))
                                  (function-value? value)))))
        ((TopData data) (data-values data))
        ((TopClass class)
         (map (lambda (method)
                (Pair (old-name (::global method))
                      (old:Method (old-name (::global class))
                                  (old-scheme (method-scheme class method)))))
              (::methods class)))
        ((TopEffect effect)
         (map (lambda (operation)
                (Pair (old-name (::global operation))
                      (old:Operation (old-name (::global effect))
                                     (old-scheme (operation-scheme (::global effect) operation)))))
              (::operations effect)))
        ((Extern global module symbol type _ _)
         (list (Pair (old-name global)
                     (old:Foreign (old:Import module symbol)
                                  (old-scheme (Scheme (Nil) (Nil) (Nil) type))))))
        (_ (Nil))))

    (: old-loc (impl (Fn Loc -> old:Loc)))
    (define (old-loc loc)
      (old:Loc (::file loc) (::line loc) (::column loc)))

    (: function-value? (impl (Fn Expr -> Bool)))
    (define (function-value? value)
      (match value
        ((Lambda _ _ _) #t)
        ((ClosedLambda _ _ _) #t)
        (_ #f)))

    ;; Each case's constructor, then each of its fields' functions.
    (: data-values (impl (Fn Data -> (List (Pair String old:Value)))))
    (define (data-values data)
      (let ((converted (old-data data)))
        (concatenate
         (map (lambda (pair)
                (let ((case (::first pair))
                      (old-case (::second pair)))
                  (Cons (Pair (old-name (::global case))
                              (old:Constructor old-case
                                               (old-scheme (constructor-scheme data case))))
                        (concatenate
                         (map (lambda (indexed)
                                (field-values data
                                              case
                                              old-case
                                              (::first indexed)
                                              (::second indexed)))
                              (zip (iota (length (::fields case))) (::fields case)))))))
              (zip (::cases data) (::cases converted))))))

    (: field-values
       (impl (Fn Data DataCase old:Case I64 DataField -> (List (Pair String old:Value)))))
    (define (field-values data case old-case index field)
      (let ((accessor (string-append (old-name (::global case)) "-" (::label field))))
        (map (lambda (role)
               (let ((scheme (old-scheme (::second role))))
                 (match (::first role)
                   ((Accessor) (Pair accessor (old:Accessor old-case index scheme)))
                   ((Replacer)
                    (Pair (string-append accessor "-set") (old:Replacer old-case index scheme)))
                   ((Setter)
                    (Pair (string-append accessor "-set!") (old:Setter old-case index scheme)))
                   ((Swapper)
                    (Pair (string-append accessor "-replace!")
                          (old:Swapper old-case index scheme))))))
             (field-schemes data case field))))

    ;; The old program's values of the library, but those it names
    ;; afresh: a name with a dot and a digit after its library, such as an
    ;; implementation's `show.12`, a program's body, `%body`, and a linked
    ;; file's handle, `%link path`.
    (: old-values (impl (Fn old:Program String -> (List String))))
    (define (old-values program key)
      (concatenate (map (lambda (name)
                          (if (or (not (in-library? key name)) (fresh-name? name))
                              (Nil)
                              (match (table-ref (::values program) name)
                                ((Some value)
                                 (list (form (name-text name) (list (value-text value)))))
                                ((None) (Nil)))))
                        (table-keys (::values program)))))

    ;; A mark's number is no fresh name's.
    (: fresh-name? (impl (Fn String -> Bool)))
    (define (fresh-name? name)
      (let ((after (list->string (drop-through-colon (string->list (name-text name))))))
        (or (dotted-digit? (string->list after))
            (string=? after "%body")
            (string-prefix? "%link " after))))

    (: drop-through-colon (impl (Fn (List Char) -> (List Char))))
    (define (drop-through-colon chars)
      (match chars
        ((Nil) (Nil))
        ((Cons #\: rest) rest)
        ((Cons _ rest) (drop-through-colon rest))))

    (: dotted-digit? (impl (Fn (List Char) -> Bool)))
    (define (dotted-digit? chars)
      (match chars
        ((Cons #\. (Cons digit rest)) (or (char-numeric? digit) (dotted-digit? (Cons digit rest))))
        ((Cons _ rest) (dotted-digit? rest))
        ((Nil) #f)))

    ;; ---- Instances ----

    ;; Class by class, the library's listing in order, beside the old
    ;; program's instances of the class the library declares.
    (: instance-differences
       (impl (Fn (List CompiledFile) String (List Listed) old:Program -> (List String))))
    (define (instance-differences files key listing program)
      (let* ((listed (map (lambda (entry) (Pair (listed-class-name entry) entry)) listing))
             (classes (delete-duplicates string=? (map ::first listed))))
        (concatenate
         (map (lambda (class)
                (class-difference files
                                  key
                                  program
                                  class
                                  (map ::second
                                       (filter (lambda (entry) (string=? (::first entry) class))
                                               listed))
                                  (library-class-instances program key class)))
              (append classes (old-only-classes program key classes))))))

    (: library-class-instances (impl (Fn old:Program String String -> (List old:Instance))))
    (define (library-class-instances program key class)
      (filter (lambda (instance) (in-library? key (::name instance)))
              (old:class-instances program class)))

    (: string-prefix? (impl (Fn String String -> Bool)))
    (define (string-prefix? prefix text)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (: class-difference
       (impl (Fn (List CompiledFile)
                 String
                 old:Program
                 String
                 (List Listed)
                 (List old:Instance)
                 ->
                 (List String))))
    (define (class-difference files key program class listed old)
      (let ((new-texts (map (lambda (entry) (listed-text files entry)) listed))
            (old-texts (if (= (length listed) (length old))
                           (map (lambda (pair)
                                  (old-instance-text program (::first pair) (::second pair)))
                                (zip listed old))
                           (map (lambda (instance) (instance-text instance (Nil))) old))))
        (if (and (= (length new-texts) (length old-texts))
                 (every? (lambda (pair) (string=? (::first pair) (::second pair)))
                         (zip new-texts old-texts)))
            (Nil)
            (list (string-append key ": the instances of " (name-text class) " differ: new "
                                 (string-join new-texts ", ")
                                 "; old "
                                 (string-join old-texts ", "))))))

    ;; The classes the old program has instances of that the library
    ;; declares, but which the listing has none of.
    (: old-only-classes (impl (Fn old:Program String (List String) -> (List String))))
    (define (old-only-classes program key classes)
      (list-sort string<?
                 (filter (lambda (class)
                           (and (not (member? class classes))
                                (not (null? (library-class-instances program key class)))))
                         (table-keys (::instances program)))))

    (: listed-class-name (impl (Fn Listed -> String)))
    (define (listed-class-name entry)
      (old-class-name (listed-class entry)))

    (: listed-text (impl (Fn (List CompiledFile) Listed -> String)))
    (define (listed-text files entry)
      (match entry
        ((ListedInstance instance set)
         (instance-text (old-instance instance set) (implementation-texts files instance)))
        ((FieldInstance data field)
         (let ((self (Con (::global data)
                          (map (lambda (name) (Var (Written name))) (::parameters data))))
               (class (string-append "::" (::label field))))
           (instance-text (old:Instance ""
                                        class
                                        (::parameters data)
                                        (map old-type (list self (::type field)))
                                        (Nil)
                                        (Nil)
                                        (list (Pair class ""))
                                        (None))
                          (list "accessor"))))))

    ;; Each implementation's scheme, the member's at the instance's head,
    ;; which `implementation-scheme` reads off the instance as declared.
    (: implementation-texts (impl (Fn (List CompiledFile) Instance -> (List String))))
    (define (implementation-texts files instance)
      (map (lambda (method)
             (match (member-class files (::class instance) (::member method))
               ((Some found)
                (scheme-text (old-scheme (implementation-scheme (::first found)
                                                                (::second found)
                                                                (as-declared instance)))))
               ((None) "no class")))
           (::methods instance)))

    (: as-declared (impl (Fn Instance -> declared-Instance)))
    (define (as-declared instance)
      (declared-Instance (::global instance)
                         (::class instance)
                         (::variables instance)
                         (::types instance)
                         (::outputs instance)
                         (::requirements instance)
                         (::copied instance)
                         (Methods (::methods instance))
                         (::loc instance)))

    ;; The class an instance implements, and the method a member names: a
    ;; declared class's, or the one method of a field class, `(::label R
    ;; T)`, which reads a T from an R.
    (: member-class (impl (Fn (List CompiledFile) ClassRef Member -> (Option (Pair Class Method)))))
    (define (member-class files class member)
      (match (Pair class member)
        ((Pair (ClassGlobal global) (ClassMethod method))
         (match (declared-class files global)
           ((Some declared)
            (match (find (lambda (candidate) (same-global? (::global candidate) method))
                         (::methods declared))
              ((Some found) (Some (Pair declared found)))
              ((None) (None))))
           ((None) (None))))
        ((Pair (FieldClass label) (FieldReader _))
         (let ((reader (Global (Nil) label 0)))
           (Some (Pair (Class reader field-class-parameters (Nil) (Nil) (Nil) (Loc "" 0 0))
                       (Method reader field-reader-scheme (Nil) (Loc "" 0 0))))))
        (_ (None))))

    (: declared-class (impl (Fn (List CompiledFile) Global -> (Option Class))))
    (define (declared-class files global)
      (match (find (lambda (file) (same-library? (::library file) (::library global))) files)
        ((Some file)
         (match (table-ref (::classes (::declarations file)) (::name global))
           ((Some classes) (find (lambda (class) (same-global? (::global class) global)) classes))
           ((None) (None))))
        ((None) (None))))

    ;; The old instance's text beside the one the listing has in its
    ;; place: each implementation's scheme as the old program holds it; an
    ;; implied field instance's implementation is its field's accessor,
    ;; compared with the library's values.
    (: old-instance-text (impl (Fn old:Program Listed old:Instance -> String)))
    (define (old-instance-text program listed instance)
      (match listed
        ((FieldInstance _ _)
         (instance-text instance (map (lambda (method) "accessor") (::methods instance))))
        ((ListedInstance _ _)
         (instance-text instance
                        (map (lambda (method)
                               (match (table-ref (::values program) (::second method))
                                 ((Some (old:Defined (Some scheme) _ _)) (scheme-text scheme))
                                 (_ "no scheme")))
                             (::methods instance))))))

    ))
