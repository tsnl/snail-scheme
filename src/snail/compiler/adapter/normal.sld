;; The normal forms the comparisons of whole programs write trees in, so
;; what the new passes wrote and what the old expander wrote compare as
;; texts, and so do two old programs: a Declared expression's text and an
;; old expression's. In both each local is numbered in the order it is
;; bound, each macro-written global is its name marked as written by an
;; expansion, without the expansion's number, each field function is its
;; name, a linked file's handle is the old expander's name for it,
;; `library:%link path`, and a `case-id` is the TypeId `declare` gives its
;; case, beside the number the old expander writes. A conversion keeps its
;; type, since the type is what it does; a dispatched method's call of an
;; instance's implementation names it as the old expander does, by the
;; implementation in the old instance in the same place. Both leave out
;; other types and whether a function may capture.
;;
;; An old expression is written in the old expansion's names through a
;; renaming, which gives each name the adapted program makes afresh the
;; old expansion's. An old item is written with what the normal form
;; leaves out but two old programs both hold: each node's place, whether
;; each function may capture and each annotation's type, and, once the
;; old checker has checked it, each node's type, each variable's
;; instantiation and each pattern's type.
(define-library (snail compiler adapter normal)
  (export
   Naming
   Rendered
   Context
   global-text
   form-text
   new-text
   old-text
   renamed
   short-name
   string-index-of
   item-text
   checked-scheme-text
   old-loc-text)
  (import
   (snail core base)
   (snail core table)
   (only (snail compiler literals datum) Datum)
   (prefix (snail compiler literals datum) datum-)
   (snail compiler names libraries)
   (only (snail compiler names globals)
         Local
         Global
         TopValue
         TopGlobal
         FieldFunction
         FieldRole
         Accessor
         Replacer
         Setter
         Swapper)
   (only (snail compiler literals constant)
         Constant
         Integer
         Float
         Text
         Character
         ByteVector
         Boolean
         UnitValue)
   (only (snail compiler declare language)
         Expr
         Literal
         LocalRef
         TopRef
         Path
         PathApply
         Lambda
         ClosedLambda
         Call
         If
         Seq
         Let
         Match
         Handle
         WithInstances
         Ann
         Convert
         TryConvert
         TypeTest
         CaseId
         Clause
         Pattern
         Wild
         Bind
         Equals
         Destructure
         Type)
   (only (snail compiler integrate sha256) sha256 bytes->hex)
   (only (snail compiler adapter declaration) old-type normal-type-text name-text)
   (prefix (only (snail compiler adapter declaration) scheme-text) normal-)
   (prefix (only (snail shell compiler read)
                 Loc
                 Datum
                 DInt
                 DFloat
                 DString
                 DChar
                 DBytes
                 DBool
                 DUnit)
           old:)
   (prefix (only (snail shell compiler core)
                 Type
                 TCon
                 TFun
                 TRow
                 Scheme
                 Evidence
                 EvInstance
                 EvParam
                 EvDerived
                 EvHole
                 Plan
                 Trivial
                 Implemented
                 Glue
                 Refused
                 Expr
                 Term
                 Lit
                 Var
                 Lambda
                 App
                 If
                 Let
                 Seq
                 Match
                 ScopedInstances
                 Ann
                 Handle
                 Convert
                 TryConvert
                 TypeTest
                 Clause
                 Pattern
                 PWild
                 PVar
                 PLit
                 PCon
                 Item
                 Define
                 Do
                 Expose)
           old:))
  (begin

    ;; ---- Names ----

    (: string-index-of (impl (Fn String String -> (Option I64))))
    (define (string-index-of text part)
      (let loop ((index 0))
        (cond ((> (+ index (string-length part)) (string-length text)) (None))
              ((string=? (substring text index (+ index (string-length part))) part) (Some index))
              (else (loop (+ index 1))))))

    (: global-text (impl (Fn Global -> String)))
    (define (global-text global)
      (string-append (library-key (::library global))
                     ":"
                     (::name global)
                     (if (= (::serial global) 0) "" "%")))

    ;; What the normal form of a new expression needs besides the
    ;; expression: the old expander's name for each linked file's handle,
    ;; and, for a dispatched method's, for each instance's implementations.
    (struct Context
      ((handles (List (Pair Global String)))
       (implementations (List (Pair Global String)))))

    ;; A value's normal name: a linked file's handle, and an instance's
    ;; implementation where the context names them, are the old
    ;; expander's names for them.
    (: top-value-text (impl (Fn Context TopValue -> String)))
    (define (top-value-text names value)
      (match value
        ((TopGlobal global)
         (match (find (lambda (entry) (same-global? (::first entry) global))
                      (append (::handles names) (::implementations names)))
           ((Some entry) (name-text (::second entry)))
           ((None) (global-text global))))
        ((FieldFunction case label role)
         (string-append (global-text case) "-" label (role-suffix role)))))

    (: same-global? (impl (Fn Global Global -> Bool)))
    (define (same-global? global other)
      (and (string=? (library-key (::library global)) (library-key (::library other)))
           (string=? (::name global) (::name other))
           (= (::serial global) (::serial other))))

    (: role-suffix (impl (Fn FieldRole -> String)))
    (define (role-suffix role)
      (match role
        ((Accessor) "")
        ((Replacer) "-set")
        ((Setter) "-set!")
        ((Swapper) "-replace!")))

    ;; ---- New expressions ----

    ;; The locals named so far, each with its number in the normal form,
    ;; and the next number.
    (struct Naming
      ((locals (List (Pair String I64)))
       (next I64)))

    (struct Rendered
      ((text String)
       (naming Naming)))

    (: bound (impl (Fn Naming String -> Rendered)))
    (define (bound naming key)
      (Rendered (string-append "L" (i64->string (::next naming)))
                (Naming (Cons (Pair key (::next naming)) (::locals naming)) (+ (::next naming) 1))))

    (: named (impl (Fn Naming String -> String)))
    (define (named naming key)
      (match (find (lambda (entry) (string=? (::first entry) key)) (::locals naming))
        ((Some entry) (string-append "L" (i64->string (::second entry))))
        ((None) (string-append "free:" key))))

    (: local-key (impl (Fn Local -> String)))
    (define (local-key local)
      (i64->string (::number local)))

    (: form-text (impl (Fn String (List String) -> String)))
    (define (form-text head items)
      (string-append "(" (string-join (Cons head items) " ") ")"))

    ;; Each of `texts` in turn, threading the naming.
    (: new-texts
       (impl (Fn Context (List Expr) Naming -> (Pair (List String) Naming))))
    (define (new-texts names exprs naming)
      (let loop ((exprs exprs)
                 (naming naming)
                 (texts (Nil)))
        (match exprs
          ((Nil) (Pair (reverse texts) naming))
          ((Cons expr rest)
           (let ((rendered (new-text names expr naming)))
             (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))

    (: new-binders (impl (Fn (List Local) Naming -> (Pair (List String) Naming))))
    (define (new-binders locals naming)
      (let loop ((locals locals)
                 (naming naming)
                 (texts (Nil)))
        (match locals
          ((Nil) (Pair (reverse texts) naming))
          ((Cons local rest)
           (let ((rendered (bound naming (local-key local))))
             (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))

    (: new-text (impl (Fn Context Expr Naming -> Rendered)))
    (define (new-text names expr naming)
      (match expr
        ((Literal constant _) (Rendered (constant-text constant) naming))
        ((LocalRef local _) (Rendered (named naming (local-key local)) naming))
        ((TopRef value _) (Rendered (top-value-text names value) naming))
        ((Path (Cons label (Nil)) _) (Rendered (string-append "::" label) naming))
        ((Path labels _)
         (let ((parameter (bound naming "%path")))
           (Rendered (form-text "lambda"
                                (list (form-text (::text parameter) (Nil))
                                      (path-text labels (::text parameter))))
                     (::naming parameter))))
        ((PathApply labels record _)
         (let ((rendered (new-text names record naming)))
           (Rendered (path-text labels (::text rendered)) (::naming rendered))))
        ((Lambda parameters body _) (lambda-text names parameters body naming))
        ((ClosedLambda parameters body _) (lambda-text names parameters body naming))
        ((Call callee arguments _) (sequence-text names "call" (Cons callee arguments) naming))
        ((If test consequent alternative _)
         (sequence-text names "if" (list test consequent alternative) naming))
        ((Seq first rest _) (sequence-text names "seq" (list first rest) naming))
        ((Let local signature value body _)
         (let* ((binder (bound naming (local-key local)))
                (value-text (new-text names value (::naming binder)))
                (body-text (new-text names body (::naming value-text))))
           (Rendered (form-text "let"
                                (list (::text binder)
                                      (match signature
                                        ((Some _) (form-text "ann" (list (::text value-text))))
                                        ((None) (::text value-text)))
                                      (::text body-text)))
                     (::naming body-text))))
        ((Match scrutinee clauses _)
         (let* ((value (new-text names scrutinee naming))
                (rendered (clauses-text names clauses (::naming value))))
           (Rendered (form-text "match" (Cons (::text value) (::first rendered)))
                     (::second rendered))))
        ((Handle effect implementations body _)
         (let* ((values (new-texts names (map ::value implementations) naming))
                (body-text (new-text names body (::second values))))
           (Rendered (form-text "handle"
                                (Cons (global-text effect)
                                      (append (map (lambda (pair)
                                                     (form-text (::first pair)
                                                                (list (::second pair))))
                                                   (zip (map (lambda (implementation)
                                                               (::name
                                                                (::operation implementation)))
                                                             implementations)
                                                        (::first values)))
                                              (list (::text body-text)))))
                     (::naming body-text))))
        ((WithInstances sets body _)
         (let ((rendered (new-text names body naming)))
           (Rendered (form-text "with-instances"
                                (list (form-text "" (map global-text sets)) (::text rendered)))
                     (::naming rendered))))
        ((Ann value _ _) (wrapped-text names "ann" value naming))
        ((Convert value type _) (converted-text names "convert" value type naming))
        ((TryConvert value type _) (converted-text names "try-convert" value type naming))
        ((TypeTest value type _) (converted-text names "type-test" value type naming))
        ((CaseId _ id _)
         (Rendered (form-text "ann" (list (string-append "i:" (i64->string id)))) naming))))

    (: path-text (impl (Fn (List String) String -> String)))
    (define (path-text labels record)
      (fold-left (lambda (text label) (form-text "call" (list (string-append "::" label) text)))
                 record
                 labels))

    (: lambda-text (impl (Fn Context (List Local) Expr Naming -> Rendered)))
    (define (lambda-text names parameters body naming)
      (let* ((binders (new-binders parameters naming))
             (rendered (new-text names body (::second binders))))
        (Rendered (form-text "lambda" (list (form-text "" (::first binders)) (::text rendered)))
                  (::naming rendered))))

    (: sequence-text
       (impl (Fn Context String (List Expr) Naming -> Rendered)))
    (define (sequence-text names head exprs naming)
      (let ((rendered (new-texts names exprs naming)))
        (Rendered (form-text head (::first rendered)) (::second rendered))))

    (: wrapped-text (impl (Fn Context String Expr Naming -> Rendered)))
    (define (wrapped-text names head value naming)
      (let ((rendered (new-text names value naming)))
        (Rendered (form-text head (list (::text rendered))) (::naming rendered))))

    (: converted-text (impl (Fn Context String Expr Type Naming -> Rendered)))
    (define (converted-text names head value type naming)
      (let ((rendered (new-text names value naming)))
        (Rendered (form-text head (list (::text rendered) (normal-type-text (old-type type))))
                  (::naming rendered))))

    (: clauses-text
       (impl (Fn Context (List Clause) Naming -> (Pair (List String) Naming))))
    (define (clauses-text names clauses naming)
      (let loop ((clauses clauses)
                 (naming naming)
                 (texts (Nil)))
        (match clauses
          ((Nil) (Pair (reverse texts) naming))
          ((Cons clause rest)
           (let* ((pattern (pattern-text names (::pattern clause) naming))
                  (body (new-text names (::body clause) (::naming pattern))))
             (loop rest
                   (::naming body)
                   (Cons (form-text (::text pattern) (list (::text body))) texts)))))))

    (: pattern-text (impl (Fn Context Pattern Naming -> Rendered)))
    (define (pattern-text names pattern naming)
      (match pattern
        ((Wild _) (Rendered "_" naming))
        ((Bind local _) (bound naming (local-key local)))
        ((Equals datum _) (Rendered (form-text "=" (list (datum-text datum))) naming))
        ((Destructure constructor arguments _)
         (let loop ((arguments arguments)
                    (naming naming)
                    (texts (Nil)))
           (match arguments
             ((Nil)
              (Rendered (form-text (top-value-text names constructor) (reverse texts)) naming))
             ((Cons argument rest)
              (let ((rendered (pattern-text names argument naming)))
                (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))))

    (: constant-text (impl (Fn Constant -> String)))
    (define (constant-text constant)
      (match constant
        ((Integer value) (string-append "i:" (i64->string value)))
        ((Float text) (string-append "f:" text))
        ((Text text) (string-append "s:" text))
        ((Character char) (string-append "c:" (i64->string (char->integer char))))
        ((ByteVector bytes) (string-append "b:" (bytes-text bytes)))
        ((Boolean value) (if value "#t" "#f"))
        ((UnitValue) "unit")))

    (: datum-text (impl (Fn Datum -> String)))
    (define (datum-text datum)
      (match datum
        ((datum-Integer value) (string-append "i:" (i64->string value)))
        ((datum-Float text) (string-append "f:" text))
        ((datum-Text text) (string-append "s:" text))
        ((datum-Character char) (string-append "c:" (i64->string (char->integer char))))
        ((datum-ByteVector bytes) (string-append "b:" (bytes-text bytes)))
        ((datum-Boolean value) (if value "#t" "#f"))))

    ;; A byte vector by its length and its digest, so two of one length
    ;; but other bytes differ.
    (: bytes-text (impl (Fn Bytes -> String)))
    (define (bytes-text bytes)
      (string-append (i64->string (vector-length bytes)) ":" (bytes->hex (sha256 bytes))))

    ;; ---- Old expressions ----

    ;; The normal form of an old expression. `renaming` gives, for a
    ;; global the program names afresh, the name the old expansion gives
    ;; it, so the adapted program's expressions are written in the old
    ;; expansion's names; the old expansion's own are written with none.
    (: old-texts
       (impl (Fn (Table String) (List old:Expr) Naming -> (Pair (List String) Naming))))
    (define (old-texts renaming exprs naming)
      (let loop ((exprs exprs)
                 (naming naming)
                 (texts (Nil)))
        (match exprs
          ((Nil) (Pair (reverse texts) naming))
          ((Cons expr rest)
           (let ((rendered (old-text renaming expr naming)))
             (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))

    (: old-binders (impl (Fn (List String) Naming -> (Pair (List String) Naming))))
    (define (old-binders names naming)
      (let loop ((names names)
                 (naming naming)
                 (texts (Nil)))
        (match names
          ((Nil) (Pair (reverse texts) naming))
          ((Cons name rest)
           (let ((rendered (bound naming name)))
             (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))

    ;; A name bound is a local; any other with `:` is a global, and any
    ;; other a free local. The locals of a dispatched method are named
    ;; for their implementation, with its colon.
    (: old-name-text (impl (Fn (Table String) Naming String -> String)))
    (define (old-name-text renaming naming name)
      (cond ((any? (lambda (entry) (string=? (::first entry) name)) (::locals naming))
             (named naming name))
            ((any? (lambda (char) (char=? char #\:)) (string->list name))
             (name-text (renamed renaming name)))
            (else (named naming name))))

    (: renamed (impl (Fn (Table String) String -> String)))
    (define (renamed renaming name)
      (match (table-ref renaming name)
        ((Some other) other)
        ((None) name)))

    (: old-text (impl (Fn (Table String) old:Expr Naming -> Rendered)))
    (define (old-text renaming expr naming)
      (match (::term expr)
        ((old:Lit datum) (Rendered (old-datum-text datum) naming))
        ((old:Var name _ _)
         (if (string=? (substring name 0 (min 2 (string-length name))) "::")
             (Rendered name naming)
             (Rendered (old-name-text renaming naming name) naming)))
        ((old:Lambda parameters body _)
         (let* ((binders (old-binders parameters naming))
                (rendered (old-text renaming body (::second binders))))
           (Rendered (form-text "lambda" (list (form-text "" (::first binders)) (::text rendered)))
                     (::naming rendered))))
        ((old:App callee arguments) (old-sequence renaming "call" (Cons callee arguments) naming))
        ((old:If test consequent alternative)
         (old-sequence renaming "if" (list test consequent alternative) naming))
        ((old:Seq first rest) (old-sequence renaming "seq" (list first rest) naming))
        ((old:Let name value body)
         (let* ((binder (bound naming name))
                (value-text (old-text renaming value (::naming binder)))
                (body-text (old-text renaming body (::naming value-text))))
           (Rendered (form-text "let" (list (::text binder) (::text value-text) (::text body-text)))
                     (::naming body-text))))
        ((old:Match scrutinee clauses)
         (let* ((value (old-text renaming scrutinee naming))
                (rendered (old-clauses renaming clauses (::naming value))))
           (Rendered (form-text "match" (Cons (::text value) (::first rendered)))
                     (::second rendered))))
        ((old:ScopedInstances sets body)
         (let ((rendered (old-text renaming body naming)))
           (Rendered (form-text "with-instances"
                                (list (form-text "" (map name-text sets)) (::text rendered)))
                     (::naming rendered))))
        ((old:Ann value _) (old-wrapped renaming "ann" value naming))
        ((old:Handle effect implementations body)
         (let* ((values (old-texts renaming (map ::second implementations) naming))
                (body-text (old-text renaming body (::second values))))
           (Rendered (form-text "handle"
                                (Cons (name-text effect)
                                      (append (map (lambda (pair)
                                                     (form-text (::first pair)
                                                                (list (::second pair))))
                                                   (zip (map (lambda (implementation)
                                                               (short-name
                                                                (::first implementation)))
                                                             implementations)
                                                        (::first values)))
                                              (list (::text body-text)))))
                     (::naming body-text))))
        ((old:Convert value type) (old-converted renaming "convert" value type naming))
        ((old:TryConvert value type) (old-converted renaming "try-convert" value type naming))
        ((old:TypeTest value type) (old-converted renaming "type-test" value type naming))))

    (: old-converted (impl (Fn (Table String) String old:Expr old:Type Naming -> Rendered)))
    (define (old-converted renaming head value type naming)
      (let ((rendered (old-text renaming value naming)))
        (Rendered (form-text head (list (::text rendered) (normal-type-text type)))
                  (::naming rendered))))

    ;; An operation's name within its effect: what follows the library.
    (: short-name (impl (Fn String -> String)))
    (define (short-name name)
      (match (string-index-of name ":")
        ((Some index) (name-text (substring name (+ index 1) (string-length name))))
        ((None) name)))

    (: old-sequence (impl (Fn (Table String) String (List old:Expr) Naming -> Rendered)))
    (define (old-sequence renaming head exprs naming)
      (let ((rendered (old-texts renaming exprs naming)))
        (Rendered (form-text head (::first rendered)) (::second rendered))))

    (: old-wrapped (impl (Fn (Table String) String old:Expr Naming -> Rendered)))
    (define (old-wrapped renaming head value naming)
      (let ((rendered (old-text renaming value naming)))
        (Rendered (form-text head (list (::text rendered))) (::naming rendered))))

    (: old-clauses
       (impl (Fn (Table String) (List old:Clause) Naming -> (Pair (List String) Naming))))
    (define (old-clauses renaming clauses naming)
      (let loop ((clauses clauses)
                 (naming naming)
                 (texts (Nil)))
        (match clauses
          ((Nil) (Pair (reverse texts) naming))
          ((Cons clause rest)
           (let* ((pattern (old-pattern (::pattern clause) naming))
                  (body (old-text renaming (::body clause) (::naming pattern))))
             (loop rest
                   (::naming body)
                   (Cons (form-text (::text pattern) (list (::text body))) texts)))))))

    (: old-pattern (impl (Fn old:Pattern Naming -> Rendered)))
    (define (old-pattern pattern naming)
      (match pattern
        ((old:PWild _) (Rendered "_" naming))
        ((old:PVar name _) (bound naming name))
        ((old:PLit datum _) (Rendered (form-text "=" (list (old-datum-text datum))) naming))
        ((old:PCon constructor arguments _)
         (let loop ((arguments arguments)
                    (naming naming)
                    (texts (Nil)))
           (match arguments
             ((Nil) (Rendered (form-text (name-text constructor) (reverse texts)) naming))
             ((Cons argument rest)
              (let ((rendered (old-pattern argument naming)))
                (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))))

    (: old-datum-text (impl (Fn old:Datum -> String)))
    (define (old-datum-text datum)
      (match datum
        ((old:DInt value) (string-append "i:" (i64->string value)))
        ((old:DFloat text) (string-append "f:" text))
        ((old:DString text) (string-append "s:" text))
        ((old:DChar char) (string-append "c:" (i64->string (char->integer char))))
        ((old:DBytes bytes) (string-append "b:" (bytes-text bytes)))
        ((old:DBool value) (if value "#t" "#f"))
        ((old:DUnit) "unit")))

    ;; ---- Old items ----

    ;; An item in the normal form, with what the normal form leaves out of
    ;; its expression.
    (: item-text (impl (Fn (Table String) Bool old:Item -> String)))
    (define (item-text renaming checked? item)
      (match item
        ((old:Define name value)
         (form-text "define"
                    (list (name-text (renamed renaming name))
                          (exact-text renaming checked? value))))
        ((old:Do value) (form-text "do" (list (exact-text renaming checked? value))))
        ((old:Expose name symbol dynamic? loc)
         (form-text "expose"
                    (list (name-text (renamed renaming name))
                          symbol
                          (if dynamic? "dynamic" "-")
                          (old-loc-text loc))))))

    (: exact-text (impl (Fn (Table String) Bool old:Expr -> String)))
    (define (exact-text renaming checked? value)
      (form-text (::text (old-text renaming value (Naming (Nil) 0)))
                 (expr-details renaming checked? value)))

    ;; What the normal form leaves out of an old expression, node by node
    ;; in order: its place; whether a function may capture; an
    ;; annotation's type; and, once it is `checked?`, the node's type, a
    ;; variable's instantiation, its types and its evidence, and the type
    ;; of each pattern a clause matches, in the old expansion's names.
    ;; Before checking, no node's type or instantiation is compared: the
    ;; checker reads neither, since it infers each node from its term, and
    ;; the old expander gives a few nodes of a dispatched method the types
    ;; they will have, where the adapter writes `unchecked`.
    (: expr-details (impl (Fn (Table String) Bool old:Expr -> (List String))))
    (define (expr-details renaming checked? expr)
      (Cons (string-append (old-loc-text (::loc expr))
                           (if checked?
                               (string-append ":"
                                              (checked-type-text renaming (::type expr))
                                              (checked-detail renaming (::term expr)))
                               "")
                           (term-detail renaming (::term expr)))
            (concatenate (map (lambda (child) (expr-details renaming checked? child))
                              (term-children (::term expr))))))

    ;; An annotation's type is written as a checked type, since the
    ;; checker writes annotations too, which can hold a closure's type.
    (: term-detail (impl (Fn (Table String) old:Term -> String)))
    (define (term-detail renaming term)
      (match term
        ((old:Lambda _ _ captures?) (if captures? "/lambda" "/fn"))
        ((old:Ann _ type) (string-append "/" (checked-type-text renaming type)))
        (_ "")))

    ;; What the checker writes on a variable, its instantiation, and on a
    ;; match, the types of its clauses' patterns.
    (: checked-detail (impl (Fn (Table String) old:Term -> String)))
    (define (checked-detail renaming term)
      (match term
        ((old:Var _ types evidence)
         (if (and (null? types) (null? evidence))
             ""
             (string-append "/"
                            (form-text ""
                                       (append
                                        (map (lambda (type) (checked-type-text renaming type))
                                             types)
                                        (map (lambda (one) (evidence-text renaming one))
                                             evidence))))))
        ((old:Match _ clauses)
         (string-append "/"
                        (form-text ""
                                   (concatenate
                                    (map
                                     (lambda (clause) (pattern-types renaming (::pattern clause)))
                                     clauses)))))
        (_ "")))

    (: pattern-types (impl (Fn (Table String) old:Pattern -> (List String))))
    (define (pattern-types renaming pattern)
      (match pattern
        ((old:PWild type) (list (checked-type-text renaming type)))
        ((old:PVar _ type) (list (checked-type-text renaming type)))
        ((old:PLit _ type) (list (checked-type-text renaming type)))
        ((old:PCon _ arguments type)
         (Cons (checked-type-text renaming type)
               (concatenate (map (lambda (argument) (pattern-types renaming argument))
                                 arguments))))))

    ;; A type the checker wrote. A concrete closure's type names its
    ;; construction, a definition, a local or a place, each with a number
    ;; after its last dot that the compiler that made it drew, which is
    ;; dropped, after the definition is given its name in the old
    ;; expansion's names.
    (: checked-type-text (impl (Fn (Table String) old:Type -> String)))
    (define (checked-type-text renaming type)
      (normal-type-text (closures-named renaming type)))

    (: closures-named (impl (Fn (Table String) old:Type -> old:Type)))
    (define (closures-named renaming type)
      (match type
        ((old:TCon name arguments)
         (old:TCon (closure-name renaming name)
                   (map (lambda (argument) (closures-named renaming argument)) arguments)))
        ((old:TFun parameters result row)
         (old:TFun (map (lambda (parameter) (closures-named renaming parameter)) parameters)
                   (closures-named renaming result)
                   (closures-named renaming row)))
        ((old:TRow labels (Some tail)) (old:TRow labels (Some (closures-named renaming tail))))
        (_ type)))

    (: closure-name (impl (Fn (Table String) String -> String)))
    (define (closure-name renaming name)
      (match (string-index-of name ":")
        ((Some index)
         (if (string-prefix-of? "$callable." name)
             (string-append (substring name 0 (+ index 1))
                            (without-number
                             (renamed renaming (substring name (+ index 1) (string-length name)))))
             name))
        ((None) name)))

    ;; A name with the number after its last dot dropped.
    (: without-number (impl (Fn String -> String)))
    (define (without-number name)
      (let loop ((chars (reverse (string->list name))))
        (match chars
          ((Cons #\. _) (list->string (reverse chars)))
          ((Cons char rest) (if (char-numeric? char) (loop rest) name))
          ((Nil) name))))

    (: string-prefix-of? (impl (Fn String String -> Bool)))
    (define (string-prefix-of? prefix text)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Evidence names the instance that satisfies a constraint, or the
    ;; plan of a drop or a clone.
    (: evidence-text (impl (Fn (Table String) old:Evidence -> String)))
    (define (evidence-text renaming evidence)
      (match evidence
        ((old:EvInstance instance types subs)
         (form-text (name-text (renamed renaming instance))
                    (append (map (lambda (type) (checked-type-text renaming type)) types)
                            (map (lambda (sub) (evidence-text renaming sub)) subs))))
        ((old:EvParam index) (string-append "param:" (i64->string index)))
        ((old:EvDerived (Some plan)) (plan-text renaming plan))
        ((old:EvDerived (None)) "derived")
        ((old:EvHole id) (string-append "hole:" (i64->string id)))))

    (: plan-text (impl (Fn (Table String) old:Plan -> String)))
    (define (plan-text renaming plan)
      (match plan
        ((old:Trivial) "trivial")
        ((old:Implemented instance)
         (form-text "implemented" (list (name-text (renamed renaming (::name instance))))))
        ((old:Glue) "glue")
        ((old:Refused reason) (form-text "refused" (list reason)))))

    (: term-children (impl (Fn old:Term -> (List old:Expr))))
    (define (term-children term)
      (match term
        ((old:Lit _) (Nil))
        ((old:Var _ _ _) (Nil))
        ((old:Lambda _ body _) (list body))
        ((old:App callee arguments) (Cons callee arguments))
        ((old:If test consequent alternative) (list test consequent alternative))
        ((old:Seq first rest) (list first rest))
        ((old:Let _ value body) (list value body))
        ((old:Match scrutinee clauses) (Cons scrutinee (map ::body clauses)))
        ((old:ScopedInstances _ body) (list body))
        ((old:Ann value _) (list value))
        ((old:Handle _ implementations body) (append (map ::second implementations) (list body)))
        ((old:Convert value _) (list value))
        ((old:TryConvert value _) (list value))
        ((old:TypeTest value _) (list value))))

    (: old-loc-text (impl (Fn old:Loc -> String)))
    (define (old-loc-text loc)
      (string-append (::file loc) ":" (i64->string (::line loc)) ":" (i64->string (::column loc))))

    (: checked-scheme-text (impl (Fn (Table String) old:Scheme -> String)))
    (define (checked-scheme-text renaming scheme)
      (normal-scheme-text (old:Scheme (::vars scheme)
                                      (::constraints scheme)
                                      (::copy scheme)
                                      (closures-named renaming (::type scheme)))))

    ))
