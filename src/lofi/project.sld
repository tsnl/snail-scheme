;; Inert project descriptions to typed build and launch targets. The compiler's
;; reader supplies locations on both hosts; this module never reads a file,
;; evaluates a form or discovers an artifact dependency. Launch references are
;; resolved after parsing, so they may precede their program's declaration.
(define-library (lofi project)
  (export
   Project
   Project-builds
   Project-launches
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
   LaunchTarget
   LaunchTarget-name
   LaunchTarget-program
   LaunchTarget-arguments
   LaunchTarget-loc
   target-name
   target-loc
   find-target
   parse-project)
  (import
   (lofi base)
   (lofi compiler read))
  (begin

    ;; ---- Descriptions ----

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

    ;; A resolved launch contains a program, never a browser or unchecked name.
    (struct LaunchTarget
      ((name String)
       (program ProgramBuild)
       (arguments (List String))
       (loc Loc)))

    (struct Project
      ((builds (List BuildTarget))
       (launches (List LaunchTarget))))

    (struct PendingLaunch
      ((name String)
       (build String)
       (reference Loc)
       (arguments (List String))
       (loc Loc)))

    (enum Declaration
      (BuildDeclaration ((target BuildTarget)))
      (LaunchDeclaration ((launch PendingLaunch))))

    (struct BuildOptions
      ((entry (Option ProjectPath))
       (libraries (List ProjectPath))
       (public (Option ProjectPath))))

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

    (: letter? (-> Char Bool))
    (define (letter? c)
      (or (and (not (char<? c #\a)) (not (char<? #\z c)))
          (and (not (char<? c #\A)) (not (char<? #\Z c)))))

    (: name-character? (-> Char Bool))
    (define (name-character? c)
      (or (letter? c) (char=? c #\_) (char=? c #\-)
          (and (not (char<? c #\0)) (not (char<? #\9 c)))))

    (: parse-name (-> Syntax String))
    (define (parse-name syntax)
      (match syntax
        ((Ident name _ loc)
         (if (and (> (string-length name) 0)
                  (or (letter? (string-ref name 0)) (char=? (string-ref name 0) #\_))
                  (every? name-character? (string->list name)))
             name
             (compile-error loc "a target name starts with a letter or _, followed by letters, digits, - or _")))
        (_ (compile-error (syntax-loc syntax) "expected a literal target name"))))

    (: literal-string (-> Syntax String))
    (define (literal-string syntax)
      (match syntax
        ((Atom (DString text) _) text)
        (_ (compile-error (syntax-loc syntax) "expected a literal string"))))

    (: path-components? (-> String Bool))
    (define (path-components? text)
      (let loop ((start 0) (end 0))
        (if (or (= end (string-length text)) (char=? (string-ref text end) #\/))
            (let ((part (substring text start end)))
              (and (> (string-length part) 0) (not (string=? part ".")) (not (string=? part ".."))
                   (or (= end (string-length text)) (loop (+ end 1) (+ end 1)))))
            (loop start (+ end 1)))))

    (: parse-path (-> Syntax ProjectPath))
    (define (parse-path syntax)
      (let ((text (literal-string syntax)) (loc (syntax-loc syntax)))
        (unless (and (> (string-length text) 0)
                     (every? (lambda (c) (and (not (= (char->integer c) 0)) (not (char=? c #\\)) (not (char=? c #\:))))
                             (string->list text))
                     (or (string=? text ".") (path-components? text)))
          (compile-error loc "expected a project-relative path using /, without empty, . or .. components, backslash, colon or NUL"))
        (ProjectPath text loc)))

    (: entry-path (-> Syntax ProjectPath))
    (define (entry-path syntax)
      (let ((path (parse-path syntax)))
        (when (string=? (ProjectPath-text path) ".")
          (compile-error (ProjectPath-loc path) "an entry must name a file, not the project directory"))
        path))

    ;; ---- Build options ----

    (: one-value (-> String (List Syntax) Loc Syntax))
    (define (one-value name values loc)
      (match values
        ((Cons value (Nil)) value)
        (_ (compile-error loc (string-append name " expects one value")))))

    (: duplicate (All (A) (-> String String Loc Loc A)))
    (define (duplicate kind name here previous)
      (compile-error here (string-append "duplicate " kind " " name "; first declared at " (loc->string previous))))

    (: parse-build-options (-> Bool (List Syntax) BuildOptions))
    (define (parse-build-options browser? forms)
      (let loop ((forms forms) (seen (ann (Nil) (List (Pair String Loc))))
                 (options (BuildOptions (None) (Nil) (None))))
        (match forms
          ((Nil) options)
          ((Cons form rest)
           (match form
             ((Form (Cons (Ident name _ _) values) loc)
              (match (assoc-ref seen name)
                ((Some previous) (duplicate "option" name loc previous))
                ((None) (loop rest (Cons (Pair name loc) seen) (build-option browser? options name values loc)))))
             (_ (compile-error (syntax-loc form) "expected a build option form")))))))

    (: build-option (-> Bool BuildOptions String (List Syntax) Loc BuildOptions))
    (define (build-option browser? options name values loc)
      (cond
       ((string=? name "entry") (BuildOptions-entry-set options (Some (entry-path (one-value name values loc)))))
       ((string=? name "library-roots") (BuildOptions-libraries-set options (map parse-path values)))
       ((and browser? (string=? name "public")) (BuildOptions-public-set options (Some (parse-path (one-value name values loc)))))
       (else (compile-error loc (string-append "unknown build option " name)))))

    (: required-entry (-> BuildOptions Loc ProjectPath))
    (define (required-entry options loc)
      (match (BuildOptions-entry options)
        ((Some path) path)
        ((None) (compile-error loc "a build target requires an entry"))))

    (: parse-build (-> String Syntax Loc BuildTarget))
    (define (parse-build name syntax declaration)
      (match syntax
        ((Form (Cons (Ident kind _ _) forms) loc)
         (unless (or (string=? kind "program") (string=? kind "browser"))
           (compile-error loc (string-append "unknown build kind " kind)))
         (let* ((options (parse-build-options (string=? kind "browser") forms))
                (entry (required-entry options loc)) (libraries (BuildOptions-libraries options)))
           (if (string=? kind "program")
               (ProgramTarget (ProgramBuild name entry libraries declaration))
               (BrowserTarget (BrowserBuild name entry libraries (BuildOptions-public options) declaration)))))
        (_ (compile-error (syntax-loc syntax) "expected a program or browser build form"))))

    ;; ---- Launches and declarations ----

    (: launch-arguments (-> (List Syntax) (List String)))
    (define (launch-arguments forms)
      (let loop ((forms forms) (seen (ann (None) (Option Loc))) (arguments (ann (Nil) (List String))))
        (match forms
          ((Nil) arguments)
          ((Cons (Form (Cons (Ident "args" _ _) values) loc) rest)
           (match seen
             ((Some previous) (duplicate "option" "args" loc previous))
             ((None) (loop rest (Some loc) (map literal-string values)))))
          ((Cons form _) (compile-error (syntax-loc form) "expected an args option")))))

    (: parse-launch (-> String Syntax Loc PendingLaunch))
    (define (parse-launch name syntax declaration)
      (match syntax
        ((Form (Cons (Ident "run" _ _) (Cons target forms)) _)
         (PendingLaunch name (parse-name target) (syntax-loc target) (launch-arguments forms) declaration))
        (_ (compile-error (syntax-loc syntax) "expected (run BUILD-NAME (args STRING ...))"))))

    (: parse-declaration (-> Syntax Declaration))
    (define (parse-declaration syntax)
      (match syntax
        ((Form (Cons (Ident "build-target" _ _) (Cons name (Cons build (Nil)))) loc)
         (BuildDeclaration (parse-build (parse-name name) build loc)))
        ((Form (Cons (Ident "launch-target" _ _) (Cons name (Cons launch (Nil)))) loc)
         (LaunchDeclaration (parse-launch (parse-name name) launch loc)))
        (_ (compile-error (syntax-loc syntax) "expected a build-target or launch-target declaration"))))

    (: resolve-launch (-> (List BuildTarget) PendingLaunch LaunchTarget))
    (define (resolve-launch builds launch)
      (match (find-target builds (PendingLaunch-build launch))
        ((Some (ProgramTarget program))
         (LaunchTarget (PendingLaunch-name launch) program (PendingLaunch-arguments launch) (PendingLaunch-loc launch)))
        ((Some (BrowserTarget _))
         (compile-error (PendingLaunch-reference launch) "a launch target must reference a program build"))
        ((None) (compile-error (PendingLaunch-reference launch) (string-append "unknown build target " (PendingLaunch-build launch))))))

    ;; Small project lists need no second persistent name index. Each name is
    ;; checked once during collection; only resolved descriptions escape.
    (: collect-project (-> (List Declaration) Project))
    (define (collect-project declarations)
      (let loop ((rest declarations) (builds (ann (Nil) (List BuildTarget)))
                 (launches (ann (Nil) (List PendingLaunch))))
        (match rest
          ((Nil) (Project (reverse builds) (map (lambda (launch) (resolve-launch builds launch)) (reverse launches))))
          ((Cons (BuildDeclaration target) tail)
           (match (find-target builds (target-name target))
             ((Some previous) (duplicate "build target" (target-name target) (target-loc target) (target-loc previous)))
             ((None) (loop tail (Cons target builds) launches))))
          ((Cons (LaunchDeclaration launch) tail)
           (match (find (lambda (previous) (string=? (PendingLaunch-name previous) (PendingLaunch-name launch))) launches)
             ((Some previous) (duplicate "launch target" (PendingLaunch-name launch) (PendingLaunch-loc launch) (PendingLaunch-loc previous)))
             ((None) (loop tail builds (Cons launch launches))))))))

    (: parse-project (-> String String Project))
    (define (parse-project text file)
      (match (read-text text file)
        ((Cons (Form declarations _) (Nil)) (collect-project (map parse-declaration declarations)))
        ((Cons _ (Cons extra _)) (compile-error (syntax-loc extra) "a project description must contain exactly one list"))
        ((Cons form _) (compile-error (syntax-loc form) "a project description must contain exactly one list"))
        ((Nil) (compile-error (Loc file 1 1) "expected a project description list"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-project)
    (import
     (only (scheme base) car cdr guard error-object-message)
     (only (chibi string) string-contains)
     (lofi testing))
    (begin
      (define (project-error text)
        (guard (failure (#t (error-object-message failure)))
          (parse-project text "project.datum")
          "accepted"))

      (define (test-project)
        (let* ((text "((launch-target dev (run server (args \"\" \"--port\" \"8080\"))) (launch-target check (run server))\n(build-target client (browser (entry \"client.sld\") (public \"public\")))\n(build-target server (program (library-roots \".\" \"src\") (entry \"missing.sld\"))))")
               (project (parse-project text "project.datum"))
               (launch (car (Project-launches project)))
               (round-trip (syntax->string (car (read-text text "project.datum")))))
          (expect (map target-name (Project-builds project)) '("client" "server"))
          (expect (map LaunchTarget-name (Project-launches project)) '("dev" "check"))
          (expect (LaunchTarget-arguments launch) '("" "--port" "8080"))
          (expect (ProgramBuild-name (LaunchTarget-program launch)) "server")
          (expect (map ProjectPath-text (ProgramBuild-libraries (LaunchTarget-program launch))) '("." "src"))
          (expect (loc->string (ProgramBuild-loc (LaunchTarget-program launch))) "project.datum:3:1")
          (match (car (Project-builds project))
            ((BrowserTarget browser)
             (expect (ProjectPath-text (BrowserBuild-entry browser)) "client.sld")
             (match (BrowserBuild-public browser)
               ((Some path) (expect (ProjectPath-text path) "public"))
               ((None) (expect "missing public directory" "public"))))
            (_ (expect "program" "browser")))
          (let* ((printed (parse-project round-trip "printed.datum"))
                 (launch (car (Project-launches printed))))
            (expect (map target-name (Project-builds printed)) '("client" "server"))
            (expect (map LaunchTarget-name (Project-launches printed)) '("dev" "check"))
            (expect (LaunchTarget-arguments launch) '("" "--port" "8080"))
            (expect (map ProjectPath-text (ProgramBuild-libraries (LaunchTarget-program launch))) '("." "src"))
            (match (car (Project-builds printed))
              ((BrowserTarget browser)
               (expect (ProjectPath-text (BrowserBuild-entry browser)) "client.sld")
               (match (BrowserBuild-public browser)
                 ((Some path) (expect (ProjectPath-text path) "public"))
                 ((None) (expect "missing public directory" "public"))))
              (_ (expect "program" "browser")))))
        (expect (Project-builds (parse-project "()" "project.datum")) '())
        (expect (project-error "((launch-target dev\n  (run missing)))")
                "project.datum:2:8: unknown build target missing")
        (expect (project-error "()\n()") "project.datum:2:1: a project description must contain exactly one list")
        (expect (project-error "((build-target a (program\n  (entry \"a.sld\")\n  (entry \"b.sld\"))))")
                "project.datum:3:3: duplicate option entry; first declared at project.datum:2:3")
        (expect (project-error "((build-target a (program (entry \"a\")))\n (build-target a (program (entry \"b\"))))")
                "project.datum:2:2: duplicate build target a; first declared at project.datum:1:2")
        (for-each (lambda (entry)
                    (let ((actual (project-error (car entry))) (wanted (car (cdr entry))))
                      (expect (if (string-contains actual wanted) wanted actual) wanted)))
                  '(("() ()" "exactly one list")
                    ("((build-target x (program (entry)))" "unclosed list")
                    ("((build-target x (program (entry))))" "entry expects one value")
                    ("((launch-target x (run y (args 5))))" "expected a literal string")
                    ("((init (run \"anything\")))" "expected a build-target")
                    ("((build-target ../bad (program (entry \"x\"))))" "a target name starts")
                    ("((build-target x (program)))" "requires an entry")
                    ("((build-target x (program (entry \"x\") (entry \"y\"))))" "duplicate option entry")
                    ("((build-target x (program (entry \"x\") (library-roots) (library-roots))))" "duplicate option library-roots")
                    ("((build-target x (browser (entry \"x\") (public \"a\") (public \"b\"))))" "duplicate option public")
                    ("((build-target x (program (entry \"x\") (public \"a\"))))" "unknown build option public")
                    ("((build-target x (program (entry \"../x\"))))" "project-relative path")
                    ("((build-target x (program (entry \"/x\"))))" "project-relative path")
                    ("((build-target x (program (entry \"a//x\"))))" "project-relative path")
                    ("((build-target x (program (entry \".\"))))" "entry must name a file")
                    ("((build-target x (program (entry x))))" "expected a literal string")
                    ("((build-target x (program (entry \"x\"))) (build-target x (program (entry \"y\"))))" "duplicate build target x")
                    ("((launch-target x (run missing)))" "unknown build target missing")
                    ("((build-target x (browser (entry \"x\"))) (launch-target y (run x)))" "must reference a program")
                    ("((launch-target x (run y (args) (args))))" "duplicate option args")
                    ("((launch-target x (run y)) (launch-target x (run y)))" "duplicate launch target x")
                    ("((launch-target x (shell \"echo hello\")))" "expected (run BUILD-NAME")
                    ("((build-target x (program (entry \"x\"))) . tail)" "dotted lists are not part of Lofi"))))))
   (else)))
