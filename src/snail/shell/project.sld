;; Inert project descriptions to typed build and run targets. The compiler's
;; reader supplies locations on both hosts; this module never reads a file,
;; evaluates a form or discovers an artifact dependency. Build declarations are
;; collected first, so a run may precede the program it references.
(define-library (snail shell project)
  (export
   Project
   ProjectPath
   ProjectEntry
   SourceEntry
   ApplicationEntry
   BuildTarget
   ProgramTarget
   BrowserTarget
   ProgramBuild
   BrowserBuild
   RunTarget
   target-name
   target-loc
   find-target
   parse-project)
  (import
   (snail core base)
   (snail shell compiler read))
  (begin

    ;; ---- Descriptions ----

    (record Project
      ((builds (List BuildTarget))
       (runs (List RunTarget))))

    ;; A nonempty project-relative path, with no escaping or empty components.
    ;; The spelling "." is allowed for a directory, but not an entry file.
    (record ProjectPath
      ((text String)
       (loc Loc)))

    ;; A source program remains useful for scripts and compiler tooling.
    ;; An application entry selects an exported concrete type in a library.
    (enum ProjectEntry
      (SourceEntry ((path ProjectPath)))
      (ApplicationEntry
       ((library (List String))
        (name String))))

    (record ProgramBuild
      ((name String)
       (entry ProjectEntry)
       (libraries (List ProjectPath))
       (loc Loc)))

    (record BrowserBuild
      ((name String)
       (entry ProjectEntry)
       (libraries (List ProjectPath))
       (public (Option ProjectPath))
       (loc Loc)))

    (enum BuildTarget
      (ProgramTarget ((program ProgramBuild)))
      (BrowserTarget ((browser BrowserBuild))))

    ;; A resolved run contains a program, never a browser or unchecked name.
    (record RunTarget
      ((name String)
       (program ProgramBuild)
       (arguments (List String))
       (loc Loc)))

    (define (target-name (target BuildTarget)) (→ String)
      (match target
        ((ProgramTarget program) (● program name))
        ((BrowserTarget browser) (● browser name))))

    (define (target-loc (target BuildTarget)) (→ Loc)
      (match target
        ((ProgramTarget program) (● program loc))
        ((BrowserTarget browser) (● browser loc))))

    (define (find-target (builds (List BuildTarget)) (name String)) (→ (Option BuildTarget))
      (find (lambda (build) (string=? (target-name build) name)) builds))

    ;; ---- Literal names and paths ----

    (define (path-character? (c Char)) (→ Bool)
      (and (not (= (char->integer c) 0)) (not (char=? c #\\)) (not (char=? c #\:))))

    ;; Names under `.snail-` belong to the toolchain's own build targets.

    (define (reserved-name? (name String)) (→ Bool)
      (let ((prefix ".snail-"))
        (and (>= (string-length name) (string-length prefix))
             (string=? (substring name 0 (string-length prefix)) prefix))))

    (define (parse-name (syntax Syntax)) (→ String) (! compile)
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

    (define (literal-string (syntax Syntax)) (→ String) (! compile)
      (match syntax
        ((Atom (DString text) _) text)
        (_ (compile-error (syntax-loc syntax) "expected a literal string"))))

    (define (literal-list (syntax Syntax)) (→ (List Syntax)) (! compile)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) "expected a literal list"))))

    (define (path-components? (text String)) (→ Bool)
      (let loop ((start 0) (end 0))
        (if (or (= end (string-length text)) (char=? (string-ref text end) #\/))
            (let ((part (substring text start end)))
              (and (> (string-length part) 0) (not (string=? part ".")) (not (string=? part ".."))
                   (or (= end (string-length text)) (loop (+ end 1) (+ end 1)))))
            (loop start (+ end 1)))))

    (define (parse-path (syntax Syntax)) (→ ProjectPath) (! compile)
      (let ((text (literal-string syntax)) (loc (syntax-loc syntax)))
        (unless (and (> (string-length text) 0)
                     (every? path-character? (string->list text))
                     (or (string=? text ".") (path-components? text)))
          (compile-error loc
                         "expected a project-relative path using /, without empty, . or .. components, backslash, colon or NUL"))
        (new ProjectPath (text text) (loc loc))))

    (define (entry-path (syntax Syntax)) (→ ProjectPath) (! compile)
      (let ((path (parse-path syntax)))
        (when (string=? (● path text) ".")
          (compile-error (● path loc)
                         "an entry must name a file, not the project directory"))
        path))

    (define (parse-entry (syntax Syntax)) (→ ProjectEntry) (! compile)
      (match syntax
        ((Atom (DString _) _) (SourceEntry (entry-path syntax)))
        ((Form (Cons (Form (Cons part parts) _) (Cons name (Nil))) _)
         (ApplicationEntry (map parse-name (Cons part parts)) (parse-name name)))
        (_ (compile-error (syntax-loc syntax)
                          "expected an entry path string or ((library name) ApplicationType)"))))

    ;; ---- Build options ----

    (define (duplicate (kind String) (name String) (here Loc) (previous Loc))
      (→ A)
      (! compile)
      (∀ (A))
      (compile-error here
                     (string-append "duplicate "
                                    kind
                                    " "
                                    name
                                    "; first declared at "
                                    (loc->string previous))))

    (define (unique-field (name String) (loc Loc) (previous (Option T)) (value T))
      (→ (Option T))
      (! compile)
      (∀ (T))
      (match previous
        ((Some _) (compile-error loc (string-append "duplicate option " name)))
        ((None) (Some value))))

    (define (build-fields (browser? Bool) (name String) (declaration Loc) (forms (List Syntax)))
      (→ BuildTarget)
      (! compile)
      (let loop ((forms forms) (entry (ann (None) (Option ProjectEntry)))
                 (libraries (ann (None) (Option (List ProjectPath))))
                 (public (ann (None) (Option ProjectPath))))
        (match forms
          ((Nil)
           (match entry
             ((None) (compile-error declaration "a build target requires an entry"))
             ((Some path)
              (let ((roots (match libraries ((Some paths) paths) ((None) (Nil)))))
                (if browser?
                    (BrowserTarget (new BrowserBuild
                                     (name name)
                                     (entry path)
                                     (libraries roots)
                                     (public public)
                                     (loc declaration)))
                    (ProgramTarget (new ProgramBuild
                                     (name name)
                                     (entry path)
                                     (libraries roots)
                                     (loc declaration))))))))
          ((Cons form rest)
           (match form
             ((Form (Cons (Ident key _ _) (Cons value (Nil))) loc)
              (cond
               ((string=? key "entry")
                (loop rest (unique-field key loc entry (parse-entry value)) libraries public))
               ((string=? key "library-roots")
                (loop rest
                      entry
                      (unique-field key loc libraries (map parse-path (literal-list value)))
                      public))
               ((and browser? (string=? key "public"))
                (loop rest entry libraries (unique-field key loc public (parse-path value))))
               (else (compile-error loc (string-append "unknown build option " key)))))
             (_ (compile-error (syntax-loc form) "expected a (key value) build option")))))))

    (define (parse-build (name String) (syntax Syntax) (declaration Loc))
      (→ BuildTarget)
      (! compile)
      (match syntax
        ((Form (Cons (Ident kind _ _) forms) loc)
         (unless (or (string=? kind "program") (string=? kind "browser"))
           (compile-error loc (string-append "unknown build kind " kind)))
         (build-fields (string=? kind "browser") name declaration forms))
        (_ (compile-error (syntax-loc syntax) "expected a program or browser build form"))))

    ;; ---- Runs and declarations ----

    (define (run-arguments (forms (List Syntax))) (→ (List String)) (! compile)
      (let loop ((forms forms) (arguments (ann (None) (Option (List String)))))
        (match forms
          ((Nil) (match arguments ((Some values) values) ((None) (Nil))))
          ((Cons (Form (Cons (Ident "args" _ _) (Cons value (Nil))) loc) rest)
           (loop rest
                 (unique-field "args" loc arguments (map literal-string (literal-list value)))))
          ((Cons form _) (compile-error (syntax-loc form) "expected (args (STRING ...))")))))

    (define (resolve-program (builds (List BuildTarget)) (syntax Syntax))
      (→ ProgramBuild)
      (! compile)
      (let ((name (parse-name syntax)) (loc (syntax-loc syntax)))
        (match (find-target builds name)
          ((Some (ProgramTarget program)) program)
          ((Some (BrowserTarget _))
           (compile-error loc "a run target must reference a program build"))
          ((None) (compile-error loc (string-append "unknown build target " name))))))

    (define (parse-run (builds (List BuildTarget)) (name String) (syntax Syntax) (declaration Loc))
      (→ RunTarget)
      (! compile)
      (match syntax
        ((Form (Cons (Ident "run" _ _) (Cons target forms)) _)
         (new RunTarget
           (name name)
           (program (resolve-program builds target))
           (arguments (run-arguments forms))
           (loc declaration)))
        (_ (compile-error (syntax-loc syntax) "expected (run BUILD-NAME (args (STRING ...)))"))))

    ;; The reader's syntax already retains forward references. Collect builds,
    ;; then resolve runs directly; no second declaration tree is needed.

    (define (collect-builds (declarations (List Syntax))) (→ (List BuildTarget)) (! compile)
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

    (define (collect-runs (declarations (List Syntax)) (builds (List BuildTarget)))
      (→ (List RunTarget))
      (! compile)
      (let loop ((rest declarations) (runs (ann (Nil) (List RunTarget))))
        (match rest
          ((Nil) (reverse runs))
          ((Cons (Form (Cons (Ident "build-target" _ _) _) _) tail) (loop tail runs))
          ((Cons (Form (Cons (Ident "run-target" _ _) (Cons name (Cons run (Nil)))) loc) tail)
           (let ((target (parse-run builds (parse-name name) run loc)))
             (match (find (lambda (previous)
                            (string=? (● previous name) (● target name)))
                          runs)
               ((Some previous)
                (duplicate "run target" (● target name) loc (● previous loc)))
               ((None) (loop tail (Cons target runs))))))
          ((Cons form _) (compile-error (syntax-loc form) "expected a run-target declaration")))))

    (define (parse-project (text String) (file String)) (→ Project) (! compile)
      (match (read-text text file)
        ((Cons (Form declarations _) (Nil))
         (let ((builds (collect-builds declarations)))
           (new Project (builds builds) (runs (collect-runs declarations builds)))))
        ((Cons _ (Cons extra _))
         (compile-error (syntax-loc extra) "a project description must contain exactly one list"))
        ((Cons form _)
         (compile-error (syntax-loc form) "a project description must contain exactly one list"))
        ((Nil)
         (compile-error (new Loc (file file) (line 1) (column 1))
                        "expected a project description list"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-project)
    (import
     (only (chezscheme) car cdr)
     (only (snail stage0 system) string-contains)
     (snail stage0 testing))
    (begin
      (define project-error
        (lambda (text)
          (or (compile-failure (lambda () (parse-project text "project.datum"))) "accepted")))

      (define test-project
        (lambda () (let* ((text
                           "((run-target dev (run server (args (\"\" \"--port\" \"8080\")))) (run-target check (run server))\n(build-target client (browser (entry \"client.sld\") (public \"public\")))\n(build-target server (program (library-roots (\".\" \"src\")) (entry \"missing.sld\"))))")
                          (project (parse-project text "project.datum"))
                          (run (car (● project runs)))
                          (round-trip (syntax->string (car (read-text text "project.datum")))))
                     (expect (map target-name (● project builds)) '("client" "server"))
                     (expect (map (lambda (record) (● record name)) (● project runs))
                             '("dev" "check"))
                     (expect (● run arguments) '("" "--port" "8080"))
                     (expect (● (● run program) name) "server")
                     (expect (map (lambda (record) (● record text)) (● (● run program) libraries))
                             '("." "src"))
                     (expect (loc->string (● (● run program) loc)) "project.datum:3:1")
                     (match (car (● project builds))
                       ((BrowserTarget browser)
                        (match (● browser entry)
                          ((SourceEntry path) (expect (● path text) "client.sld"))
                          (_ (expect "application" "source")))
                        (match (● browser public)
                          ((Some path) (expect (● path text) "public"))
                          ((None) (expect "missing public directory" "public"))))
                       (_ (expect "program" "browser")))
                     (let ((printed (parse-project round-trip "printed.datum")))
                       (expect (map target-name (● printed builds)) '("client" "server"))
                       (expect (map (lambda (record) (● record name)) (● printed runs))
                               '("dev" "check"))
                       (expect (● (car (● printed runs)) arguments) '("" "--port" "8080"))))
                (match (car (● (parse-project
                                "((build-target app (program (entry ((example output-port) Printer)))))"
                                "typed.datum") builds))
                  ((ProgramTarget program)
                   (match (● program entry)
                     ((ApplicationEntry library name)
                      (expect library '("example" "output-port"))
                      (expect name "Printer"))
                     (_ (expect "source" "application"))))
                  (_ (expect "missing application" "application")))
                (expect (● (parse-project "()" "project.datum") builds) '())
                (let* ((project
                        (parse-project
                         "((run-target check (run café.v2 (args ()))) (build-target café.v2 (program (entry \"missing.sld\") (library-roots ()))))"
                         "project.datum"))
                       (run (car (● project runs))))
                  (expect (● (● run program) name) "café.v2")
                  (expect (● run arguments) '())
                  (expect (● (● run program) libraries) '()))
                (expect (project-error "((run-target dev\n  (run missing)))")
                        "project.datum:2:8: unknown build target missing")
                (expect (project-error "()\n()")
                        "project.datum:2:1: a project description must contain exactly one list")
                (expect
                 (project-error
                  "((build-target a (program\n  (entry \"a.sld\")\n  (entry \"b.sld\"))))")
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
                            ("((launch-target old (run y)))"
                             "expected a build-target or run-target")
                            ("((init (run \"anything\")))" "expected a build-target")
                            ("((build-target ../bad (program (entry \"x\"))))" "one path component")
                            ("((build-target .snail-publish (program (entry \"x\"))))"
                             "reserved .snail-*")
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
                            ("((build-target x (program (entry \"../x\"))))"
                             "project-relative path")
                            ("((build-target x (program (entry \"/x\"))))" "project-relative path")
                            ("((build-target x (program (entry \"a//x\"))))"
                             "project-relative path")
                            ("((build-target x (program (entry \".\"))))" "entry must name a file")
                            ("((build-target x (program (entry x))))"
                             "expected an entry path string")
                            ("((build-target x (program (entry (() App)))))"
                             "expected an entry path string")
                            ("((build-target x (program (entry ((a b) (Generic I64))))))"
                             "literal target name")
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
                             "dotted lists are not part of Snail Scheme")))))))
   (else)))
