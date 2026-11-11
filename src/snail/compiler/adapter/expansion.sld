;; Whole programs expanded by the pass `expand` beside the old expander,
;; which tests/compare-compiler.sld runs, compiled, over the suites'
;; programs that load completely. Both succeed or both fail. When both
;; fail, the first problem each reports is compared, message and place;
;; the old expander reports several when several bodies fail, and those
;; programs are named apart, with whether every problem agrees. When both
;; succeed, each library the old expansion records is compared: the names
;; it exports, in order; its written top-level definitions, in order; and
;; each one's value in a normal form, as is a program's body; and what
;; the queries over Expanded answer, the files it links, the targets it
;; asks for and whether it derives, beside what the old expansion
;; records of the same.
;;
;; The normal form is a text in which each local is numbered in the order
;; it is bound, each macro-written global is its name marked as written
;; by an expansion, without the expansion's number, and each field
;; function is its name. It leaves out types, whether a function may
;; capture, a local signature that annotates no definition, instance
;; methods and effect defaults, which the old expander names afresh, and
;; statements of a library. Where the old expander resolves what `declare`
;; or `bind` will, the two are made alike: an `artifact-files` form is its
;; `empty`, as the old expander writes it for a target with no files, and
;; a linked file is its path. A `case-id` is the old expander's case
;; number, which only `declare` knows, so it differs, and is reported.
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
   (snail compiler expand language)
   (snail compiler expand offer)
   (snail compiler expand links)
   (snail compiler expand targets)
   (snail compiler expand derives)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate expand)
   (only (snail compiler adapter outline) feedback-text)
   (only (snail compiler adapter load) old-expansion)
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
                 library-items
                 program-items)
           old:)
   (prefix (only (snail shell compiler expand) ExpandedProgram) old:))
  (begin

    ;; ---- Programs ----

    ;; What the program at `path` finds: a kind, and what it says.
    (: expansion-comparison
       (impl (Fn (List String) String -> (Pair String String) ! fs)))
    (define (expansion-comparison directories path)
      (match (load-program directories path)
        ((Err feedback)
         (Pair "not compared" (string-append "it does not load: " (feedback-text feedback))))
        ((Ok loaded)
         (match (expand-loaded directories loaded)
           ((Ok (WaitingFor _)) (Pair "not compared" "it reaches a generated library"))
           (new (outcomes new (old-expansion directories path)))))))

    (: outcomes
       (impl (Fn (Result ProgramExpansion (List Feedback))
                 (Result old:ExpandedProgram old:Stop)
                 ->
                 (Pair String String))))
    (define (outcomes new old)
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
        ((Pair (Ok (ExpandedAll files)) (Ok expanded)) (expansions-comparison files expanded))
        ((Pair (Ok (WaitingFor _)) _) (Pair "not compared" "it reaches a generated library"))))

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
       (impl (Fn (List ExpandedFile) old:ExpandedProgram -> (Pair String String))))
    (define (expansions-comparison files expanded)
      (let* ((program (::program expanded))
             (old-libraries (old:library-items program (old:program-items program)))
             (differences (concatenate
                           (map (lambda (file)
                                  (match (find (lambda (entry)
                                                 (string=? (::first entry) (file-key file)))
                                               old-libraries)
                                    ((Some entry)
                                     (append (library-differences file
                                                                  (::second entry)
                                                                  (old-exports expanded
                                                                               (::first entry)))
                                             (query-differences file expanded)))
                                    ((None) (Nil))))
                                files))))
        (match (append (order-difference files old-libraries) differences)
          ((Nil) (Pair "expand alike" ""))
          (found (Pair "expansions differ" (string-join found "; "))))))

    ;; The libraries come in the old expansion's order, the implicit
    ;; libraries of a deriving clause among them, but for the primitive
    ;; library, which the old expansion never lists.
    (: order-difference
       (impl (Fn (List ExpandedFile) (List (Pair String (List old:Item))) -> (List String))))
    (define (order-difference files old-libraries)
      (let ((new (filter (lambda (key) (not (string=? key "snail.core.primitive")))
                         (map file-key files)))
            (old (map ::first old-libraries)))
        (if (same-texts? new old)
            (Nil)
            (list (string-append "the order differs: new " (string-join new " ")
                                 "; old " (string-join old " "))))))

    (: file-key (impl (Fn ExpandedFile -> String)))
    (define (file-key file)
      (library-key (::library file)))

    (: old-exports (impl (Fn old:ExpandedProgram String -> (List String))))
    (define (old-exports expanded key)
      (match (table-ref (::libraries expanded) key)
        ((Some entry) (map ::first (::exports entry)))
        ((None) (Nil))))

    ;; The files linked and the targets asked for, each once, in name
    ;; order, and whether the library derives.
    (: query-differences (impl (Fn ExpandedFile old:ExpandedProgram -> (List String))))
    (define (query-differences file expanded)
      (match (table-ref (::libraries expanded) (file-key file))
        ((Some entry)
         (let* ((library (::expanded (::expansion file)))
                (new (list (names-text (map linked-path (linked-files library)))
                           (names-text (requested-targets library))
                           (match (first-derivation library)
                             ((Some _) "derives")
                             ((None) "derives nothing"))))
                (old (list (names-text (map ::path (::links entry)))
                           (names-text (map ::name (::artifacts entry)))
                           (match (::derives entry)
                             ((Some _) "derives")
                             ((None) "derives nothing")))))
           (if (same-texts? new old)
               (Nil)
               (list (string-append (file-key file) ": queries differ: new " (string-join new ", ")
                                    "; old " (string-join old ", "))))))
        ((None) (Nil))))

    ;; A linked file's path beside the file that names it, as the old
    ;; expander records it.
    (: linked-path (impl (Fn Link -> String)))
    (define (linked-path link)
      (let ((file (string->list (::file (::written link)))))
        (string-append (match (list-index (lambda (char) (char=? char #\/)) (reverse file))
                         ((Some index) (list->string (take file (- (length file) index))))
                         ((None) ""))
                       (string-join (::path link) "/"))))

    (: names-text (impl (Fn (List String) -> String)))
    (define (names-text names)
      (string-append "("
                     (string-join (list-sort string<? (delete-duplicates string=? names)) " ")
                     ")"))

    (: library-differences
       (impl (Fn ExpandedFile (List old:Item) (List String) -> (List String))))
    (define (library-differences file items old-exported)
      (let* ((key (file-key file))
             (exported (map ::name (::exports (::offer (::expansion file)))))
             (new (written-definitions (::expanded (::expansion file))))
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
    ;; normal form; a program's body is `main:%body`, a function of
    ;; nothing.
    (: written-definitions (impl (Fn Expanded -> (List (Pair String String)))))
    (define (written-definitions expanded)
      (match expanded
        ((Defined _ tops _) (tops-definitions tops (Nil)))
        ((Program tops body)
         (append (tops-definitions tops (Nil))
                 (match body
                   ((Some expr)
                    (list (Pair "main:%body"
                                (::text
                                 (new-text (Lambda (Nil) expr (Loc "" 0 0)) (Naming (Nil) 0))))))
                   ((None) (Nil)))))))

    (: tops-definitions (impl (Fn (List Top) (List Global) -> (List (Pair String String)))))
    (define (tops-definitions tops sets)
      (concatenate (map (lambda (top) (top-definitions top sets)) tops)))

    ;; A definition under a top-level `with-instances` has its sets twice,
    ;; as the old expander scopes them.
    (: top-definitions (impl (Fn Top (List Global) -> (List (Pair String String)))))
    (define (top-definitions top sets)
      (match top
        ((Define global value _)
         (list (Pair (global-text global)
                     (::text (new-text (scoped (scoped value sets) sets) (Naming (Nil) 0))))))
        ((InstanceScope own tops _)
         (tops-definitions tops (delete-duplicates same-global-text? (append own sets))))
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

    (: top-value-text (impl (Fn TopValue -> String)))
    (define (top-value-text value)
      (match value
        ((TopGlobal global) (global-text global))
        ((FieldFunction case label role)
         (string-append (global-text case) "-" label (role-suffix role)))))

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
    (: new-texts (impl (Fn (List Expr) Naming -> (Pair (List String) Naming))))
    (define (new-texts exprs naming)
      (let loop ((exprs exprs)
                 (naming naming)
                 (texts (Nil)))
        (match exprs
          ((Nil) (Pair (reverse texts) naming))
          ((Cons expr rest)
           (let ((rendered (new-text expr naming)))
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

    (: new-text (impl (Fn Expr Naming -> Rendered)))
    (define (new-text expr naming)
      (match expr
        ((Literal constant _) (Rendered (constant-text constant) naming))
        ((LocalRef local _) (Rendered (named naming (local-key local)) naming))
        ((TopRef value _) (Rendered (top-value-text value) naming))
        ((Path (Cons label (Nil)) _) (Rendered (string-append "::" label) naming))
        ((Path labels _)
         (let ((parameter (bound naming "%path")))
           (Rendered (form-text "lambda"
                                (list (form-text (::text parameter) (Nil))
                                      (path-text labels (::text parameter))))
                     (::naming parameter))))
        ((PathApply labels record _)
         (let ((rendered (new-text record naming)))
           (Rendered (path-text labels (::text rendered)) (::naming rendered))))
        ((Lambda parameters body _) (lambda-text parameters body naming))
        ((ClosedLambda parameters body _) (lambda-text parameters body naming))
        ((Call callee arguments _) (sequence-text "call" (Cons callee arguments) naming))
        ((If test consequent alternative _)
         (sequence-text "if" (list test consequent alternative) naming))
        ((Seq first rest _) (sequence-text "seq" (list first rest) naming))
        ((Let local signature value body _)
         (let* ((binder (bound naming (local-key local)))
                (value-text (new-text value (::naming binder)))
                (body-text (new-text body (::naming value-text))))
           (Rendered (form-text "let"
                                (list (::text binder)
                                      (match signature
                                        ((Some _) (form-text "ann" (list (::text value-text))))
                                        ((None) (::text value-text)))
                                      (::text body-text)))
                     (::naming body-text))))
        ((LocalSignature _ body _) (new-text body naming))
        ((Match scrutinee clauses _)
         (let* ((value (new-text scrutinee naming))
                (rendered (clauses-text clauses (::naming value))))
           (Rendered (form-text "match" (Cons (::text value) (::first rendered)))
                     (::second rendered))))
        ((Handle effect implementations body _)
         (let* ((values (new-texts (map ::value implementations) naming))
                (body-text (new-text body (::second values))))
           (Rendered (form-text "handle"
                                (Cons (global-text effect)
                                      (append (map (lambda (pair)
                                                     (form-text (::first pair)
                                                                (list (::second pair))))
                                                   (zip (map (lambda (implementation)
                                                               (::name (::label implementation)))
                                                             implementations)
                                                        (::first values)))
                                              (list (::text body-text)))))
                     (::naming body-text))))
        ((WithInstances sets body _)
         (let ((rendered (new-text body naming)))
           (Rendered (form-text "with-instances"
                                (list (form-text "" (map global-text sets)) (::text rendered)))
                     (::naming rendered))))
        ((Ann value _ _) (wrapped-text "ann" value naming))
        ((Convert value _ _) (wrapped-text "convert" value naming))
        ((TryConvert value _ _) (wrapped-text "try-convert" value naming))
        ((TypeTest value _ _) (wrapped-text "type-test" value naming))
        ((CaseId constructor _ _)
         (Rendered (form-text "case-id" (list (top-value-text constructor))) naming))
        ((LinkedFile path _ _) (Rendered (form-text "link" (list (string-join path "/"))) naming))
        ((ArtifactFiles _ _ _ empty _) (new-text empty naming))))

    (: path-text (impl (Fn (List String) String -> String)))
    (define (path-text labels record)
      (fold-left (lambda (text label) (form-text "call" (list (string-append "::" label) text)))
                 record
                 labels))

    (: lambda-text (impl (Fn (List Local) Expr Naming -> Rendered)))
    (define (lambda-text parameters body naming)
      (let* ((binders (new-binders parameters naming))
             (rendered (new-text body (::second binders))))
        (Rendered (form-text "lambda" (list (form-text "" (::first binders)) (::text rendered)))
                  (::naming rendered))))

    (: sequence-text (impl (Fn String (List Expr) Naming -> Rendered)))
    (define (sequence-text head exprs naming)
      (let ((rendered (new-texts exprs naming)))
        (Rendered (form-text head (::first rendered)) (::second rendered))))

    (: wrapped-text (impl (Fn String Expr Naming -> Rendered)))
    (define (wrapped-text head value naming)
      (let ((rendered (new-text value naming)))
        (Rendered (form-text head (list (::text rendered))) (::naming rendered))))

    (: clauses-text (impl (Fn (List Clause) Naming -> (Pair (List String) Naming))))
    (define (clauses-text clauses naming)
      (let loop ((clauses clauses)
                 (naming naming)
                 (texts (Nil)))
        (match clauses
          ((Nil) (Pair (reverse texts) naming))
          ((Cons clause rest)
           (let* ((pattern (pattern-text (::pattern clause) naming))
                  (body (new-text (::body clause) (::naming pattern))))
             (loop rest
                   (::naming body)
                   (Cons (form-text (::text pattern) (list (::text body))) texts)))))))

    (: pattern-text (impl (Fn Pattern Naming -> Rendered)))
    (define (pattern-text pattern naming)
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
              (Rendered (form-text (top-value-text constructor) (reverse texts)) naming))
             ((Cons argument rest)
              (let ((rendered (pattern-text argument naming)))
                (loop rest (::naming rendered) (Cons (::text rendered) texts)))))))))

    (: constant-text (impl (Fn Constant -> String)))
    (define (constant-text constant)
      (match constant
        ((Integer value) (string-append "i:" (i64->string value)))
        ((Float text) (string-append "f:" text))
        ((Text text) (string-append "s:" text))
        ((Character char) (string-append "c:" (i64->string (char->integer char))))
        ((ByteVector bytes) (string-append "b:" (i64->string (vector-length bytes))))
        ((Boolean value) (if value "#t" "#f"))
        ((UnitValue) "unit")))

    (: datum-text (impl (Fn syntax-Datum -> String)))
    (define (datum-text datum)
      (match datum
        ((syntax-Integer value) (string-append "i:" (i64->string value)))
        ((syntax-Float text) (string-append "f:" text))
        ((syntax-Text text) (string-append "s:" text))
        ((syntax-Character char) (string-append "c:" (i64->string (char->integer char))))
        ((syntax-ByteVector bytes) (string-append "b:" (i64->string (vector-length bytes))))
        ((syntax-Boolean value) (if value "#t" "#f"))))

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

    ;; A name with `:` is a global, and any other a local.
    (: old-name-text (impl (Fn Naming String -> String)))
    (define (old-name-text naming name)
      (if (any? (lambda (char) (char=? char #\:)) (string->list name))
          (old-global-text name)
          (named naming name)))

    (: old-link (impl (Fn String -> (Option String))))
    (define (old-link name)
      (match (string-index-of name "%link ")
        ((Some index) (Some (substring name (+ index 6) (string-length name))))
        ((None) (None))))

    (: string-index-of (impl (Fn String String -> (Option I64))))
    (define (string-index-of text part)
      (let loop ((index 0))
        (cond ((> (+ index (string-length part)) (string-length text)) (None))
              ((string=? (substring text index (+ index (string-length part))) part) (Some index))
              (else (loop (+ index 1))))))

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
        ((old:App callee arguments)
         (match (Pair (::term callee) arguments)
           ((Pair (old:Var name _ _) (Nil))
            (match (old-link name)
              ((Some path) (Rendered (form-text "link" (list path)) naming))
              ((None) (old-sequence "call" (Cons callee arguments) naming))))
           (_ (old-sequence "call" (Cons callee arguments) naming))))
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
        ((old:Convert value _) (old-wrapped "convert" value naming))
        ((old:TryConvert value _) (old-wrapped "try-convert" value naming))
        ((old:TypeTest value _) (old-wrapped "type-test" value naming))))

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
        ((old:DBytes bytes) (string-append "b:" (i64->string (vector-length bytes))))
        ((old:DBool value) (if value "#t" "#f"))
        ((old:DUnit) "unit")))

    ))
