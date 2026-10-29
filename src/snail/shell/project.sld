;; Inert project descriptions to typed build and run targets. The compiler's
;; reader supplies locations on both hosts; this module never reads a file,
;; evaluates a form or discovers an artifact dependency. Build declarations are
;; collected first, so a run may precede the program it references.
(define-library (snail shell project)
  (export
   Project
   Project-builds
   Project-runs
   ProjectPath
   ProjectPath-text
   ProjectPath-loc
   BuildTarget
   ProgramTarget
   BrowserTarget
   ProgramBuild
   ProgramBuild-name
   ProgramBuild-entry
   ProgramBuild-libraries
   ProgramBuild-loc
   BrowserBuild
   BrowserBuild-name
   BrowserBuild-entry
   BrowserBuild-libraries
   BrowserBuild-public
   BrowserBuild-loc
   RunTarget
   RunTarget-name
   RunTarget-program
   RunTarget-arguments
   RunTarget-loc
   target-name
   target-loc
   find-target
   parse-project)
  (import
   (snail core base)
   (snail shell compiler read))
  (begin

    ;; ---- Descriptions ----

    (struct Project
      ((builds (List BuildTarget))
       (runs (List RunTarget))))

    ;; A nonempty project-relative path, with no escaping or empty components.
    ;; The spelling "." is allowed for a directory, but not an entry file.
    (struct ProjectPath
      ((text String)
       (loc Loc)))

    (struct ProgramBuild
      ((name String)
       (entry ProjectPath)
       (libraries (List ProjectPath))
       (loc Loc)))

    (struct BrowserBuild
      ((name String)
       (entry ProjectPath)
       (libraries (List ProjectPath))
       (public (Option ProjectPath))
       (loc Loc)))

    (enum BuildTarget
      (ProgramTarget ((program ProgramBuild)))
      (BrowserTarget ((browser BrowserBuild))))

    ;; A resolved run contains a program, never a browser or unchecked name.
    (struct RunTarget
      ((name String)
       (program ProgramBuild)
       (arguments (List String))
       (loc Loc)))

    (: target-name (-> BuildTarget String))
    (define (target-name target)
      (match target
        ((ProgramTarget program) (ProgramBuild-name program))
        ((BrowserTarget browser) (BrowserBuild-name browser))))

    (: target-loc (-> BuildTarget Loc))
    (define (target-loc target)
      (match target
        ((ProgramTarget program) (ProgramBuild-loc program))
        ((BrowserTarget browser) (BrowserBuild-loc browser))))

    (: find-target (-> (List BuildTarget) String (Option BuildTarget)))
    (define (find-target builds name)
      (find (lambda (build) (string=? (target-name build) name)) builds))

    ;; ---- Literal names and paths ----

    (: path-character? (-> Char Bool))
    (define (path-character? c)
      (and (not (= (char->integer c) 0)) (not (char=? c #\\)) (not (char=? c #\:))))

    ;; Names under `.snail-` belong to the toolchain's own build targets.
    (: reserved-name? (-> String Bool))
    (define (reserved-name? name)
      (let ((prefix ".snail-"))
        (and (>= (string-length name) (string-length prefix))
             (string=? (substring name 0 (string-length prefix)) prefix))))

    (: parse-name (-> Syntax String ! compile))
    (define (parse-name syntax)
      (match syntax
        ((Ident name _ loc)
         (if (and (not (string=? name ".."))
                  (not (reserved-name? name))
                  (every? (lambda (c) (and (path-character? c) (not (char=? c #\/))))
                          (string->list name)))
             name
             (compile-error loc
                            "a target name must be one path component outside the reserved .snail-* names")))
        (_ (compile-error (syntax-loc syntax) "expected a literal target name"))))

    (: literal-string (-> Syntax String ! compile))
    (define (literal-string syntax)
      (match syntax
        ((Atom (DString text) _) text)
        (_ (compile-error (syntax-loc syntax) "expected a literal string"))))

    (: literal-list (-> Syntax (List Syntax) ! compile))
    (define (literal-list syntax)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) "expected a literal list"))))

    (: path-components? (-> String Bool))
    (define (path-components? text)
      (let loop ((start 0) (end 0))
        (if (or (= end (string-length text)) (char=? (string-ref text end) #\/))
            (let ((part (substring text start end)))
              (and (> (string-length part) 0) (not (string=? part ".")) (not (string=? part ".."))
                   (or (= end (string-length text)) (loop (+ end 1) (+ end 1)))))
            (loop start (+ end 1)))))

    (: parse-path (-> Syntax ProjectPath ! compile))
    (define (parse-path syntax)
      (let ((text (literal-string syntax)) (loc (syntax-loc syntax)))
        (unless (and (> (string-length text) 0)
                     (every? path-character? (string->list text))
                     (or (string=? text ".") (path-components? text)))
          (compile-error loc
                         "expected a project-relative path using /, without empty, . or .. components, backslash, colon or NUL"))
        (ProjectPath text loc)))

    (: entry-path (-> Syntax ProjectPath ! compile))
    (define (entry-path syntax)
      (let ((path (parse-path syntax)))
        (when (string=? (ProjectPath-text path) ".")
          (compile-error (ProjectPath-loc path)
                         "an entry must name a file, not the project directory"))
        path))

    ;; ---- Build options ----

    (: duplicate (All (A) (-> String String Loc Loc A ! compile)))
    (define (duplicate kind name here previous)
      (compile-error here
                     (string-append "duplicate "
                                    kind
                                    " "
                                    name
                                    "; first declared at "
                                    (loc->string previous))))

    (: unique-field (All (T) (requires (Copy T)) (-> String Loc (Option T) T (Option T) ! compile)))
    (define (unique-field name loc previous value)
      (match previous
        ((Some _) (compile-error loc (string-append "duplicate option " name)))
        ((None) (Some value))))

    (: build-fields (-> Bool String Loc (List Syntax) BuildTarget ! compile))
    (define (build-fields browser? name declaration forms)
      (let loop ((forms forms) (entry (ann (None) (Option ProjectPath)))
                 (libraries (ann (None) (Option (List ProjectPath))))
                 (public (ann (None) (Option ProjectPath))))
        (match forms
          ((Nil)
           (match entry
             ((None) (compile-error declaration "a build target requires an entry"))
             ((Some path)
              (let ((roots (match libraries ((Some paths) paths) ((None) (Nil)))))
                (if browser?
                    (BrowserTarget (BrowserBuild name path roots public declaration))
                    (ProgramTarget (ProgramBuild name path roots declaration)))))))
          ((Cons form rest)
           (match form
             ((Form (Cons (Ident key _ _) (Cons value (Nil))) loc)
              (cond
               ((string=? key "entry")
                (loop rest (unique-field key loc entry (entry-path value)) libraries public))
               ((string=? key "library-roots")
                (loop rest
                      entry
                      (unique-field key loc libraries (map parse-path (literal-list value)))
                      public))
               ((and browser? (string=? key "public"))
                (loop rest entry libraries (unique-field key loc public (parse-path value))))
               (else (compile-error loc (string-append "unknown build option " key)))))
             (_ (compile-error (syntax-loc form) "expected a (key value) build option")))))))

    (: parse-build (-> String Syntax Loc BuildTarget ! compile))
    (define (parse-build name syntax declaration)
      (match syntax
        ((Form (Cons (Ident kind _ _) forms) loc)
         (unless (or (string=? kind "program") (string=? kind "browser"))
           (compile-error loc (string-append "unknown build kind " kind)))
         (build-fields (string=? kind "browser") name declaration forms))
        (_ (compile-error (syntax-loc syntax) "expected a program or browser build form"))))

    ;; ---- Runs and declarations ----

    (: run-arguments (-> (List Syntax) (List String) ! compile))
    (define (run-arguments forms)
      (let loop ((forms forms) (arguments (ann (None) (Option (List String)))))
        (match forms
          ((Nil) (match arguments ((Some values) values) ((None) (Nil))))
          ((Cons (Form (Cons (Ident "args" _ _) (Cons value (Nil))) loc) rest)
           (loop rest
                 (unique-field "args" loc arguments (map literal-string (literal-list value)))))
          ((Cons form _) (compile-error (syntax-loc form) "expected (args (STRING ...))")))))

    (: resolve-program (-> (List BuildTarget) Syntax ProgramBuild ! compile))
    (define (resolve-program builds syntax)
      (let ((name (parse-name syntax)) (loc (syntax-loc syntax)))
        (match (find-target builds name)
          ((Some (ProgramTarget program)) program)
          ((Some (BrowserTarget _))
           (compile-error loc "a run target must reference a program build"))
          ((None) (compile-error loc (string-append "unknown build target " name))))))

    (: parse-run (-> (List BuildTarget) String Syntax Loc RunTarget ! compile))
    (define (parse-run builds name syntax declaration)
      (match syntax
        ((Form (Cons (Ident "run" _ _) (Cons target forms)) _)
         (RunTarget name (resolve-program builds target) (run-arguments forms) declaration))
        (_ (compile-error (syntax-loc syntax) "expected (run BUILD-NAME (args (STRING ...)))"))))

    ;; The reader's syntax already retains forward references. Collect builds,
    ;; then resolve runs directly; no second declaration tree is needed.
    (: collect-builds (-> (List Syntax) (List BuildTarget) ! compile))
    (define (collect-builds declarations)
      (let loop ((rest declarations) (builds (ann (Nil) (List BuildTarget))))
        (match rest
          ((Nil) (reverse builds))
          ((Cons (Form (Cons (Ident "build-target" _ _) (Cons name (Cons build (Nil)))) loc) tail)
           (let ((target (parse-build (parse-name name) build loc)))
             (match (find-target builds (target-name target))
               ((Some previous)
                (duplicate "build target" (target-name target) loc (target-loc previous)))
               ((None) (loop tail (Cons target builds))))))
          ((Cons (Form (Cons (Ident "run-target" _ _) _) _) tail) (loop tail builds))
          ((Cons form _)
           (compile-error (syntax-loc form) "expected a build-target or run-target declaration")))))

    (: collect-runs (-> (List Syntax) (List BuildTarget) (List RunTarget) ! compile))
    (define (collect-runs declarations builds)
      (let loop ((rest declarations) (runs (ann (Nil) (List RunTarget))))
        (match rest
          ((Nil) (reverse runs))
          ((Cons (Form (Cons (Ident "build-target" _ _) _) _) tail) (loop tail runs))
          ((Cons (Form (Cons (Ident "run-target" _ _) (Cons name (Cons run (Nil)))) loc) tail)
           (let ((target (parse-run builds (parse-name name) run loc)))
             (match (find (lambda (previous)
                            (string=? (RunTarget-name previous) (RunTarget-name target)))
                          runs)
               ((Some previous)
                (duplicate "run target" (RunTarget-name target) loc (RunTarget-loc previous)))
               ((None) (loop tail (Cons target runs))))))
          ((Cons form _) (compile-error (syntax-loc form) "expected a run-target declaration")))))

    (: parse-project (-> String String Project ! compile))
    (define (parse-project text file)
      (match (read-text text file)
        ((Cons (Form declarations _) (Nil))
         (let ((builds (collect-builds declarations)))
           (Project builds (collect-runs declarations builds))))
        ((Cons _ (Cons extra _))
         (compile-error (syntax-loc extra) "a project description must contain exactly one list"))
        ((Cons form _)
         (compile-error (syntax-loc form) "a project description must contain exactly one list"))
        ((Nil) (compile-error (Loc file 1 1) "expected a project description list"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-project)
    (import
     (only (scheme base) car cdr)
     (only (chibi string) string-contains)
     (snail stage0 testing))
    (begin
      (define (project-error text)
        (or (compile-failure (lambda () (parse-project text "project.datum"))) "accepted"))

      (define (test-project)
        (let* ((text
                "((run-target dev (run server (args (\"\" \"--port\" \"8080\")))) (run-target check (run server))\n(build-target client (browser (entry \"client.sld\") (public \"public\")))\n(build-target server (program (library-roots (\".\" \"src\")) (entry \"missing.sld\"))))")
               (project (parse-project text "project.datum"))
               (run (car (Project-runs project)))
               (round-trip (syntax->string (car (read-text text "project.datum")))))
          (expect (map target-name (Project-builds project)) '("client" "server"))
          (expect (map RunTarget-name (Project-runs project)) '("dev" "check"))
          (expect (RunTarget-arguments run) '("" "--port" "8080"))
          (expect (ProgramBuild-name (RunTarget-program run)) "server")
          (expect (map ProjectPath-text (ProgramBuild-libraries (RunTarget-program run)))
                  '("." "src"))
          (expect (loc->string (ProgramBuild-loc (RunTarget-program run))) "project.datum:3:1")
          (match (car (Project-builds project))
            ((BrowserTarget browser)
             (expect (ProjectPath-text (BrowserBuild-entry browser)) "client.sld")
             (match (BrowserBuild-public browser)
               ((Some path) (expect (ProjectPath-text path) "public"))
               ((None) (expect "missing public directory" "public"))))
            (_ (expect "program" "browser")))
          (let ((printed (parse-project round-trip "printed.datum")))
            (expect (map target-name (Project-builds printed)) '("client" "server"))
            (expect (map RunTarget-name (Project-runs printed)) '("dev" "check"))
            (expect (RunTarget-arguments (car (Project-runs printed))) '("" "--port" "8080"))))
        (expect (Project-builds (parse-project "()" "project.datum")) '())
        (let* ((project
                (parse-project
                 "((run-target check (run café.v2 (args ()))) (build-target café.v2 (program (entry \"missing.sld\") (library-roots ()))))"
                 "project.datum"))
               (run (car (Project-runs project))))
          (expect (ProgramBuild-name (RunTarget-program run)) "café.v2")
          (expect (RunTarget-arguments run) '())
          (expect (ProgramBuild-libraries (RunTarget-program run)) '()))
        (expect (project-error "((run-target dev\n  (run missing)))")
                "project.datum:2:8: unknown build target missing")
        (expect (project-error "()\n()")
                "project.datum:2:1: a project description must contain exactly one list")
        (expect
         (project-error "((build-target a (program\n  (entry \"a.sld\")\n  (entry \"b.sld\"))))")
         "project.datum:3:3: duplicate option entry")
        (expect
         (project-error
          "((build-target a (program (entry \"a\")))\n (build-target a (program (entry \"b\"))))")
         "project.datum:2:2: duplicate build target a; first declared at project.datum:1:2")
        (for-each (lambda (entry)
                    (let ((actual (project-error (car entry))) (wanted (car (cdr entry))))
                      (expect (if (string-contains actual wanted) wanted actual) wanted)))
                  '(("() ()" "exactly one list")
                    ("((build-target x (program (entry)))" "unclosed list")
                    ("((build-target x (program (entry))))" "(key value)")
                    ("((build-target x (program (entry \"x\" \"y\"))))" "(key value)")
                    ("((build-target y (program (entry \"y\"))) (run-target x (run y (args (5)))))"
                     "expected a literal string")
                    ("((build-target y (program (entry \"y\"))) (run-target x (run y (args \"flat\"))))"
                     "expected a literal list")
                    ("((build-target x (program (entry \"x\") (library-roots \"src\"))))"
                     "expected a literal list")
                    ("((build-target x (program (entry \"x\") (library-roots \"src\" \"shared\"))))"
                     "(key value)")
                    ("((launch-target old (run y)))" "expected a build-target or run-target")
                    ("((init (run \"anything\")))" "expected a build-target")
                    ("((build-target ../bad (program (entry \"x\"))))" "one path component")
                    ("((build-target .snail-publish (program (entry \"x\"))))" "reserved .snail-*")
                    ("((build-target a:b (program (entry \"x\"))))" "one path component")
                    ("((build-target x (program)))" "requires an entry")
                    ("((build-target x (program (entry \"x\") (entry \"y\"))))"
                     "duplicate option entry")
                    ("((build-target x (program (entry \"x\") (library-roots ()) (library-roots ()))))"
                     "duplicate option library-roots")
                    ("((build-target x (browser (entry \"x\") (public \"a\") (public \"b\"))))"
                     "duplicate option public")
                    ("((build-target x (program (entry \"x\") (public \"a\"))))"
                     "unknown build option public")
                    ("((build-target x (program (entry \"../x\"))))" "project-relative path")
                    ("((build-target x (program (entry \"/x\"))))" "project-relative path")
                    ("((build-target x (program (entry \"a//x\"))))" "project-relative path")
                    ("((build-target x (program (entry \".\"))))" "entry must name a file")
                    ("((build-target x (program (entry x))))" "expected a literal string")
                    ("((build-target x (program (entry \"x\"))) (build-target x (program (entry \"y\"))))"
                     "duplicate build target x")
                    ("((run-target x (run missing)))" "unknown build target missing")
                    ("((build-target x (browser (entry \"x\"))) (run-target y (run x)))"
                     "must reference a program")
                    ("((build-target y (program (entry \"y\"))) (run-target x (run y (args ()) (args ()))))"
                     "duplicate option args")
                    ("((build-target y (program (entry \"y\"))) (run-target x (run y)) (run-target x (run y)))"
                     "duplicate run target x")
                    ("((run-target x (shell \"echo hello\")))" "expected (run BUILD-NAME")
                    ("((build-target x (program (entry \"x\"))) . tail)"
                     "dotted lists are not part of Snail-Core"))))))
   (else)))
