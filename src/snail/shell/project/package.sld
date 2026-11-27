;; Source packages share one src/ namespace. Resolution reads the reachable
;; manifests, then checks their contributions before the compiler opens a
;; library. All source locations still point into their owning checkouts.
(define-library (snail shell project package)
  (export
   Package
   PackageSet
   workspace-packages
   package-directories)
  (import
   (snail core base)
   (snail core io)
   (snail core table)
   (snail shell process)
   (snail shell utf8)
   (only (snail shell text) string-downcase)
   (only (snail shell compiler sha256) bytes->hex sha256)
   (only (snail shell compiler library) LibraryLookup directory-lookup)
   (snail shell compiler read))
  (begin

    ;; ---- Declarations ----

    (enum GitRef
      (Commit ((id String)))
      (Tag ((name String))))

    (enum Origin
      (Checkout ((path String)))
      (Git ((url String) (revision GitRef))))

    (record Dependency
      ((name String)
       (origin Origin)
       (loc Loc)))

    (record Package
      ((name String)
       (root String)
       (exports (Option (List String)))
       (dependencies (List Dependency))))

    (define (manifest (root String)) (→ String)
      (string-append root "/package.scm"))

    (define (file-loc (path String)) (→ Loc)
      (new Loc (file path) (line 0) (column 0)))

    (define (read-package (fs Fs) (root String)) (→ Package)
      (let* ((path (manifest root))
             (text (match (read-text-file fs path 1048576)
                     ((Ok text) text)
                     ((Err error) (compile-error (file-loc path) (show error))))))
        (match (read-text text path)
          ((Cons (Form (Cons (Ident "package" _ _) (Cons (Ident name _ _) clauses)) _) (Nil))
           (package-clauses fs root name clauses))
          (_ (compile-error (file-loc path) "expected one (package NAME ...) declaration")))))

    ;; An optional export selects immediate entries of src/. Names are kept
    ;; exactly as they will appear in an import. The default exports all.
    (define (package-clauses (fs Fs) (root String) (name String) (clauses (List Syntax)))
      (→ Package)
      (match clauses
        ((Cons (Form (Cons (Ident "export" _ _) items) _) rest)
         (new Package (name name) (root root)
              (exports (Some (map (lambda (item) (export-name fs root item)) items)))
              (dependencies (dependencies rest))))
        (_ (new Package (name name) (root root) (exports (None))
                (dependencies (dependencies clauses))))))

    (define (export-name (fs Fs) (root String) (item Syntax)) (→ String)
      (match item
        ((Atom (DString name) loc)
         (unless (and (not (member? name (list "" "." "..")))
                      (every? (lambda (c) (not (member? c (list #\/ #\\ #\null))))
                              (string->list name)))
           (compile-error loc "an export names one entry of src/"))
         (match (file-status fs (string-append root "/src/" name))
           ((Ok _) name)
           ((Err error)
            (compile-error loc (string-append "cannot export src/" name ": " (show error))))))
        (_ (compile-error (syntax-loc item) "expected an export path string"))))

    (define (dependencies (clauses (List Syntax))) (→ (List Dependency))
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons (Ident "depends" _ _) items) _) (Nil)) (map dependency items))
        ((Cons item _) (compile-error (syntax-loc item) "expected (depends (NAME SOURCE) ...)"))))

    (define (dependency (item Syntax)) (→ Dependency)
      (match item
        ((Form (Cons (Ident name _ _) (Cons source (Nil))) loc)
         (new Dependency (name name) (origin (package-origin source)) (loc loc)))
        (_ (compile-error (syntax-loc item) "expected a dependency (NAME SOURCE)"))))

    (define (package-origin (source Syntax)) (→ Origin)
      (match source
        ((Form (Cons (Ident "path" _ _) (Cons path (Nil))) _) (Checkout (source-string path)))
        ((Form (Cons (Ident "git" _ _) (Cons url (Cons rev (Nil)))) _)
         (Git (source-string url) (git-ref rev)))
        (_ (compile-error (syntax-loc source) "expected (path DIRECTORY) or (git URL REF)"))))

    ;; Full object IDs are case insensitive. Both forms of a tag name,
    ;; v1 and refs/tags/v1, select the same pin.
    (define (git-ref (item Syntax)) (→ GitRef)
      (let ((text (source-string item)))
        (match (full-object-id text)
          ((Some id) (Commit id))
          ((None)
           (cond ((starts-with? text "refs/tags/") (Tag (substring text 10 (string-length text))))
                 ((starts-with? text "refs/")
                  (compile-error (syntax-loc item) "expected a Git tag or full commit hash"))
                 (else (Tag text)))))))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (full-object-id (text String)) (→ (Option String))
      (let ((hex? (lambda (c) (or (and (<= #\0 c) (<= c #\9))
                                  (and (<= #\a c) (<= c #\f))
                                  (and (<= #\A c) (<= c #\F))))))
        (if (and (member? (string-length text) (list 40 64)) (every? hex? (string->list text)))
            (Some (string-downcase text))
            (None))))

    (define (source-string (item Syntax)) (→ String)
      (match item
        ((Atom (DString value) loc)
         (when (or (string=? value "") (member? #\null (string->list value)))
           (compile-error loc "expected a nonempty source string without NUL"))
         value)
        (_ (compile-error (syntax-loc item) "expected a source string"))))

    ;; ---- Dependency closure ----

    ;; Only the explicit deps command supplies a clock to fetch a missing
    ;; Git checkout. Builds and editor checks resolve the same graph offline.
    (record Resolver
      ((fs Fs)
       (processes Processes)
       (git-tool String)
       (fetch (Option Clock))
       (cache String)
       (locked (Table String))
       (selected (Table String))))

    (record PackageSet
      ((members (List Package))
       (lookup LibraryLookup)))

    (define (source-directory (package Package)) (→ String)
      (string-append (● package root) "/src"))

    (define (package-directories (packages PackageSet)) (→ (List String))
      (map source-directory (● packages members)))

    (define (workspace-packages (processes Processes) (fs Fs) (fetch (Option Clock))
                                (workspace String) (standard String))
      (→ PackageSet)
      (if (manifest-present? fs workspace)
          (resolve-workspace processes fs fetch standard
                             (physical-directory processes
                                                 workspace
                                                 (file-loc (manifest workspace))))
          (assembled fs (implicit-packages workspace standard))))

    (define (resolve-workspace (processes Processes) (fs Fs) (fetch (Option Clock))
                               (standard String) (root String))
      (→ PackageSet)
      (let* ((lock (string-append root "/package.lock"))
             (resolver (new Resolver (fs fs) (processes processes) (fetch fetch)
                            (git-tool (string-append standard
                                                     "/build/wasm-snail-scheme-support-toolchain/release/snail-git"))
                            (cache (string-append root "/build/.snail-packages"))
                            (locked (read-pins fs lock)) (selected (empty-table))))
             (package (Package-exports-set (read-package fs root) (None)))
             (packages (assembled fs (visit resolver package (Nil) (Nil)))))
        (match fetch
          ((Some clock) (save-pins resolver clock lock))
          ((None) (unit)))
        packages))

    (define (manifest-present? (fs Fs) (root String)) (→ Bool)
      (match (file-status fs (manifest root))
        ((Ok _) #t)
        ((Err (NotFound)) #f)
        ((Err error) (compile-error (file-loc (manifest root)) (show error)))))

    ;; A workspace created before packages sees the two src/ trees it has
    ;; always used, including the repository's in-tree applications.
    (define (implicit-packages (workspace String) (standard String)) (→ (List Package))
      (let ((local (lambda (name root)
                     (new Package (name name) (root root) (exports (None)) (dependencies (Nil))))))
        (if (string=? workspace standard)
            (list (local "workspace" workspace))
            (list (local "workspace" workspace) (local "toolchain" standard)))))

    (define (visit (resolver Resolver) (package Package) (parents (List Package))
                   (done (List Package)))
      (→ (List Package))
      (Cons package
            (fold-left (lambda (seen edge)
                         (visit-dependency resolver package edge (Cons package parents) seen))
                       done (● package dependencies))))

    (define (visit-dependency (resolver Resolver) (parent Package) (edge Dependency)
                              (parents (List Package)) (done (List Package)))
      (→ (List Package))
      (let* ((name (● edge name)) (loc (● edge loc))
             (path (dependency-root resolver (● parent root) edge))
             (named? (lambda (package) (string=? (● package name) name))))
        (match (find named? (append parents done))
          ((Some prior)
           (unless (string=? path (● prior root))
             (compile-error loc
                            (string-append "package "
                                           name
                                           " has two sources: "
                                           (● prior root)
                                           " and "
                                           path)))
           (when (any? named? parents)
             (let ((chain (reverse (Cons name (map (lambda (p) (● p name)) parents)))))
               (compile-error loc
                              (string-append "package dependency cycle: "
                                             (string-join chain " → ")))))
           done)
          ((None) (visit resolver (declared-dependency (● resolver fs) edge path) parents done)))))

    (define (declared-dependency (fs Fs) (edge Dependency) (path String)) (→ Package)
      (let ((package (read-package fs path)))
        (unless (string=? (● edge name) (● package name))
          (compile-error (● edge loc) (string-append "expected package " (● edge name)
                                                     ", found " (● package name) " in " path)))
        package))

    (define (dependency-root (resolver Resolver) (parent String) (edge Dependency)) (→ String)
      (match (● edge origin)
        ((Checkout path)
         (physical-directory (● resolver processes) (relative-to parent path) (● edge loc)))
        ((Git url revision)
         (let ((remote (match (string-index url #\:)
                         ((Some _) url) ((None) (relative-to parent url))))
               (loc (● edge loc)))
           (git-checkout resolver remote
                         (match revision
                           ((Commit id) id)
                           ((Tag name) (tag-commit! resolver remote name loc)))
                         loc)))))

    (define (relative-to (directory String) (path String)) (→ String)
      (if (char=? (string-ref path 0) #\/) path (string-append directory "/" path)))

    ;; pwd -P lets paths through symlinks, . and .. share one package identity.
    (define (physical-directory (processes Processes) (path String) (loc Loc)) (→ String)
      (let ((line (command-text processes loc path "pwd" (list "-P"))))
        (substring line 0 (- (string-length line) 1))))

    ;; ---- Tag pins ----

    ;; The workspace lock records (URL TAG COMMIT) for every reachable tag.
    ;; A pair of quoted strings is both its table key and its printed form.
    ;; Only the root workspace's lock participates in a build.
    (define (pin-key (url String) (tag String)) (→ String)
      (string-append (datum->string (DString url)) " " (datum->string (DString tag))))

    (define (read-pins (fs Fs) (path String)) (→ (Table String))
      (match (read-text-file fs path 16777216)
        ((Err (ReadFailed (NotFound))) (empty-table))
        ((Err error) (compile-error (file-loc path) (show error)))
        ((Ok text)
         (match (read-text text path)
           ((Cons (Form (Cons (Ident "package-lock" _ _) entries) _) (Nil))
            (fold-left read-pin (empty-table) entries))
           (_ (compile-error (file-loc path) "expected (package-lock (URL TAG COMMIT) ...)"))))))

    (define (read-pin (pins (Table String)) (entry Syntax)) (→ (Table String))
      (match entry
        ((Form (Cons url (Cons tag (Cons id (Nil)))) loc)
         (let ((key (pin-key (source-string url) (source-string tag))))
           (when (table-contains? pins key) (compile-error loc "duplicate tag in package.lock"))
           (match (full-object-id (source-string id))
             ((Some commit) (table-set pins key commit))
             ((None)
              (compile-error (syntax-loc id) "expected a full commit hash in package.lock")))))
        (_ (compile-error (syntax-loc entry) "expected a tag pin (URL TAG COMMIT)"))))

    (define (pins-text (pins (Table String))) (→ String)
      (let ((line (lambda (key)
                    (match (table-ref pins key)
                      ((Some commit)
                       (string-append "\n  (" key " " (datum->string (DString commit)) ")"))
                      ((None) (panic "missing tag pin"))))))
        (string-append "(package-lock"
                       (string-concatenate (map line (list-sort string<? (table-keys pins))))
                       ")\n")))

    ;; The resolver owns this install's selections. Every edge using a tag
    ;; sees the same commit, even if the remote tag moves during resolution.
    (define (tag-commit! (resolver Resolver) (url String) (name String) (loc Loc)) (→ String)
      (let ((key (pin-key url name)) (ref (string-append "refs/tags/" name)))
        (match (table-ref (● resolver selected) key)
          ((Some commit) commit)
          ((None)
           (let ((commit (match (table-ref (● resolver locked) key)
                           ((Some commit)
                            (package-git resolver loc "." (list "check-tag" ref))
                            commit)
                           ((None) (resolve-tag resolver url ref loc)))))
             (set! (● resolver selected) (table-set (● resolver selected) key commit))
             commit)))))

    (define (resolve-tag (resolver Resolver) (url String) (ref String) (loc Loc)) (→ String)
      (match (● resolver fetch)
        ((None)
         (compile-error loc (string-append "unlocked Git tag " ref " (run snail-scheme deps)")))
        ((Some _)
         (match (full-object-id (package-git resolver loc "." (list "resolve-tag" url ref)))
           ((Some commit) commit)
           ((None) (compile-error loc "expected a full commit hash from snail-git"))))))

    ;; Publish only after the whole graph and source tree have checked.
    ;; Serialize this short replacement so a racing install cannot silently
    ;; overwrite new pins chosen by another. Readers see either whole file.
    (define (save-pins (resolver Resolver) (clock Clock) (path String)) (→ Unit)
      (let ((before (pins-text (● resolver locked))) (after (pins-text (● resolver selected))))
        (unless (string=? before after)
          (let ((deadline (+ ((● clock monotonic-nanoseconds)) 5000000000)))
            (publish-pins resolver clock path before after deadline)))))

    (define (publish-pins (resolver Resolver) (clock Clock) (path String) (before String)
                          (after String) (deadline I64))
      (→ Unit)
      (let ((fs (● resolver fs)) (guard (string-append path ".lock")) (loc (file-loc path)))
        (match (make-directory fs guard)
          ((Ok _)
           (let ((result (recovering (lambda () (replace-pins fs path guard before after)))))
             (remove-tree fs guard)
             (match result ((Ok _) (unit)) ((Err errors) (stop (Failed errors))))))
          ((Err (AlreadyExists))
           (when (>= ((● clock monotonic-nanoseconds)) deadline)
             (compile-error loc (string-append "package.lock is busy: " guard)))
           (command-text (● resolver processes) loc "." "sleep" (list "0.05"))
           (publish-pins resolver clock path before after deadline))
          ((Err error) (compile-error loc (show error))))))

    (define (replace-pins (fs Fs) (path String) (guard String) (before String) (after String))
      (→ Unit)
      (let ((current (pins-text (read-pins fs path))) (temp (string-append guard "/pins")))
        (unless (string=? current after)
          (unless (string=? current before)
            (compile-error (file-loc path)
                           "package.lock changed during resolution (run snail-scheme deps again)"))
          (match (write-text-file fs temp after (CreateNew))
            ((Err error) (compile-error (file-loc path) (show error)))
            ((Ok _) (match (rename-file fs temp path)
                      ((Ok _) (unit))
                      ((Err error) (compile-error (file-loc path) (show error)))))))))

    ;; ---- Git checkouts ----

    ;; Each URL and exact commit has its own checkout. Only completed
    ;; checkouts are published, by renaming a private directory beside them.
    (define (git-checkout (resolver Resolver) (url String) (commit String) (loc Loc))
      (→ String)
      (let* ((fs (● resolver fs)) (cache (● resolver cache))
             (path (string-append cache "/" (bytes->hex (sha256 (string->utf8 url))) "-" commit)))
        (if (file-exists? fs path)
            (verify-checkout resolver path commit loc)
            (match (● resolver fetch)
              ((Some clock) (fetch-checkout resolver clock url commit path loc))
              ((None) (compile-error loc (string-append "missing Git commit " commit
                                                        " (run snail-scheme deps)")))))
        path))

    (define (verify-checkout (resolver Resolver) (path String) (commit String) (loc Loc)) (→ Unit)
      (package-git resolver loc path (list "verify" commit))
      (unit))

    (define (fetch-checkout (resolver Resolver) (clock Clock) (url String) (commit String)
                            (path String) (loc Loc))
      (→ Unit)
      (let ((fs (● resolver fs)) (cache (● resolver cache)))
        (match (make-directories fs cache)
          ((Err error) (compile-error loc (string-append cache ": " (show error))))
          ((Ok _) (unit)))
        (let ((temp (checkout-scratch fs cache ((● clock monotonic-nanoseconds)) loc)))
          (match (recovering (lambda ()
                               (package-git resolver loc temp (list "checkout" url commit))
                               (publish-checkout resolver temp path commit loc)))
            ((Ok _) (unit))
            ((Err errors) (remove-tree fs temp) (stop (Failed errors)))))))

    ;; A concurrent install can win the rename. Its checkout must satisfy
    ;; the same pin. After our rename succeeds the temp name is free again.
    (define (publish-checkout (resolver Resolver)
                              (temp String)
                              (path String)
                              (commit String)
                              (loc Loc))
      (→ Unit)
      (let ((fs (● resolver fs)))
        (match (rename-file fs temp path)
          ((Ok _) (unit))
          ((Err error)
           (unless (file-exists? fs path)
             (compile-error loc (string-append path ": " (show error))))
           (verify-checkout resolver path commit loc)
           (remove-tree fs temp)
           (unit)))))

    (define (checkout-scratch (fs Fs) (cache String) (number I64) (loc Loc)) (→ String)
      (let ((path (string-append cache "/fetch-" (show number))))
        (match (make-directory fs path)
          ((Ok _) path)
          ((Err (AlreadyExists)) (checkout-scratch fs cache (+ number 1) loc))
          ((Err error) (compile-error loc (string-append path ": " (show error)))))))

    (define (package-git (resolver Resolver) (loc Loc) (directory String) (arguments (List String)))
      (→ String)
      (command-text (● resolver processes) loc directory (● resolver git-tool) arguments))

    (define (command-text (processes Processes) (loc Loc) (directory String)
                          (program String) (arguments (List String)))
      (→ String)
      (let ((command (new Command (program program) (arguments arguments) (directory directory))))
        (match ((● processes run) command #u8())
          ((Err error)
           (compile-error loc
                          (string-append "cannot run "
                                         program
                                         " in "
                                         directory
                                         ": "
                                         (● error code))))
          ((Ok captured)
           (match (● captured exit)
             ((Exited 0) (match (utf8->string (● captured stdout))
                           ((Ok text) text)
                           ((Err _) (compile-error loc "command output is not UTF-8"))))
             (_ (compile-error loc (string-append program " failed in " directory ": "
                                                  (match (utf8->string (● captured stderr))
                                                    ((Ok text) text)
                                                    ((Err _) "unreadable output"))))))))))

    ;; ---- The virtual src/ tree ----

    ;; Only directories can be shared. A top-level entry owned by one
    ;; package needs no walk. Where roots overlap, descend just their
    ;; intersection, checking assets as well as libraries before any import.
    (type Providers (Table (List Package)))

    (define (assembled (fs Fs) (members (List Package))) (→ PackageSet)
      (let ((providers (fold-left (lambda (index package)
                                    (fold-left
                                     (lambda (index name) (contribute fs index name package))
                                     index (source-entries fs package)))
                                  (empty-table) members)))
        (new PackageSet (members members) (lookup (provider-lookup fs providers)))))

    (define (provider-lookup (fs Fs) (providers Providers)) (→ LibraryLookup)
      (lambda (relative)
        (let ((head (match (string-index relative #\/)
                      ((Some end) (substring relative 0 end)) ((None) relative))))
          (match (table-ref providers head)
            ((None) (None))
            ((Some packages)
             ((directory-lookup fs (map source-directory packages)) relative))))))

    (define (source-entries (fs Fs) (package Package)) (→ (List String))
      (match (● package exports)
        ((Some names) (delete-duplicates string=? names))
        ((None)
         (let ((src (source-directory package)))
           (match (list-directory fs src)
             ((Ok names) names)
             ((Err (NotFound)) (Nil))
             ((Err error) (compile-error (file-loc src) (show error))))))))

    (define (source-path (package Package) (relative String)) (→ String)
      (string-append (● package root) "/src/" relative))

    (define (contribute (fs Fs) (index Providers) (name String) (package Package)) (→ Providers)
      (let ((others (match (table-ref index name) ((Some packages) packages) ((None) (Nil)))))
        (for-each (lambda (other) (check-overlap fs name package other)) others)
        (table-set index name (Cons package others))))

    (define (entry-kind (fs Fs) (path String)) (→ (Option FileKind))
      (match (file-status fs path)
        ((Ok status) (Some (● status kind)))
        ((Err (NotFound)) (None))
        ((Err error) (compile-error (file-loc path) (show error)))))

    (define (check-overlap (fs Fs) (relative String) (left Package) (right Package)) (→ Unit)
      (let ((a (source-path left relative)) (b (source-path right relative)))
        (match (new Pair (first (entry-kind fs b)) (second (entry-kind fs a)))
          ((Pair (None) _) (unit))
          ((Pair _ (None)) (unit))
          ((Pair (Some (Directory)) (Some (Directory)))
           (match (list-directory fs a)
             ((Err error) (compile-error (file-loc a) (show error)))
             ((Ok names)
              (for-each
               (lambda (name) (check-overlap fs (string-append relative "/" name) left right))
               names))))
          (_ (compile-error (file-loc (manifest (● left root)))
                            (string-append "conflicting src/"
                                           relative
                                           " in packages "
                                           (● left name)
                                           " ("
                                           a
                                           ") and "
                                           (● right name)
                                           " ("
                                           b
                                           ")"))))))

    ))
