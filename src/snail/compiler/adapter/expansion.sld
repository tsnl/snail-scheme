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
;; order; and each one's value in a normal form, as is a program's body,
;; its statements gathered as the old expander gathers them;
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
;; When both succeed, the program (snail compiler adapter program) makes
;; of the new compilation, which milestone A hands the old checker, is
;; compared with the old expansion's too, table by table, in the old
;; expansion's names: its values, data types, classes, effects and each
;; class's instances in order; its runs, and each item of each run in the
;; normal form, with what the normal form leaves out but both hold, each
;; node's place, whether each function may capture and each annotation's
;; type; the files each library links; and each case's TypeId. Then the
;; old checker runs on both: both succeed or both fail, failures by every
;; problem, in order, as written, successes by each definition's scheme
;; and each library's checked items in the normal form, with the types
;; and instantiations the checker wrote.
;;
;; The normal form is (snail compiler adapter normal)'s. The comparisons
;; leave out the methods of an instance a library writes and effect
;; defaults, which the old expander names afresh, and statements of a
;; library.
(define-library (snail compiler adapter expansion)
  (export
   Expansions
   expansion-comparison)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail compiler source)
   (snail compiler names libraries)
   (only (snail compiler expand language) Expanded)
   (only (snail compiler names globals) Global ClassGlobal FieldClass)
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
   (only (snail compiler types type) Type Con Var TypeVariable Written)
   (only (snail compiler types scheme) Requirement ClassRequirement)
   (snail compiler dispatch language)
   (only (snail compiler dispatch listing) Listed ListedInstance FieldInstance listed-class)
   (only (snail compiler bind placed) Placed)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate compile)
   (only (snail compiler adapter outline) feedback-text)
   (only (snail compiler adapter load) old-expansion-with)
   (only (snail compiler declare known) Known Scanned)
   (only (snail compiler declare identities) case-type-id)
   (only (snail compiler adapter declaration)
         old-name
         name-text
         tops-data
         declaration-differences)
   (prefix (only (snail compiler adapter declaration)
                 value-text
                 data-text
                 class-text
                 effect-text
                 instance-text)
           normal-)
   (only (snail compiler adapter expressions) active-sets)
   (snail compiler adapter normal)
   (only (snail compiler adapter program)
         AdaptedProgram
         AdaptedLibrary
         adapted-program
         program-body
         scoped)
   (prefix (only (snail shell compiler read)
                 Loc
                 SourceDiagnostic
                 diagnostics->list
                 Stop
                 Failed
                 Requested
                 compiling)
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
                 Case
                 Scheme
                 case-type-id
                 class-instances
                 Item
                 Define
                 Program
                 Foreign
                 Import
                 program-value
                 library-items
                 program-items)
           old:)
   (prefix (only (snail shell compiler expand) ExpandedProgram LinkedFile library-links) old:)
   (prefix (only (snail shell compiler check) Typed check-program) old:)
   (prefix (only (snail shell compiler inputs) Inputs no-inputs supply-artifact) old:))
  (begin

    ;; ---- Programs ----

    ;; What the program at `path` finds, each a kind and what it says: how
    ;; its expansion compares, and, when both compilers expand it, how the
    ;; program the adapter makes of the new compilation compares with the
    ;; old expansion's, and how the old checker's answers for the two
    ;; compare. Producers' outputs are read from `generated`.
    (struct Expansions
      ((expansion (Pair String String))
       (adapted (Pair String String))
       (checked (Pair String String))))

    (: expansion-comparison (impl (Fn (List String) String String -> Expansions ! fs)))
    (define (expansion-comparison directories generated path)
      (let ((supplied (supplied-expansion directories generated path (Nil))))
        (match (::first supplied)
          ((Err feedback)
           (match (load-program directories generated path)
             ((Err _)
              (unadapted
               (Pair "not compared" (string-append "it does not load: " (feedback-text feedback)))))
             ((Ok _) (outcomes (::first supplied) (old-expansion-for directories path supplied)))))
          ((Ok (WaitingForProducers _))
           (unadapted (Pair "not compared" "it reaches a generated library")))
          (new (outcomes new (old-expansion-for directories path supplied))))))

    (: unadapted (impl (Fn (Pair String String) -> Expansions)))
    (define (unadapted expansion)
      (Expansions expansion (Pair "not compared" "") (Pair "not compared" "")))

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
                 Expansions)))
    (define (outcomes new supplied)
      (match (Pair new (::first supplied))
        ((Pair (Ok (CompiledAll files)) (Ok expanded))
         (let* ((adapted (adapted-program files))
                (renaming (fresh-renaming files (::program adapted) (::program expanded))))
           (Expansions (expansions-comparison files expanded (::second supplied))
                       (adapted-comparison files adapted renaming expanded)
                       (check-comparison renaming (::program adapted) (::program expanded)))))
        (_ (unadapted (outcomes-with new (::first supplied))))))

    (: outcomes-with
       (impl (Fn (Result ProgramCompilation (List Feedback))
                 (Result old:ExpandedProgram old:Stop)
                 ->
                 (Pair String String))))
    (define (outcomes-with new old)
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
        ((Pair (Ok (CompiledAll _)) (Ok _)) (Pair "expand alike" ""))
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
        ((Program tops _) tops)))

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
                                                        (name-text (::class instance))
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
      (form-text (name-text (::class instance)) (map old-type-text (::types instance))))

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
        ((Some (old:Define _ value)) (::text (old-text empty-table value (Naming (Nil) 0))))
        (_ (string-append "no definition of " global))))

    (: requirement-text (impl (Fn Requirement -> String)))
    (define (requirement-text requirement)
      (match requirement
        ((ClassRequirement (ClassGlobal global) types)
         (form-text (global-text global) (map type-text types)))
        (_ "?")))

    (: old-requirement-text (impl (Fn old:Constraint -> String)))
    (define (old-requirement-text constraint)
      (form-text (name-text (::class constraint)) (map old-type-text (::types constraint))))

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
        ((old:TCon name (Nil)) (name-text name))
        ((old:TCon name arguments) (form-text (name-text name) (map old-type-text arguments)))
        ((old:TRigid name) (string-append "'" name))
        (_ "?")))

    ;; ---- Definitions ----

    (: library-differences
       (impl (Fn CompiledFile (List old:Item) (List String) old:Program -> (List String))))
    (define (library-differences file items old-exported program)
      (let* ((key (file-key file))
             (exported (map ::name (::exports (::offer file))))
             (new (written-definitions file))
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

    ;; ---- New definitions ----

    ;; Each written definition, by its normal name, with its value's
    ;; normal form; a program's body is `main:%body`, a function of nothing.
    (: written-definitions (impl (Fn CompiledFile -> (List (Pair String String)))))
    (define (written-definitions file)
      (let ((names (Context (handle-names (::dispatched file)) (Nil)))
            (tops (library-tops (::dispatched file))))
        (append (tops-definitions names tops (Nil))
                (match (if (same-library? (::library file) program-library)
                           (program-body tops)
                           (None))
                  ((Some body)
                   (list (Pair "main:%body" (::text (new-text names body (Naming (Nil) 0))))))
                  ((None) (Nil))))))

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
                     (::text (new-text names (scoped sets (scoped sets value)) (Naming (Nil) 0))))))
        ((InstanceScope own tops _) (tops-definitions names tops (active-sets own sets)))
        (_ (Nil))))

    ;; ---- Adapted programs ----

    ;; The program the adapter makes of the libraries the new passes
    ;; compiled, beside the old expansion's program, table by table: the
    ;; values, data types, classes, effects and instances, in the old
    ;; expansion's names; the libraries' runs and each run's items, in
    ;; order; the files each library links; and each case's TypeId, the
    ;; old compiler's of the adapted program beside the one `declare`
    ;; writes. Metadata is not compared, since the adapter writes none.
    ;; `renaming` gives each name the adapted program makes afresh the old
    ;; expansion's.
    (: adapted-comparison
       (impl (Fn (List CompiledFile) AdaptedProgram (Table String) old:ExpandedProgram
                 -> (Pair String String))))
    (define (adapted-comparison files adapted renaming expanded)
      (let* ((new (::program adapted))
             (old (::program expanded))
             (implementations (implementation-table old)))
        (match (concatenate
                (list (ordered-difference "the values"
                                          (value-texts renaming implementations new)
                                          (value-texts empty-table implementations old))
                      (ordered-difference "the data types"
                                          (sorted-texts
                                           (map normal-data-text (table-values (::types new))))
                                          (sorted-texts
                                           (map normal-data-text (table-values (::types old)))))
                      (ordered-difference "the classes"
                                          (sorted-texts
                                           (map normal-class-text (table-values (::classes new))))
                                          (sorted-texts
                                           (map normal-class-text (table-values (::classes old)))))
                      (ordered-difference "the effects"
                                          (sorted-texts
                                           (map normal-effect-text (table-values (::effects new))))
                                          (sorted-texts
                                           (map normal-effect-text (table-values (::effects old)))))
                      (ordered-difference "the instances"
                                          (instances-texts renaming new)
                                          (instances-texts empty-table old))
                      (runs-differences renaming
                                        #f
                                        (old:library-items new (old:program-items new))
                                        (old:library-items old (old:program-items old)))
                      (ordered-difference "the files linked"
                                          (map adapted-links-text (::libraries adapted))
                                          (old-links-texts expanded))
                      (type-id-differences files new)))
          ((Nil) (Pair "adapt alike" ""))
          (found (Pair "adaptations differ" (string-join found "; "))))))

    ;; Where two lists of texts first part, in order: the two texts from a
    ;; little before the first character they part at.
    (: ordered-difference (impl (Fn String (List String) (List String) -> (List String))))
    (define (ordered-difference what new old)
      (match (first-parting new old)
        ((Some pair)
         (let ((from (max 0 (- (common-prefix-length (::first pair) (::second pair)) 60))))
           (list (string-append what
                                " differ: new "
                                (text-window (::first pair) from)
                                "; old "
                                (text-window (::second pair) from)))))
        ((None) (Nil))))

    (: common-prefix-length (impl (Fn String String -> I64)))
    (define (common-prefix-length text other)
      (let loop ((index 0))
        (if (and (< index (string-length text))
                 (< index (string-length other))
                 (char=? (string-ref text index) (string-ref other index)))
            (loop (+ index 1))
            index)))

    ;; At most 300 characters of `text` from `from`, marked where cut.
    (: text-window (impl (Fn String I64 -> String)))
    (define (text-window text from)
      (let ((end (min (string-length text) (+ from 300))))
        (string-append (if (> from 0) "..." "")
                       (substring text (min from (string-length text)) end)
                       (if (< end (string-length text)) "..." ""))))

    (: first-parting (impl (Fn (List String) (List String) -> (Option (Pair String String)))))
    (define (first-parting new old)
      (match (Pair new old)
        ((Pair (Nil) (Nil)) (None))
        ((Pair (Cons text more) (Cons other others))
         (if (string=? text other) (first-parting more others) (Some (Pair text other))))
        ((Pair (Cons text _) (Nil)) (Some (Pair text "nothing")))
        ((Pair (Nil) (Cons other _)) (Some (Pair "nothing" other)))))

    ;; ---- Fresh names ----

    ;; The old expansion's name of each value the adapted program names
    ;; afresh: each instance and its implementations, paired with the old
    ;; instance in its place among its class's; each default, by its
    ;; effect and operation; and each linked file's handle, by its path.
    ;; A class's instances or an effect's defaults the two programs do not
    ;; hold alike are left as they are, which the tables report.
    (: fresh-renaming
       (impl (Fn (List CompiledFile) old:Program old:Program -> (Table String))))
    (define (fresh-renaming files new old)
      (fold-left (lambda (table pair) (table-set table (::first pair) (::second pair)))
                 empty-table
                 (concatenate (list (instance-renaming new old)
                                    (default-renaming new old)
                                    (concatenate (map (lambda (file)
                                                        (map (lambda (handle)
                                                               (Pair (old-name (::first handle))
                                                                     (::second handle)))
                                                             (handle-names (::dispatched file))))
                                                      files))))))

    ;; A table keyed by the normal form of its names, which a macro-written
    ;; name has in both programs.
    (: normal-keys (All (T) (requires (Copy T)) (impl (Fn (Table T) -> (Table T)))))
    (define (normal-keys table)
      (fold-left (lambda (normal key)
                   (match (table-ref table key)
                     ((Some value) (table-set normal (name-text key) value))
                     ((None) normal)))
                 empty-table
                 (list-sort string<? (table-keys table))))

    (: instance-renaming (impl (Fn old:Program old:Program -> (List (Pair String String)))))
    (define (instance-renaming new old)
      (let ((theirs (normal-keys (::instances old))))
        (concatenate
         (map (lambda (class)
                (let ((ours (old:class-instances new class))
                      (others (match (table-ref theirs (name-text class))
                                ((Some found) found)
                                ((None) (Nil)))))
                  (if (= (length ours) (length others))
                      (concatenate (map paired-names (zip ours others)))
                      (Nil))))
              (list-sort string<? (table-keys (::instances new)))))))

    ;; An instance's name and its implementations', beside the old one's.
    (: paired-names (impl (Fn (Pair old:Instance old:Instance) -> (List (Pair String String)))))
    (define (paired-names pair)
      (let ((ours (::methods (::first pair)))
            (others (::methods (::second pair))))
        (Cons (Pair (::name (::first pair)) (::name (::second pair)))
              (if (= (length ours) (length others))
                  (map (lambda (methods)
                         (Pair (::second (::first methods)) (::second (::second methods))))
                       (zip ours others))
                  (Nil)))))

    (: default-renaming (impl (Fn old:Program old:Program -> (List (Pair String String)))))
    (define (default-renaming new old)
      (let ((theirs (normal-keys (::effects old))))
        (concatenate
         (map (lambda (name)
                (match (Pair (table-ref (::effects new) name) (table-ref theirs (name-text name)))
                  ((Pair (Some ours) (Some others))
                   (concatenate (map (lambda (default) (paired-default default (::defaults others)))
                                     (::defaults ours))))
                  (_ (Nil))))
              (list-sort string<? (table-keys (::effects new)))))))

    ;; A default, by its operation's name and its own, beside the old
    ;; default of the operation.
    (: paired-default
       (impl (Fn (Pair String String) (List (Pair String String)) -> (List (Pair String String)))))
    (define (paired-default default others)
      (match (find
              (lambda (other) (string=? (name-text (::first other)) (name-text (::first default))))
              others)
        ((Some found) (list (Pair (::second default) (::second found))))
        ((None) (Nil))))

    ;; Every implementation of an instance the old program holds, by its
    ;; name.
    (: implementation-table (impl (Fn old:Program -> (Table Bool))))
    (define (implementation-table program)
      (fold-left (lambda (table name) (table-set table name #t))
                 empty-table
                 (concatenate (map (lambda (class)
                                     (concatenate (map (lambda (instance)
                                                         (map ::second (::methods instance)))
                                                       (old:class-instances program class))))
                                   (list-sort string<? (table-keys (::instances program)))))))

    ;; ---- Tables ----

    ;; A table's values, as texts in order.
    (: sorted-texts (impl (Fn (List String) -> (List String))))
    (define (sorted-texts texts)
      (list-sort string<? texts))

    ;; Each value by its name in the old expansion's names. An
    ;; implementation is not compared by whether it is a function, which
    ;; the old expander marks a dispatched one and the adapter none, and
    ;; which is read only of a value a program names; a signature is
    ;; compared by its place.
    (: value-texts (impl (Fn (Table String) (Table Bool) old:Program -> (List String))))
    (define (value-texts renaming implementations program)
      (list-sort string<?
                 (map (lambda (name)
                        (let ((old-name (renamed renaming name)))
                          (form-text (name-text old-name)
                                     (list (adapted-value-text
                                            (match (table-ref implementations old-name)
                                              ((Some _) #t)
                                              ((None) #f))
                                            (table-ref (::values program) name))))))
                      (table-keys (::values program)))))

    (: adapted-value-text (impl (Fn Bool (Option old:Value) -> String)))
    (define (adapted-value-text implementation? value)
      (match value
        ((Some (old:Defined scheme signature function?))
         (form-text (normal-value-text
                     (old:Defined scheme signature (and function? (not implementation?))))
                    (match signature
                      ((Some loc) (list (old-loc-text loc)))
                      ((None) (Nil)))))
        ((Some other) (normal-value-text other))
        ((None) "none")))

    ;; Each class's instances in order, the classes by name: each by its
    ;; name and its implementations', in the old expansion's names.
    (: instances-texts (impl (Fn (Table String) old:Program -> (List String))))
    (define (instances-texts renaming program)
      (let ((instances (normal-keys (::instances program))))
        (map (lambda (class)
               (form-text class
                          (map (lambda (instance)
                                 (form-text (name-text (renamed renaming (::name instance)))
                                            (list (normal-instance-text instance (Nil))
                                                  (form-text ""
                                                             (map (lambda (method)
                                                                    (name-text
                                                                     (renamed renaming
                                                                              (::second method))))
                                                                  (::methods instance))))))
                               (match (table-ref instances class)
                                 ((Some found) found)
                                 ((None) (Nil))))))
             (list-sort string<? (table-keys instances)))))

    ;; ---- Runs ----

    ;; The libraries that record a run, each with its count, in program
    ;; order; then, library by library, each item of its run, in order:
    ;; `ours` are the adapted program's, `theirs` the old expansion's,
    ;; expanded, or `checked?`.
    (: runs-differences
       (impl (Fn (Table String)
                 Bool
                 (List (Pair String (List old:Item)))
                 (List (Pair String (List old:Item)))
                 ->
                 (List String))))
    (define (runs-differences renaming checked? ours theirs)
      (match (ordered-difference "the runs" (map run-text ours) (map run-text theirs))
        ((Nil)
         (concatenate
          (map (lambda (pair)
                 (ordered-difference (string-append (::first (::first pair)) ": the items")
                                     (map (lambda (item) (item-text renaming checked? item))
                                          (::second (::first pair)))
                                     (map (lambda (item) (item-text empty-table checked? item))
                                          (::second (::second pair)))))
               (zip ours theirs))))
        (found found)))

    (: run-text (impl (Fn (Pair String (List old:Item)) -> String)))
    (define (run-text run)
      (string-append (::first run) " " (i64->string (length (::second run)))))

    ;; ---- Checked programs ----

    ;; The old checker on the adapted program and on the old expansion's.
    ;; Both succeed or both fail. Failures are compared by every problem,
    ;; message and place, in order, as the checker writes them, so a name
    ;; the adapted program makes afresh shows where a message spells it.
    ;; Successes are compared by each definition's scheme, and by each
    ;; checked item in the normal form, library by library, with each
    ;; node's place and type and each variable's instantiation, in the old
    ;; expansion's names. The program the checker hands on is the one it
    ;; was given, which the adapted comparison compares.
    (: check-comparison
       (impl (Fn (Table String) old:Program old:Program -> (Pair String String))))
    (define (check-comparison renaming new old)
      (match (Pair (old:compiling (lambda () (old:check-program new)))
                   (old:compiling (lambda () (old:check-program old))))
        ((Pair (Ok ours) (Ok theirs)) (typed-comparison renaming ours theirs))
        ((Pair (Err (old:Failed ours)) (Err (old:Failed theirs)))
         (check-failures (old:diagnostics->list ours) (old:diagnostics->list theirs)))
        ((Pair (Err stop) (Ok _)) (Pair "only the adapted fails" (stop-text stop)))
        ((Pair (Ok _) (Err stop)) (Pair "only the old fails" (stop-text stop)))
        (_ (Pair "not compared" "the checker asks for an input"))))

    (: check-failures
       (impl (Fn (List old:SourceDiagnostic) (List old:SourceDiagnostic) -> (Pair String String))))
    (define (check-failures ours theirs)
      (let ((new (map old-problem-text ours))
            (old (map old-problem-text theirs)))
        (if (same-texts? new old)
            (Pair "fail alike" (string-join old " | "))
            (Pair "fail differently"
                  (string-append "adapted: "
                                 (string-join new " | ")
                                 "; old: "
                                 (string-join old " | "))))))

    (: stop-text (impl (Fn old:Stop -> String)))
    (define (stop-text stop)
      (match stop
        ((old:Failed diagnostics)
         (string-join (map old-problem-text (old:diagnostics->list diagnostics)) " | "))
        ((old:Requested _) "the checker asks for an input")))

    ;; Each library's checked items are the run of its items the checker
    ;; answers, which the program's runs divide.
    (: typed-comparison (impl (Fn (Table String) old:Typed old:Typed -> (Pair String String))))
    (define (typed-comparison renaming ours theirs)
      (match (concatenate
              (list (ordered-difference "the schemes"
                                        (scheme-texts renaming (::schemes ours))
                                        (scheme-texts empty-table (::schemes theirs)))
                    (runs-differences renaming
                                      #t
                                      (old:library-items (::program ours) (::items ours))
                                      (old:library-items (::program theirs) (::items theirs)))))
        ((Nil) (Pair "check alike" ""))
        (found (Pair "checks differ" (string-join found "; ")))))

    ;; Each definition's scheme, by its name in the old expansion's names.
    (: scheme-texts (impl (Fn (Table String) (Table old:Scheme) -> (List String))))
    (define (scheme-texts renaming schemes)
      (list-sort string<?
                 (map (lambda (name)
                        (form-text (name-text (renamed renaming name))
                                   (list (match (table-ref schemes name)
                                           ((Some scheme) (checked-scheme-text renaming scheme))
                                           ((None) "none")))))
                      (table-keys schemes))))

    ;; ---- Links and TypeIds ----

    (: adapted-links-text (impl (Fn AdaptedLibrary -> String)))
    (define (adapted-links-text library)
      (form-text (::key library) (map linked-text (::links library))))

    ;; The files each library the old expansion records links, in program
    ;; order.
    (: old-links-texts (impl (Fn old:ExpandedProgram -> (List String))))
    (define (old-links-texts expanded)
      (map (lambda (run)
             (form-text (::first run) (map linked-text (old:library-links expanded (::first run)))))
           (reverse (::libraries (::program expanded)))))

    (: linked-text (impl (Fn old:LinkedFile -> String)))
    (define (linked-text linked)
      (string-append (::digest linked) "@" (::path linked)))

    ;; Each case's TypeId as the old compiler computes it of the adapted
    ;; program, beside the one `declare` writes, which knows every library
    ;; compiled.
    (: type-id-differences (impl (Fn (List CompiledFile) old:Program -> (List String))))
    (define (type-id-differences files program)
      (concatenate
       (map (lambda (file)
              (let ((known (Known (::library file)
                                  (Scanned empty-table empty-table)
                                  (::declarations file)
                                  (map ::declarations files))))
                (concatenate
                 (map (lambda (data)
                        (concatenate
                         (map (lambda (case) (type-id-difference known program data case))
                              (::cases data))))
                      (tops-data (library-tops (::dispatched file)))))))
            files)))

    (: type-id-difference (impl (Fn Known old:Program Data DataCase -> (List String))))
    (define (type-id-difference known program data case)
      (let ((name (old-name (::global case)))
            (id (case-type-id known data case)))
        (match (adapted-case program (old-name (::global data)) name)
          ((Some found)
           (if (= (old:case-type-id program found) id)
               (Nil)
               (list (string-append "the TypeId of " name " differs: declared "
                                    (i64->string id)
                                    "; old "
                                    (i64->string (old:case-type-id program found))))))
          ((None) (list (string-append "the adapted program holds no case " name))))))

    (: adapted-case (impl (Fn old:Program String String -> (Option old:Case))))
    (define (adapted-case program data name)
      (match (table-ref (::types program) data)
        ((Some found) (find (lambda (case) (string=? (::name case) name)) (::cases found)))
        ((None) (None))))

    ;; ---- Old definitions ----

    (: old-definitions (impl (Fn (List old:Item) -> (List (Pair String String)))))
    (define (old-definitions items)
      (concatenate (map (lambda (item)
                          (match item
                            ((old:Define name value)
                             (list (Pair (name-text name)
                                         (::text (old-text empty-table value (Naming (Nil) 0))))))
                            (_ (Nil))))
                        items)))

    ))
