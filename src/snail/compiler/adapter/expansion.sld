;; Whole programs compiled by the new passes, expanded, bound, derived,
;; declared, dispatched and cohered, beside the old expander, which
;; tests/compare-compiler.sld runs, compiled, over the suites' programs
;; that load completely. A program that asks for a target's files is
;; supplied stand-in files for each target it asks for, the same to both.
;; Both succeed or both fail.
;; When both fail, the first problem each reports is compared, message and
;; place; the old expander reports several when several bodies fail, and
;; those programs are named apart, with whether every problem agrees. When
;; both succeed, each library the old expansion records is compared: the
;; names it exports, in order; its written top-level definitions, in
;; order; and each one's value in a normal form, as is a program's body;
;; the files it links, each LinkImport beside the old value of its handle,
;; and the files the build must place beside the program, beside the old
;; `library-links`; each instance `derive` wrote, beside the old instance
;; of its class and types, by its variables, its requirements and its
;; method's value in the normal form, and the derived instances of each
;; class in the old order; each instance whose methods the old expander
;; marks as dispatched, a dispatch clause's or one `dynamic-instances`
;; generates, beside the instance in its place in the library's listing,
;; by its head and each method's value in the normal form; and its
;; entities, as (snail compiler adapter declaration) compares them. And
;; the targets the program asks for,
;; which the stand-in files were supplied for, are compared with those the
;; old expansion records of its libraries. The integrator keeps no
;; library's Expanded tree, so whether a library derives is compared
;; through the instances and the order of the libraries, which places the
;; implicit libraries where the first one derives.
;;
;; The normal form is a text in which each local is numbered in the order
;; it is bound, each macro-written global is its name marked as written
;; by an expansion, without the expansion's number, each field function is
;; its name, a linked file's handle is the old expander's name for it,
;; `library:%link path`, and a `case-id` is the TypeId `declare` gives its
;; case, beside the number the old expander writes. A conversion keeps its
;; type, since the type is what it does; a dispatched method's call of an
;; instance's implementation names it as the old expander does, by the
;; implementation in the old instance in the same place. It leaves out
;; other types, whether a function may capture, the methods of an instance
;; a library writes and effect defaults, which the old expander names
;; afresh, and statements of a library.
(define-library (snail compiler adapter expansion)
  (export
   expansion-comparison)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (only (snail compiler outline names) library-key)
   (only (snail compiler expand language)
         Expanded
         Global
         TopValue
         TopGlobal
         FieldFunction
         FieldRole
         Accessor
         Replacer
         Setter
         Swapper
         Local
         Constant
         Integer
         Float
         Text
         Character
         ByteVector
         Boolean
         UnitValue
         ClassRef
         ClassGlobal
         FieldClass)
   (only (snail compiler expand offer) Offer Export)
   (snail compiler bind supply)
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
   (snail compiler dispatch language)
   (only (snail compiler dispatch listing) Listed ListedInstance FieldInstance listed-class)
   (only (snail compiler bind placed) Placed)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate compile)
   (snail compiler integrate sha256)
   (only (snail compiler adapter outline) feedback-text)
   (only (snail compiler adapter load) old-expansion-with)
   (only (snail compiler adapter declaration)
         old-name
         old-type
         normal-type-text
         declaration-differences)
   (prefix (only (snail shell compiler read)
                 Loc
                 Datum
                 DInt
                 DFloat
                 DString
                 DChar
                 DBytes
                 DBool
                 DUnit
                 SourceDiagnostic
                 diagnostics->list
                 Stop
                 Failed
                 Requested)
           old:)
   (prefix (only (snail shell compiler core)
                 Type
                 TCon
                 TRigid
                 Constraint
                 Instance
                 Constructor
                 Value
                 Defined
                 case-type-id
                 class-instances
                 Expr
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
                 Program
                 Foreign
                 Import
                 program-value
                 library-items
                 program-items)
           old:)
   (prefix (only (snail shell compiler expand) ExpandedProgram library-links) old:)
   (prefix (only (snail shell compiler inputs) Inputs no-inputs supply-artifact) old:))
  (begin

    ;; ---- Programs ----

    ;; What the program at `path` finds: a kind, and what it says.
    ;; Producers' outputs are read from `generated`.
    (: expansion-comparison
       (impl (Fn (List String) String String -> (Pair String String) ! fs)))
    (define (expansion-comparison directories generated path)
      (let ((supplied (supplied-expansion directories generated path (Nil))))
        (match (::first supplied)
          ((Err feedback)
           (match (load-program directories generated path)
             ((Err _)
              (Pair "not compared" (string-append "it does not load: " (feedback-text feedback))))
             ((Ok _) (outcomes (::first supplied) (old-expansion-for directories path supplied)))))
          ((Ok (WaitingForProducers _)) (Pair "not compared" "it reaches a generated library"))
          (new (outcomes new (old-expansion-for directories path supplied))))))

    (: old-expansion-for
       (impl
        (Fn (List String) String (Pair (Result ProgramCompilation (List Feedback)) (List Supplied))
            -> (Pair (Result old:ExpandedProgram old:Stop) (List String))
            !
            fs)))
    (define (old-expansion-for directories path supplied)
      (Pair (old-expansion-with directories (old-inputs (::second supplied)) path)
            (map ::target (::second supplied))))

    ;; ---- Targets ----

    ;; The files supplied for each target, the same to both compilers.
    (struct Supplied
      ((target String)
       (files (List TargetFile))))

    ;; The program compiled, with stand-in files for each target
    ;; it asks for, and the targets supplied. Expanding stops at the first
    ;; library that asks for a target not supplied, so the targets are
    ;; supplied a library at a time.
    (: supplied-expansion
       (impl (Fn (List String) String String (List Supplied)
                 -> (Pair (Result ProgramCompilation (List Feedback)) (List Supplied))
                 !
                 fs)))
    (define (supplied-expansion directories generated path supplied)
      (match (compile-program directories generated (target-table supplied) path)
        ((Ok (WaitingForTargets requests))
         (supplied-expansion directories
                             generated
                             path
                             (append supplied
                                     (map (lambda (request)
                                            (Supplied (::target request)
                                                      (stand-in-files (::target request))))
                                          requests))))
        (new (Pair new supplied))))

    ;; Two files, the first holding the target's name, so two targets'
    ;; lists differ.
    (: stand-in-files (impl (Fn String -> (List TargetFile))))
    (define (stand-in-files target)
      (list (TargetFile "index.html" (text-bytes target))
            (TargetFile "main.wasm" (text-bytes "wasm"))))

    (: text-bytes (impl (Fn String -> Bytes)))
    (define (text-bytes text)
      (list->vector
       (map (lambda (char) (i32->u8 (i64->i32 (char->integer char)))) (string->list text))))

    (: target-table (impl (Fn (List Supplied) -> (Table (List TargetFile)))))
    (define (target-table supplied)
      (fold-left (lambda (table entry) (table-set table (::target entry) (::files entry)))
                 empty-table
                 supplied))

    (: old-inputs (impl (Fn (List Supplied) -> old:Inputs)))
    (define (old-inputs supplied)
      (fold-left (lambda (inputs entry)
                   (old:supply-artifact inputs
                                        (::target entry)
                                        (map (lambda (file) (Pair (::path file) (::bytes file)))
                                             (::files entry))))
                 old:no-inputs
                 supplied))

    ;; ---- Outcomes ----

    ;; `old` is the old expansion and the targets the new expansion was
    ;; supplied, which the old one was too.
    (: outcomes
       (impl (Fn (Result ProgramCompilation (List Feedback))
                 (Pair (Result old:ExpandedProgram old:Stop) (List String))
                 ->
                 (Pair String String))))
    (define (outcomes new supplied)
      (outcomes-with new (::first supplied) (::second supplied)))

    (: outcomes-with
       (impl (Fn (Result ProgramCompilation (List Feedback))
                 (Result old:ExpandedProgram old:Stop)
                 (List String)
                 ->
                 (Pair String String))))
    (define (outcomes-with new old targets)
      (match (Pair new old)
        ((Pair (Err feedback) (Err (old:Failed diagnostics)))
         (failures feedback (old:diagnostics->list diagnostics)))
        ((Pair (Err feedback) (Err (old:Requested _)))
         (Pair "not compared" "the old compiler asks for an input"))
        ((Pair (Err feedback) (Ok _))
         (Pair "only the new fails" (problem-text (first-feedback feedback))))
        ((Pair (Ok _) (Err (old:Failed diagnostics)))
         (Pair "only the old fails"
               (old-problem-text (first-old (old:diagnostics->list diagnostics)))))
        ((Pair (Ok _) (Err (old:Requested _)))
         (Pair "not compared" "the old compiler asks for an input"))
        ((Pair (Ok (CompiledAll files)) (Ok expanded))
         (expansions-comparison files expanded targets))
        ((Pair (Ok (WaitingForProducers _)) _)
         (Pair "not compared" "it reaches a generated library"))
        ((Pair (Ok (WaitingForTargets _)) _) (Pair "not compared" "it waits for a target"))))

    ;; ---- Problems ----

    (: failures (impl (Fn (List Feedback) (List old:SourceDiagnostic) -> (Pair String String))))
    (define (failures feedback diagnostics)
      (let ((new (map problem-text feedback))
            (old (map old-problem-text diagnostics)))
        (cond ((not (string=? (first-text new) (first-text old)))
               (Pair "fail differently"
                     (string-append "new: " (first-text new) "; old: " (first-text old))))
              ((null? (rest-texts old)) (Pair "fail alike" ""))
              ((same-texts? new old)
               (Pair "fail alike, several problems" (string-join old " | ")))
              (else
               (Pair "fail alike first, several problems differ"
                     (string-append "new: "
                                    (string-join new " | ")
                                    "; old: "
                                    (string-join old " | ")))))))

    (: first-text (impl (Fn (List String) -> String)))
    (define (first-text texts)
      (match texts
        ((Cons text _) text)
        ((Nil) "")))

    (: rest-texts (impl (Fn (List String) -> (List String))))
    (define (rest-texts texts)
      (match texts
        ((Cons _ rest) rest)
        ((Nil) (Nil))))

    (: same-texts? (impl (Fn (List String) (List String) -> Bool)))
    (define (same-texts? texts others)
      (and (= (length texts) (length others))
           (every? (lambda (pair) (string=? (::first pair) (::second pair))) (zip texts others))))

    (: first-feedback (impl (Fn (List Feedback) -> Feedback)))
    (define (first-feedback feedback)
      (match feedback
        ((Cons first _) first)
        ((Nil) (Feedback (Loc "" 0 0) "no feedback"))))

    (: first-old (impl (Fn (List old:SourceDiagnostic) -> old:SourceDiagnostic)))
    (define (first-old diagnostics)
      (match diagnostics
        ((Cons first _) first)
        ((Nil) (old:SourceDiagnostic (old:Loc "" 0 0) "no diagnostic"))))

    (: problem-text (impl (Fn Feedback -> String)))
    (define (problem-text feedback)
      (let ((loc (::loc feedback)))
        (place-text (::file loc) (::line loc) (::column loc) (::message feedback))))

    (: old-problem-text (impl (Fn old:SourceDiagnostic -> String)))
    (define (old-problem-text diagnostic)
      (let ((loc (::loc diagnostic)))
        (place-text (::file loc) (::line loc) (::column loc) (::message diagnostic))))

    (: place-text (impl (Fn String I64 I64 String -> String)))
    (define (place-text file line column message)
      (string-append file ":" (i64->string line) ":" (i64->string column) ": " message))

    ;; ---- Libraries ----

    ;; Each library the old expansion records, beside the new one of the
    ;; same name; the primitive library, which records nothing, is not.
    (: expansions-comparison
       (impl (Fn (List CompiledFile) old:ExpandedProgram (List String) -> (Pair String String))))
    (define (expansions-comparison files expanded targets)
      (let* ((program (::program expanded))
             (old-libraries (old:library-items program (old:program-items program)))
             (implementations (implementation-names files program))
             (differences (concatenate
                           (map (lambda (file)
                                  (match (find (lambda (entry)
                                                 (string=? (::first entry) (file-key file)))
                                               old-libraries)
                                    ((Some entry)
                                     (concatenate
                                      (list (library-differences file
                                                                 (::second entry)
                                                                 (old-exports expanded
                                                                              (::first entry))
                                                                 program)
                                            (link-differences file expanded)
                                            (instance-differences file
                                                                  program
                                                                  (::second entry))
                                            (dispatched-differences file
                                                                    program
                                                                    (::second entry)
                                                                    implementations)
                                            (declaration-differences files file program))))
                                    ((None) (Nil))))
                                files))))
        (match (concatenate (list (order-difference files old-libraries)
                                  (targets-difference files expanded targets)
                                  differences))
          ((Nil) (Pair "expand alike" ""))
          (found (Pair "expansions differ" (string-join found "; "))))))

    ;; The libraries come in the old expansion's order, the implicit
    ;; libraries of a deriving clause among them, but for the primitive
    ;; library, which the old expansion never lists.
    (: order-difference
       (impl (Fn (List CompiledFile) (List (Pair String (List old:Item))) -> (List String))))
    (define (order-difference files old-libraries)
      (let ((new (filter (lambda (key) (not (string=? key "snail.core.primitive")))
                         (map file-key files)))
            (old (map ::first old-libraries)))
        (if (same-texts? new old)
            (Nil)
            (list (string-append "the order differs: new " (string-join new " ")
                                 "; old " (string-join old " "))))))

    (: file-key (impl (Fn CompiledFile -> String)))
    (define (file-key file)
      (library-key (::library file)))

    (: old-exports (impl (Fn old:ExpandedProgram String -> (List String))))
    (define (old-exports expanded key)
      (match (table-ref (::libraries expanded) key)
        ((Some entry) (map ::first (::exports entry)))
        ((None) (Nil))))

    ;; The targets the program asks for, each once, in name order: those
    ;; the new expansion was supplied, beside those the old expansion
    ;; records of the same libraries.
    (: targets-difference
       (impl (Fn (List CompiledFile) old:ExpandedProgram (List String) -> (List String))))
    (define (targets-difference files expanded targets)
      (let ((new (names-text targets))
            (old (names-text (concatenate (map (lambda (file)
                                                 (match (table-ref (::libraries expanded)
                                                                   (file-key file))
                                                   ((Some entry) (map ::name (::artifacts entry)))
                                                   ((None) (Nil))))
                                               files)))))
        (if (string=? new old)
            (Nil)
            (list (string-append "the targets asked for differ: new " new "; old " old)))))

    (: names-text (impl (Fn (List String) -> String)))
    (define (names-text names)
      (string-append "("
                     (string-join (list-sort string<? (delete-duplicates string=? names)) " ")
                     ")"))

    ;; ---- Linked files ----

    ;; The files a library links: each LinkImport's digest beside the old
    ;; value of its handle, an import from "snail.runtime.link" named for
    ;; the digest; and the files to place, in order, beside the old
    ;; `library-links`.
    (: link-differences (impl (Fn CompiledFile old:ExpandedProgram -> (List String))))
    (define (link-differences file expanded)
      (let* ((key (file-key file))
             (new (map placed-text (::placed file)))
             (old (map (lambda (linked) (string-append (::digest linked) " at " (::path linked)))
                       (old:library-links expanded key))))
        (append (concatenate (map (lambda (top) (import-difference key (::program expanded) top))
                                  (library-tops (::dispatched file))))
                (if (same-texts? new old)
                    (Nil)
                    (list (string-append key ": the files to place differ: new "
                                         (string-join new ", ")
                                         "; old "
                                         (string-join old ", ")))))))

    (: placed-text (impl (Fn Placed -> String)))
    (define (placed-text placed)
      (string-append (::digest placed) " at " (::file placed)))

    (: import-difference (impl (Fn String old:Program Top -> (List String))))
    (define (import-difference key program top)
      (match top
        ((LinkImport _ path digest _ _)
         (let ((name (handle-name key path)))
           (match (old:program-value program name)
             ((Some (old:Foreign import _))
              (if (and (string=? (::module import) "snail.runtime.link")
                       (string=? (::symbol import) digest))
                  (Nil)
                  (list (string-append name " imports " (::module import) " " (::symbol import)
                                       " in the old, " digest " in the new"))))
             (_ (list (string-append name " is no linked file's import in the old"))))))
        (_ (Nil))))

    (: library-tops (impl (Fn Dispatched -> (List Top))))
    (define (library-tops library)
      (match library
        ((Defined _ tops _ _) tops)
        ((Program tops _ _) tops)))

    ;; The old expander's name for the handle of a file a library links.
    (: handle-name (impl (Fn String (List String) -> String)))
    (define (handle-name key path)
      (string-append key ":%link " (string-join path "/")))

    ;; Each handle a library's LinkImports declare, with its old name.
    (: handle-names (impl (Fn Dispatched -> (List (Pair Global String)))))
    (define (handle-names library)
      (concatenate (map (lambda (top)
                          (match top
                            ((LinkImport global path _ _ _)
                             (list
                              (Pair global (handle-name (library-key (::library global)) path))))
                            (_ (Nil))))
                        (library-tops library))))

    ;; ---- Derived instances ----

    ;; Each instance `derive` wrote, beside the old instance of its class
    ;; and types, by its variables, its requirements, and its method's
    ;; value in the normal form; and the derived instances of a class in
    ;; the old expansion's order. The old instance's methods are named
    ;; afresh, so its method is found by its label.
    (: instance-differences
       (impl (Fn CompiledFile old:Program (List old:Item) -> (List String))))
    (define (instance-differences file program items)
      (let* ((key (file-key file))
             (names (Context (handle-names (::dispatched file)) (Nil)))
             (tops (library-tops (::dispatched file)))
             (derived (derived-instances tops))
             (old (library-instances program key)))
        (concatenate
         (list (concatenate (map (lambda (instance)
                                   (derived-difference names items old instance))
                                 derived))
               (instance-order key derived old)))))

    ;; The instances `derive` placed: those that follow a struct or an
    ;; enum at its own place, inside an instance scope too.
    (: derived-instances (impl (Fn (List Top) -> (List Instance))))
    (define (derived-instances tops)
      (match tops
        ((Nil) (Nil))
        ((Cons (InstanceScope _ inner _) rest)
         (append (derived-instances inner) (derived-instances rest)))
        ((Cons (TopData data) rest) (following (::loc data) rest))
        ((Cons _ rest) (derived-instances rest))))

    (: following (impl (Fn Loc (List Top) -> (List Instance))))
    (define (following loc tops)
      (match tops
        ((Cons (TopInstance instance) rest)
         (if (same-loc? (::loc instance) loc)
             (Cons instance (following loc rest))
             (derived-instances tops)))
        (_ (derived-instances tops))))

    (: same-loc? (impl (Fn Loc Loc -> Bool)))
    (define (same-loc? loc other)
      (and (string=? (::file loc) (::file other))
           (= (::line loc) (::line other))
           (= (::column loc) (::column other))))

    ;; The old instances the library declares, its name before the colon
    ;; of theirs, of the two classes `derive` writes.
    (: library-instances (impl (Fn old:Program String -> (List old:Instance))))
    (define (library-instances program key)
      (filter (lambda (instance)
                (match (string-index-of (::name instance) ":")
                  ((Some index) (string=? (substring (::name instance) 0 index) key))
                  ((None) #f)))
              (append (old:class-instances program "snail.shell.wire:Serialize")
                      (old:class-instances program "snail.shell.wire:Deserialize"))))

    (: derived-difference
       (impl (Fn Context (List old:Item) (List old:Instance) Instance -> (List String))))
    (define (derived-difference names items old instance)
      (let ((head (instance-head-text instance)))
        (match (find (lambda (candidate) (string=? (old-head-text candidate) head)) old)
          ((None) (list (string-append "no old instance " head)))
          ((Some found)
           (let ((new (instance-text names instance))
                 (old (old-instance-text items found)))
             (if (string=? new old)
                 (Nil)
                 (list (string-append "the instance " head " differs: new " new "; old " old))))))))

    ;; The derived instances of each class come in the order the old
    ;; instances of the class do; the old program keeps its instances by
    ;; class, so the two classes are not ordered against each other.
    (: instance-order (impl (Fn String (List Instance) (List old:Instance) -> (List String))))
    (define (instance-order key derived old)
      (concatenate
       (map (lambda (class)
              (let* ((new (map instance-head-text
                               (filter (lambda (instance) (string=? (class-text instance) class))
                                       derived)))
                     (old-heads (filter (lambda (head) (member? head new))
                                        (map old-head-text
                                             (filter (lambda (instance)
                                                       (string=?
                                                        (old-global-text (::class instance))
                                                        class))
                                                     old)))))
                (if (same-texts? new old-heads)
                    (Nil)
                    (list (string-append key ": the derived instances of " class
                                         " come in another order: new " (string-join new ", ")
                                         "; old " (string-join old-heads ", "))))))
            (list "snail.shell.wire:Serialize" "snail.shell.wire:Deserialize"))))

    ;; ---- Dispatched instances ----

    ;; The library's listing beside the old instances of each class it
    ;; lists that the library declares, in place; a class whose instances
    ;; are not as many is left out, which (snail compiler adapter
    ;; declaration) reports.
    (: paired-instances (impl (Fn CompiledFile old:Program -> (List (Pair Listed old:Instance)))))
    (define (paired-instances file program)
      (let* ((key (file-key file))
             (classes (delete-duplicates string=? (map listed-key (::listing file)))))
        (concatenate
         (map (lambda (class)
                (let ((new (filter (lambda (entry) (string=? (listed-key entry) class))
                                   (::listing file)))
                      (old (filter (lambda (instance) (of-library? key (::name instance)))
                                   (old:class-instances program class))))
                  (if (= (length new) (length old))
                      (zip new old)
                      (Nil))))
              classes))))

    ;; The old program's name of an entry's class, which keys its
    ;; instances.
    (: listed-key (impl (Fn Listed -> String)))
    (define (listed-key entry)
      (match (listed-class entry)
        ((ClassGlobal global) (old-name global))
        ((FieldClass label) (string-append "::" label))))

    (: of-library? (impl (Fn String String -> Bool)))
    (define (of-library? key name)
      (match (string-index-of name ":")
        ((Some index) (and (> index 0) (string=? (substring name 0 index) key)))
        ((None) #f)))

    ;; Each implementation of every library's instances, by the old name
    ;; of the implementation in the old instance in its place.
    (: implementation-names
       (impl (Fn (List CompiledFile) old:Program -> (List (Pair Global String)))))
    (define (implementation-names files program)
      (concatenate
       (map (lambda (file)
              (concatenate (map (lambda (pair)
                                  (match (::first pair)
                                    ((ListedInstance instance _)
                                     (if (= (length (::methods instance))
                                            (length (::methods (::second pair))))
                                         (map (lambda (methods)
                                                (Pair (::implementation (::first methods))
                                                      (::second (::second methods))))
                                              (zip (::methods instance)
                                                   (::methods (::second pair))))
                                         (Nil)))
                                    ((FieldInstance _ _) (Nil))))
                                (paired-instances file program))))
            files)))

    ;; Each instance the old expander's dispatch wrote the methods of,
    ;; beside the instance in its place: their heads, and each method's
    ;; value in the normal form.
    (: dispatched-differences
       (impl
        (Fn CompiledFile old:Program (List old:Item) (List (Pair Global String)) -> (List String))))
    (define (dispatched-differences file program items implementations)
      (let ((names (Context (handle-names (::dispatched file)) implementations)))
        (concatenate (map (lambda (pair)
                            (match (::first pair)
                              ((ListedInstance instance _)
                               (if (old-dispatched? program (::second pair))
                                   (dispatched-difference names items instance (::second pair))
                                   (Nil)))
                              ((FieldInstance _ _) (Nil))))
                          (paired-instances file program)))))

    ;; Whether the old expander wrote the instance's methods: their
    ;; values are marked as functions, which only `dispatch-instance-method`
    ;; and `install-generated-instance` do.
    (: old-dispatched? (impl (Fn old:Program old:Instance -> Bool)))
    (define (old-dispatched? program instance)
      (and (not (null? (::methods instance)))
           (every? (lambda (method)
                     (match (table-ref (::values program) (::second method))
                       ((Some (old:Defined _ _ function?)) function?)
                       (_ #f)))
                   (::methods instance))))

    (: dispatched-difference
       (impl (Fn Context (List old:Item) Instance old:Instance -> (List String))))
    (define (dispatched-difference names items instance old)
      (let ((new-text (form-text (form-text (class-text instance)
                                            (map type-text
                                                 (append (::types instance) (::outputs instance))))
                                 (map (lambda (method) (method-text names method))
                                      (::methods instance))))
            (old-text (form-text (old-head-text old)
                                 (map (lambda (method)
                                        (form-text (old-member-text (::first method))
                                                   (list
                                                    (old-method-text items (::second method)))))
                                      (::methods old)))))
        (if (string=? new-text old-text)
            (Nil)
            (list (string-append "the dispatched instance " (old-head-text old) " differs: new "
                                 new-text
                                 "; old "
                                 old-text)))))

    ;; A member's name within its class, as `member-text` writes it: a
    ;; field class's reader is its path.
    (: old-member-text (impl (Fn String -> String)))
    (define (old-member-text name)
      (if (string=? (substring name 0 (min 2 (string-length name))) "::")
          name
          (short-name name)))

    ;; ---- Instance texts ----

    ;; An instance's class and types, which find the old one.
    (: instance-head-text (impl (Fn Instance -> String)))
    (define (instance-head-text instance)
      (form-text (class-text instance) (map type-text (::types instance))))

    (: class-text (impl (Fn Instance -> String)))
    (define (class-text instance)
      (match (::class instance)
        ((ClassGlobal global) (global-text global))
        ((FieldClass label) (string-append "::" label))))

    (: old-head-text (impl (Fn old:Instance -> String)))
    (define (old-head-text instance)
      (form-text (old-global-text (::class instance)) (map old-type-text (::types instance))))

    ;; Its variables, requirements and methods.
    (: instance-text (impl (Fn Context Instance -> String)))
    (define (instance-text names instance)
      (form-text "instance"
                 (list (form-text "" (map variable-text (::variables instance)))
                       (form-text "" (map requirement-text (::requirements instance)))
                       (form-text "" (map (lambda (method) (method-text names method))
                                          (::methods instance))))))

    ;; A method by the member it implements and its value's normal form.
    (: method-text (impl (Fn Context InstanceMethod -> String)))
    (define (method-text names method)
      (form-text (member-text (::member method))
                 (list (::text (new-text names (::value method) (Naming (Nil) 0))))))

    ;; The member a method implements, by its name within its class.
    (: member-text (impl (Fn Member -> String)))
    (define (member-text member)
      (match member
        ((ClassMethod global) (::name global))
        ((FieldReader label) (string-append "::" label))))

    ;; A variable a derived instance's head writes.
    (: variable-text (impl (Fn TypeVariable -> String)))
    (define (variable-text variable)
      (match variable
        ((Written name) name)
        (_ "?")))

    (: old-instance-text (impl (Fn (List old:Item) old:Instance -> String)))
    (define (old-instance-text items instance)
      (form-text "instance"
                 (list (form-text "" (::vars instance))
                       (form-text "" (map old-requirement-text (::requires instance)))
                       (form-text "" (map (lambda (method)
                                            (form-text (short-name (::first method))
                                                       (list
                                                        (old-method-text items (::second method)))))
                                          (::methods instance))))))

    (: old-method-text (impl (Fn (List old:Item) String -> String)))
    (define (old-method-text items global)
      (match (find (lambda (item)
                     (match item
                       ((old:Define name _) (string=? name global))
                       (_ #f)))
                   items)
        ((Some (old:Define _ value)) (::text (old-text value (Naming (Nil) 0))))
        (_ (string-append "no definition of " global))))

    (: requirement-text (impl (Fn Requirement -> String)))
    (define (requirement-text requirement)
      (match requirement
        ((ClassRequirement (ClassGlobal global) types)
         (form-text (global-text global) (map type-text types)))
        (_ "?")))

    (: old-requirement-text (impl (Fn old:Constraint -> String)))
    (define (old-requirement-text constraint)
      (form-text (old-global-text (::class constraint)) (map old-type-text (::types constraint))))

    ;; A type's normal name: a builtin of (snail core forms) is its name
    ;; alone, as the old compiler names it, and a variable is marked.
    (: type-text (impl (Fn Type -> String)))
    (define (type-text type)
      (match type
        ((Con global (Nil)) (type-name-text global))
        ((Con global arguments) (form-text (type-name-text global) (map type-text arguments)))
        ((Var (Written name)) (string-append "'" name))
        (_ "?")))

    (: type-name-text (impl (Fn Global -> String)))
    (define (type-name-text global)
      (if (string=? (library-key (::library global)) "snail.core.forms")
          (::name global)
          (global-text global)))

    (: old-type-text (impl (Fn old:Type -> String)))
    (define (old-type-text type)
      (match type
        ((old:TCon name (Nil)) (old-global-text name))
        ((old:TCon name arguments) (form-text (old-global-text name) (map old-type-text arguments)))
        ((old:TRigid name) (string-append "'" name))
        (_ "?")))

    ;; ---- Definitions ----

    (: library-differences
       (impl (Fn CompiledFile (List old:Item) (List String) old:Program -> (List String))))
    (define (library-differences file items old-exported program)
      (let* ((key (file-key file))
             (exported (map ::name (::exports (::offer file))))
             (new (written-definitions (::dispatched file)))
             (new-names (map ::first new))
             (old (filter (lambda (entry)
                            (or (member? (::first entry) new-names)
                                (not (fresh-name? (::first entry)))))
                          (old-definitions items)))
             (old-names (map ::first old)))
        (cond ((not (same-texts? exported old-exported))
               (list (string-append key ": exports differ: new " (string-join exported " ")
                                    "; old " (string-join old-exported " "))))
              ((not (same-texts? new-names old-names))
               (list (string-append key ": definitions differ: new " (string-join new-names " ")
                                    "; old " (string-join old-names " "))))
              (else
               (concatenate (map (lambda (pair)
                                   (if
                                    (string=? (::second (::first pair)) (::second (::second pair)))
                                    (Nil)
                                    (list
                                     (string-append key ": the value of " (::first (::first pair))
                                                    " differs: new " (::second (::first pair))
                                                    "; old " (::second (::second pair))))))
                                 (zip new old)))))))

    ;; A name the old expander makes afresh has a dot and a digit after
    ;; its library, as `show.12` and `dynamic.4.0.add`; `%body` is a
    ;; program's body.
    (: fresh-name? (impl (Fn String -> Bool)))
    (define (fresh-name? name)
      (or (string-suffix? name ":%body")
          (match (string-index-of name ":")
            ((Some index)
             (dotted-digit? (string->list (substring name index (string-length name)))))
            ((None) #f))))

    (: dotted-digit? (impl (Fn (List Char) -> Bool)))
    (define (dotted-digit? chars)
      (match chars
        ((Cons #\. (Cons digit rest)) (or (char-numeric? digit) (dotted-digit? (Cons digit rest))))
        ((Cons _ rest) (dotted-digit? rest))
        ((Nil) #f)))

    (: string-suffix? (impl (Fn String String -> Bool)))
    (define (string-suffix? text suffix)
      (let ((length-of (string-length text))
            (suffix-length (string-length suffix)))
        (and (>= length-of suffix-length)
             (string=? (substring text (- length-of suffix-length) length-of) suffix))))

    (: string-index-of (impl (Fn String String -> (Option I64))))
    (define (string-index-of text part)
      (let loop ((index 0))
        (cond ((> (+ index (string-length part)) (string-length text)) (None))
              ((string=? (substring text index (+ index (string-length part))) part) (Some index))
              (else (loop (+ index 1))))))

    ;; ---- New definitions ----

    ;; Each written definition, by its normal name, with its value's
    ;; normal form; a program's body is `main:%body`, a function of
    ;; nothing.
    (: written-definitions (impl (Fn Dispatched -> (List (Pair String String)))))
    (define (written-definitions library)
      (let ((names (Context (handle-names library) (Nil))))
        (match library
          ((Defined _ tops _ _) (tops-definitions names tops (Nil)))
          ((Program tops body _)
           (append (tops-definitions names tops (Nil))
                   (match body
                     ((Some expr)
                      (list (Pair "main:%body"
                                  (::text (new-text names
                                                    (Lambda (Nil) expr (Loc "" 0 0))
                                                    (Naming (Nil) 0))))))
                     ((None) (Nil))))))))

    (: tops-definitions
       (impl
        (Fn Context (List Top) (List Global) -> (List (Pair String String)))))
    (define (tops-definitions names tops sets)
      (concatenate (map (lambda (top) (top-definitions names top sets)) tops)))

    ;; A definition under a top-level `with-instances` has its sets twice,
    ;; as the old expander scopes them.
    (: top-definitions
       (impl (Fn Context Top (List Global) -> (List (Pair String String)))))
    (define (top-definitions names top sets)
      (match top
        ((Define global value _ _ _)
         (list (Pair (global-text global)
                     (::text (new-text names (scoped (scoped value sets) sets) (Naming (Nil) 0))))))
        ((InstanceScope own tops _)
         (tops-definitions names tops (delete-duplicates same-global-text? (append own sets))))
        (_ (Nil))))

    (: same-global-text? (impl (Fn Global Global -> Bool)))
    (define (same-global-text? global other)
      (string=? (global-text global) (global-text other)))

    (: scoped (impl (Fn Expr (List Global) -> Expr)))
    (define (scoped value sets)
      (if (null? sets)
          value
          (match value
            ((Lambda parameters body loc) (Lambda parameters (WithInstances sets body loc) loc))
            ((ClosedLambda parameters body loc)
             (ClosedLambda parameters (WithInstances sets body loc) loc))
            (_ (WithInstances sets value (Loc "" 0 0))))))

    ;; ---- Names ----

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
           ((Some entry) (old-global-text (::second entry)))
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

    ;; An old global's name, with each expansion's number dropped from its
    ;; marks: `name%m.12` is `name%`.
    (: old-global-text (impl (Fn String -> String)))
    (define (old-global-text name)
      (list->string (unmarked (string->list name))))

    (: unmarked (impl (Fn (List Char) -> (List Char))))
    (define (unmarked chars)
      (match chars
        ((Nil) (Nil))
        ((Cons #\% (Cons #\m (Cons #\. rest)))
         (Cons #\% (unmarked (drop-digits rest))))
        ((Cons char rest) (Cons char (unmarked rest)))))

    (: drop-digits (impl (Fn (List Char) -> (List Char))))
    (define (drop-digits chars)
      (match chars
        ((Cons char rest) (if (char-numeric? char) (drop-digits rest) chars))
        ((Nil) (Nil))))

    ;; ---- Normal forms ----

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

    (: datum-text (impl (Fn syntax-Datum -> String)))
    (define (datum-text datum)
      (match datum
        ((syntax-Integer value) (string-append "i:" (i64->string value)))
        ((syntax-Float text) (string-append "f:" text))
        ((syntax-Text text) (string-append "s:" text))
        ((syntax-Character char) (string-append "c:" (i64->string (char->integer char))))
        ((syntax-ByteVector bytes) (string-append "b:" (bytes-text bytes)))
        ((syntax-Boolean value) (if value "#t" "#f"))))

    ;; A byte vector by its length and its digest, so two of one length
    ;; but other bytes differ.
    (: bytes-text (impl (Fn Bytes -> String)))
    (define (bytes-text bytes)
      (string-append (i64->string (vector-length bytes)) ":" (bytes->hex (sha256 bytes))))

    ;; ---- Old definitions ----

    (: old-definitions (impl (Fn (List old:Item) -> (List (Pair String String)))))
    (define (old-definitions items)
      (concatenate (map (lambda (item)
                          (match item
                            ((old:Define name value)
                             (list (Pair (old-global-text name)
                                         (::text (old-text value (Naming (Nil) 0))))))
                            (_ (Nil))))
                        items)))

    (: old-texts (impl (Fn (List old:Expr) Naming -> (Pair (List String) Naming))))
    (define (old-texts exprs naming)
      (let loop ((exprs exprs)
                 (naming naming)
                 (texts (Nil)))
        (match exprs
          ((Nil) (Pair (reverse texts) naming))
          ((Cons expr rest)
           (let ((rendered (old-text expr naming)))
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
    (: old-name-text (impl (Fn Naming String -> String)))
    (define (old-name-text naming name)
      (cond ((any? (lambda (entry) (string=? (::first entry) name)) (::locals naming))
             (named naming name))
            ((any? (lambda (char) (char=? char #\:)) (string->list name)) (old-global-text name))
            (else (named naming name))))

    (: old-text (impl (Fn old:Expr Naming -> Rendered)))
    (define (old-text expr naming)
      (match (::term expr)
        ((old:Lit datum) (Rendered (old-datum-text datum) naming))
        ((old:Var name _ _)
         (if (string=? (substring name 0 (min 2 (string-length name))) "::")
             (Rendered name naming)
             (Rendered (old-name-text naming name) naming)))
        ((old:Lambda parameters body _)
         (let* ((binders (old-binders parameters naming))
                (rendered (old-text body (::second binders))))
           (Rendered (form-text "lambda" (list (form-text "" (::first binders)) (::text rendered)))
                     (::naming rendered))))
        ((old:App callee arguments) (old-sequence "call" (Cons callee arguments) naming))
        ((old:If test consequent alternative)
         (old-sequence "if" (list test consequent alternative) naming))
        ((old:Seq first rest) (old-sequence "seq" (list first rest) naming))
        ((old:Let name value body)
         (let* ((binder (bound naming name))
                (value-text (old-text value (::naming binder)))
                (body-text (old-text body (::naming value-text))))
           (Rendered (form-text "let" (list (::text binder) (::text value-text) (::text body-text)))
                     (::naming body-text))))
        ((old:Match scrutinee clauses)
         (let* ((value (old-text scrutinee naming))
                (rendered (old-clauses clauses (::naming value))))
           (Rendered (form-text "match" (Cons (::text value) (::first rendered)))
                     (::second rendered))))
        ((old:ScopedInstances sets body)
         (let ((rendered (old-text body naming)))
           (Rendered (form-text "with-instances"
                                (list (form-text "" (map old-global-text sets)) (::text rendered)))
                     (::naming rendered))))
        ((old:Ann value _) (old-wrapped "ann" value naming))
        ((old:Handle effect implementations body)
         (let* ((values (old-texts (map ::second implementations) naming))
                (body-text (old-text body (::second values))))
           (Rendered (form-text "handle"
                                (Cons (old-global-text effect)
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
        ((old:Convert value type) (old-converted "convert" value type naming))
        ((old:TryConvert value type) (old-converted "try-convert" value type naming))
        ((old:TypeTest value type) (old-converted "type-test" value type naming))))

    (: old-converted (impl (Fn String old:Expr old:Type Naming -> Rendered)))
    (define (old-converted head value type naming)
      (let ((rendered (old-text value naming)))
        (Rendered (form-text head (list (::text rendered) (normal-type-text type)))
                  (::naming rendered))))

    ;; An operation's name within its effect: what follows the library.
    (: short-name (impl (Fn String -> String)))
    (define (short-name name)
      (match (string-index-of name ":")
        ((Some index) (old-global-text (substring name (+ index 1) (string-length name))))
        ((None) name)))

    (: old-sequence (impl (Fn String (List old:Expr) Naming -> Rendered)))
    (define (old-sequence head exprs naming)
      (let ((rendered (old-texts exprs naming)))
        (Rendered (form-text head (::first rendered)) (::second rendered))))

    (: old-wrapped (impl (Fn String old:Expr Naming -> Rendered)))
    (define (old-wrapped head value naming)
      (let ((rendered (old-text value naming)))
        (Rendered (form-text head (list (::text rendered))) (::naming rendered))))

    (: old-clauses (impl (Fn (List old:Clause) Naming -> (Pair (List String) Naming))))
    (define (old-clauses clauses naming)
      (let loop ((clauses clauses)
                 (naming naming)
                 (texts (Nil)))
        (match clauses
          ((Nil) (Pair (reverse texts) naming))
          ((Cons clause rest)
           (let* ((pattern (old-pattern (::pattern clause) naming))
                  (body (old-text (::body clause) (::naming pattern))))
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
             ((Nil) (Rendered (form-text (old-global-text constructor) (reverse texts)) naming))
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

    ))
