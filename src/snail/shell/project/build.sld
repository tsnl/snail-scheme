;; A script's build: its program compiled, linked and packaged into a
;; generation of its own, then published by replacing the script's link
;; in its workspace's build/ at once. A compile that reaches a generated
;; library runs its producer first, and then compiles again. A check, for
;; the language server, compiles as a build does and writes nothing.
;;
;; Every build, debug or release, compiles the whole program afresh into
;; one module, linked with its runtime in-process (snail shell assembler).
;; The compiler carries no checked code or emitted modules between builds.
;;
;; The compiler, assembler and linker run in this program. Node runs
;; producers through `run` (snail shell process). A build that fails removes
;; every generation it made, and only those, so the outputs of earlier
;; builds stay published.
(define-library (snail shell project build)
  (export
   Tools
   Mode
   Debug
   Release
   Failure
   CompileFailure
   BuildFailure
   failure->string
   program-name
   Platform
   Node
   Browser
   platform-library
   Script
   script-at
   script-file
   script-name
   build-script
   check-script
   check-library
   workspace-directories
   producer-tools)
  (import
   (snail shell project web-app)
   (snail core base)
   (snail core io)
   (snail core table)
   (snail shell compiler)
   (only (snail shell compiler read)
         compiling
         Failed
         Requested
         GenerateInput
         Diagnostics
         diagnostics->string)
   (snail shell compiler inputs)
   (only (snail shell compiler check) Typed)
   (snail shell process)
   (snail shell assembler)
   (snail shell json)
   (snail shell json read)
   (snail shell compiler sha256)
   (snail shell utf8))
  (begin

    ;; ---- Tools and modes ----

    ;; What a build runs besides the compiler: `root` holds the standard
    ;; libraries (src/), the browser host's files and the native runner,
    ;; `runtime` is the runtime module a program is linked with, `toolchain`
    ;; the one a program that links the assembler is, whose services
    ;; include it, and `node` runs producers. Binaryen's wasm-opt, which
    ;; optimizes a release build, is found on PATH. `building` holds the
    ;; scripts whose builds this one is part of, outermost first: a producer
    ;; is handed its build's, so a script that embeds itself is refused.
    (record Tools
      ((root String)
       (runtime String)
       (toolchain String)
       (node String)
       (building (List String))))

    ;; Every build compiles the whole program to one module and fuses it
    ;; with the runtime: NAME.wasm, with copies of the files it links, so
    ;; its directory can be served or shipped on its own, a page's with the
    ;; browser host and a Node program's as an npm package. A release build
    ;; also optimizes the module with wasm-opt, which can inline the
    ;; runtime's functions into the program; that is the modes' one
    ;; difference.
    (enum Mode
      (Debug)
      (Release))

    ;; ---- Scripts ----

    ;; Where a script's program runs: on Node or in a page.
    (enum Platform
      (Node)
      (Browser))

    (define (platform-library (platform Platform)) (→ (List String))
      (list "snail"
            "target"
            (match platform
              ((Node) "node")
              ((Browser) "browser"))))

    ;; A script: `file`, an absolute path, in `workspace`, the nearest folder
    ;; above it that holds src/, where every import resolves.
    (record Script
      ((file String)
       (workspace String)))

    ;; The script at `path`, taken from the working directory if relative.
    (define (script-at (fs Fs) (environment ProcessEnvironment) (path String)) (→ Script)
      (script-file fs (from-working-directory environment path)))

    ;; The script at an absolute path.
    (define (script-file (fs Fs) (path String)) (→ Script)
      (let ((file (normalized path)))
        (unless (file-exists? fs file) (panic (string-append "there is no script at " file)))
        (new Script (file file) (workspace (workspace-of fs file (directory-of file))))))

    ;; A path made absolute against the working directory.

    (define (from-working-directory (environment ProcessEnvironment) (path String)) (→ String)
      (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/))
          path
          (string-append (match (working-directory environment)
                           ((Some directory) directory)
                           ((None) (panic "there is no working directory")))
                         "/"
                         path)))

    ;; An absolute path without empty or "." components, and with each ".."
    ;; taking the component before it.

    (define (normalized (absolute String)) (→ String)
      (let ((parts (fold-left (lambda (kept part)
                                (cond ((or (string=? part "") (string=? part ".")) kept)
                                      ((string=? part "..") (match kept
                                                              ((Cons _ rest) rest)
                                                              ((Nil) (Nil))))
                                      (else (Cons part kept))))
                              (Nil)
                              (split-path absolute))))
        (string-append "/" (string-join (reverse parts) "/"))))

    (define (workspace-of (fs Fs) (file String) (directory String)) (→ String)
      (cond ((file-exists? fs (string-append directory "/src")) directory)
            ((string=? directory "") (panic (string-append "no folder above " file " holds src/")))
            (else (workspace-of fs file (directory-of directory)))))

    (define (directory-of (path String)) (→ String)
      (let loop ((index (- (string-length path) 1)))
        (cond ((< index 0) "")
              ((char=? (string-ref path index) #\/) (substring path 0 index))
              (else (loop (- index 1))))))

    ;; The script's path in its workspace, and without its extension, the
    ;; name of its build: build/NAME holds its output.

    (define (script-path (script Script)) (→ String)
      (let ((workspace (● script workspace)) (file (● script file)))
        (substring file (+ (string-length workspace) 1) (string-length file))))

    (define (script-name (script Script)) (→ String)
      (let ((path (script-path script)))
        (let loop ((index (- (string-length path) 1)))
          (cond ((< index 0) path)
                ((char=? (string-ref path index) #\/) path)
                ((char=? (string-ref path index) #\.) (substring path 0 index))
                (else (loop (- index 1)))))))

    ;; Builds the script for `platform` and publishes it; answers its
    ;; generation. A producer can call this too, with `producer-tools`, to
    ;; embed another build: its generated library links the files.

    (define (build-script (processes Processes)
                          (fs Fs)
                          (clock Clock)
                          (tools Tools)
                          (script Script)
                          (platform Platform)
                          (mode Mode))
      (→ String)
      (match (with-builder fs clock (building-script tools script)
                           (● script workspace)
                           mode
                           (lambda (builder)
                             (build-target processes
                                           fs
                                           clock
                                           builder
                                           (script-target fs tools script platform))))
        ((Err failure) (panic (failure->string failure)))
        ((Ok output)
         (match (publish fs (● script workspace) output)
           ((Err message) (panic message))
           ((Ok _) (● output directory))))))

    ;; The tools of the script's build, which its producers are run with.
    ;; A producer that builds a script already being built would be run
    ;; again by that build, without end, so it stops here.

    (define (building-script (tools Tools) (script Script)) (→ Tools)
      (let ((building (append (● tools building) (list (● script file)))))
        (when (member? (● script file) (● tools building))
          (panic (string-append "a script's build embeds itself: " (string-join building " → "))))
        (Tools-building-set tools building)))

    ;; The build target a script is: a page, with the public/ folder beside
    ;; the script if there is one, or a program.

    (define (script-target (fs Fs) (tools Tools) (script Script) (platform Platform))
      (→ Target)
      (new Target
        (name (script-name script))
        (browser? (match platform ((Browser) #t) (_ #f)))
        (platform (Some (platform-library platform)))
        (entry (● script file))
        (directories (workspace-directories tools (● script workspace)))
        (public (match platform
                  ((Browser) (script-public fs script))
                  (_ (None))))))

    (define (script-public (fs Fs) (script Script)) (→ (Option String))
      (let* ((directory (directory-of (script-path script)))
             (public (if (string=? directory "") "public" (string-append directory "/public"))))
        (if (file-exists? fs (string-append (● script workspace) "/" public))
            (Some public)
            (None))))

    ;; Where a workspace's imports resolve: its src/, then the standard
    ;; libraries', unless they are the same, as in this repository.

    (define (workspace-directories (tools Tools) (workspace String)) (→ (List String))
      (let ((own (string-append workspace "/src")) (standard (string-append (● tools root) "/src")))
        (if (string=? own standard) (list own) (list own standard))))

    ;; ---- Checks ----

    ;; The script checked for `platform` as a build would, its producers
    ;; run, and nothing written: its program as the checker typed it.

    (define (check-script (processes Processes)
                          (fs Fs)
                          (clock Clock)
                          (tools Tools)
                          (script Script)
                          (platform Platform))
      (→ (Result Typed Failure))
      (checking processes fs clock (building-script tools script)
                (● script workspace)
                (lambda (working) (script-target fs tools script platform))))

    ;; The library `name` of `workspace`, checked as the program that
    ;; imports it is, under no target.

    (define (check-library (processes Processes)
                           (fs Fs)
                           (clock Clock)
                           (tools Tools)
                           (workspace String)
                           (name (List String)))
      (→ (Result Typed Failure))
      (checking processes fs clock tools
                workspace
                (lambda (working)
                  (let ((entry (string-append working "/check.scm")))
                    (write-file fs entry (string-append "(import (" (string-join name " ") "))\n"))
                    (new Target
                      (name "check")
                      (browser? #f)
                      (platform (None))
                      (entry entry)
                      (directories (workspace-directories tools workspace))
                      (public (None)))))))

    ;; The program `target` gives, in a working directory of its own,
    ;; checked as a debug build would check it.

    (define (checking (processes Processes)
                      (fs Fs)
                      (clock Clock)
                      (tools Tools)
                      (workspace String)
                      (target (Fn String → Target)))
      (→ (Result Typed Failure))
      (with-builder fs clock tools
                    workspace
                    (Debug)
                    (lambda (builder)
                      (in-working fs builder
                                  "check"
                                  (lambda (working)
                                    (● (check-target
                                        processes
                                        fs
                                        builder
                                        (target working)
                                        working)
                                       typed))))))

    ;; What a producer's build runs, from its command line: a build runs a
    ;; producer with the path its output goes to, then the build's tools,
    ;; the scripts being built last.

    (define (producer-tools (arguments Arguments)) (→ Tools)
      (match (command-line arguments)
        ((Cons _ (Cons _ (Cons root (Cons runtime (Cons toolchain (Cons node building))))))
         (new Tools
           (root root)
           (runtime runtime)
           (toolchain toolchain)
           (node node)
           (building building)))
        (_ (panic "producer-tools: this program is not a producer a build ran"))))

    ;; ---- Failures ----

    ;; Why a build stopped: a compile's diagnostics, each naming its source
    ;; point, or a failure of the build's own work, which names a file or a
    ;; command.
    (enum Failure
      (CompileFailure ((diagnostics Diagnostics)))
      (BuildFailure ((message String))))

    (define (failure->string (failure Failure)) (→ String)
      (match failure
        ((CompileFailure diagnostics) (diagnostics->string diagnostics))
        ((BuildFailure message) message)))

    ;; A build stops at the first failure it meets, and nothing after the
    ;; failure runs: nothing resumes a suspension to the build's prompt, so
    ;; stopping saves no frames. `attempt` turns the work into a Result.
    (define failing (→ (Prompt Failure Never)) (make-prompt))

    (define (stop-build (failure Failure)) (→ A) (∀ (A))
      (absurd (suspend failing failure)))

    (define (fail-build (message String)) (→ A) (∀ (A))
      (stop-build (BuildFailure message)))

    (define (attempt (work (Fn → T))) (→ (Result T Failure)) (∀ (T))
      (with-prompt failing (lambda () (Ok (work))) (lambda (failure resume) (Err failure))))

    ;; A compile that fails stops the build with its diagnostic. One that
    ;; needs no producer asks for nothing.

    (define (compiled (work (Fn → T)))
      (→ T)
      (∀ (T))
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (stop-build (CompileFailure diagnostics)))
        ((Err (Requested (GenerateInput key)))
         (fail-build (string-append "internal error: a compile asked for the producer " key)))))

    ;; ---- Builders ----

    ;; One build's fixed context: what it runs, the workspace, the mode,
    ;; and the scratch directory its compiles and producers work in, which
    ;; no other build shares.
    (record Builder
      ((tools Tools)
       (workspace String)
       (mode Mode)
       (scratch String)))

    ;; `work` with a builder of its own, in a fresh scratch directory under
    ;; the repository's build/snail-run/, removed after; a failure is its
    ;; Result.

    (define (with-builder (fs Fs) (clock Clock) (tools Tools)
                          (workspace String)
                          (mode Mode)
                          (work (Fn Builder → T)))
      (→ (Result T Failure))
      (∀ (T))
      (match (attempt (lambda ()
                        (fresh-scratch fs clock (string-append (● tools root) "/build/snail-run"))))
        ((Err failure) (Err failure))
        ((Ok scratch)
         (let ((result (attempt (lambda ()
                                  (work (new Builder
                                          (tools tools)
                                          (workspace workspace)
                                          (mode mode)
                                          (scratch scratch)))))))
           (remove-tree fs scratch)
           result))))

    (define (fresh-scratch (fs Fs) (clock Clock) (scratch String)) (→ String)
      (expect-done (make-directories fs scratch) (string-append "cannot make " scratch))
      (fresh-directory fs (string-append scratch "/build-") "" (monotonic-nanoseconds clock)))

    ;; ---- A build ----

    ;; What a build makes: its name, whether it is a page, the target
    ;; library its program runs under, if any, its entry program's path,
    ;; the directories its libraries are found in, and a page's public
    ;; folder, relative to the workspace.
    (record Target
      ((name String)
       (browser? Bool)
       (platform (Option (List String)))
       (entry String)
       (directories (List String))
       (public (Option String))))

    ;; A target's generation, not yet published: the target's name and the
    ;; directory that holds what was built for it.
    (record Output
      ((name String)
       (directory String)))

    ;; ---- Targets ----

    ;; Builds a target into a new generation, which goes if the build of it
    ;; fails.

    (define (build-target (processes Processes)
                          (fs Fs)
                          (clock Clock)
                          (builder Builder)
                          (target Target))
      (→ Output)
      (let* ((name (● target name))
             (directory (prepare-generation fs clock builder name)))
        (removing fs directory
                  (lambda ()
                    (let ((libraries (build-program processes fs builder target directory)))
                      (if (● target browser?)
                          (package-browser fs builder target directory)
                          (package-node fs builder name directory libraries)))
                    (new Output (name name) (directory directory))))))

    ;; `work`'s value; when it fails, `directory` goes before the failure
    ;; does.

    (define (removing (fs Fs) (directory String) (work (Fn → T)))
      (→ T)
      (∀ (T))
      (match (attempt work)
        ((Ok value) value)
        ((Err failure)
         (remove-tree fs directory)
         (stop-build failure))))

    ;; The target's program in its generation, compiled anew, with the
    ;; files it links; answers the libraries the program holds.

    (define (build-program (processes Processes)
                           (fs Fs)
                           (builder Builder)
                           (target Target)
                           (directory String))
      (→ (List String))
      (in-working fs builder (● target name)
                  (lambda (working)
                    (let ((checked (check-target processes fs builder target working)))
                      (write-program processes fs builder target directory working checked)))))

    (define (check-target (processes Processes)
                          (fs Fs)
                          (builder Builder)
                          (target Target)
                          (working String))
      (→ Checked)
      (let ((directories (● target directories)))
        (producing processes fs builder working directories
                   (lambda ()
                     (source->checked fs directories
                                      (● target entry)
                                      (lambda (loading forms)
                                        (generated-syntax fs working directories loading forms))
                                      (● target platform)
                                      (known-digests fs builder))))))

    ;; The program's one module, NAME.wasm, and copies of the files it links
    ;; in its store/; answers the libraries it holds. A release build's is
    ;; linked in `working` and optimized from there.

    (define (write-program (processes Processes) (fs Fs) (builder Builder)
                           (target Target)
                           (directory String)
                           (working String)
                           (checked Checked))
      (→ (List String))
      (let* ((program (compiled (lambda () (checked->wat checked))))
             (output (string-append directory "/" (program-name (● target name)))))
        (match (● builder mode)
          ((Debug) (write-bytes fs output (linked-program fs builder program)))
          ((Release)
           (let ((linked (string-append working "/linked.wasm")))
             (write-bytes fs linked (linked-program fs builder program))
             (optimize processes linked output))))
        (place-links fs builder directory (● program links))
        (● program libraries)))

    ;; `work` in a directory of its own in the build's scratch, removed after.

    (define (in-working (fs Fs) (builder Builder) (name String) (work (Fn String → T)))
      (→ T)
      (∀ (T))
      (let ((working (in-scratch builder (string-append "target-" (base-name name)))))
        (make-directories fs working)
        (let ((result (work working)))
          (remove-tree fs working)
          result)))

    (define (in-scratch (builder Builder) (name String)) (→ String)
      (string-append (● builder scratch) "/" name))

    ;; ---- Programs ----

    ;; The runtime a program links with: the toolchain's, whose services
    ;; include the assembler, for a program that links (snail shell
    ;; assembler), and the plain one otherwise.

    (define (program-runtime (builder Builder) (libraries (List String))) (→ String)
      (let ((tools (● builder tools)))
        (if (member? "snail.shell.assembler" libraries)
            (● tools toolchain)
            (● tools runtime))))

    ;; The program at `entry`, compiled in this process to one module and
    ;; linked with the runtime into `output`; the files it links ship beside
    ;; it. The compile's own files stay in `working`.

    (define (link-program (processes Processes) (fs Fs) (builder Builder)
                          (entry String)
                          (directories (List String))
                          (working String)
                          (output String))
      (→ (List LinkedFile))
      (let ((program (producing processes fs builder working directories
                                (lambda ()
                                  (source->wat fs directories
                                               entry
                                               (lambda (loading forms)
                                                 (generated-syntax fs working
                                                                   directories
                                                                   loading
                                                                   forms))
                                               (Some (list "snail" "target" "node"))
                                               (known-digests fs builder))))))
        (write-bytes fs output (linked-program fs builder program))
        (● program links)))

    ;; The whole program fused with its runtime into one module.

    (define (linked-program (fs Fs) (builder Builder) (program WholeProgram))
      (→ Bytes)
      (match (link (● program text) (read-bytes fs (program-runtime builder (● program libraries))))
        ((Ok bytes) bytes)
        ((Err message) (fail-build (string-append "cannot link program: " message)))))

    ;; wasm-opt's -O2 over the linked module, enabling exactly the
    ;; proposals the program may use: the compiler's GC, typed references,
    ;; tail calls, bulk memory for its constant data and saturating
    ;; conversions, and the Rust runtime's wasm32-wasip1 defaults. Enabling
    ;; every feature would let it introduce one a host lacks: it then emits
    ;; exact reference types, which Node 26 rejects.

    (define (optimize (processes Processes) (linked String) (output String)) (→ Unit)
      (run-command processes (new Command (program "wasm-opt")
                                  (arguments (list "--enable-gc"
                                                   "--enable-reference-types"
                                                   "--enable-tail-call"
                                                   "--enable-bulk-memory"
                                                   "--enable-nontrapping-float-to-int"
                                                   "--enable-sign-ext"
                                                   "--enable-mutable-globals"
                                                   "--enable-multivalue"
                                                   "-O2"
                                                   linked
                                                   "-o"
                                                   output))
                                  (directory "."))
                   "wasm-opt"))

    ;; What a host runs or a page loads: the program's module, named for
    ;; the last part of its target's name, the script's.

    (define (program-name (target String)) (→ String)
      (string-append (base-name target) ".wasm"))

    ;; ---- Linked files ----

    ;; A file a program links is an object: named for the SHA-256 of its
    ;; bytes, at sha256/AB/DIGEST, sharded by its first two hex digits. The
    ;; workspace keeps one store of them, build/.snail-store, which every
    ;; build of every script shares: an object is placed once and never
    ;; rewritten. A program reads its files from store/ beside its module,
    ;; where each is another name for the store's object, a hard link: a
    ;; program's bulky files are on disk once, and its directory still holds
    ;; them itself, to be served or shipped on its own. Nothing reclaims the
    ;; store; deleting build/ does.

    (define (workspace-store (builder Builder)) (→ String)
      (string-append (● builder workspace) "/build/.snail-store"))

    (define (object-path (store String) (digest String)) (→ String)
      (string-append store "/sha256/" (substring digest 0 2) "/" digest))

    ;; The files `links` names, in the workspace's store and under
    ;; `directory`'s store/: a program's generation, or a producer's scratch.

    (define (place-links (fs Fs) (builder Builder) (directory String) (links (List LinkedFile)))
      (→ Unit)
      (for-each (lambda (link)
                  (let ((object (object-path (workspace-store builder) (● link digest)))
                        (to (object-path (string-append directory "/store") (● link digest))))
                    (unless (kind-is? fs object (RegularFile))
                      (place-object fs link object (base-name directory)))
                    (expect-done (make-directories fs (directory-part to))
                                 (string-append "cannot make " to))
                    (name-object fs object to)))
                (delete-duplicates (lambda (a b) (string=? (● a digest) (● b digest))) links))
      (remember-digests fs builder links (base-name directory)))

    ;; ---- Digests ----

    ;; The digests of linked files the workspace's builds have read, in its
    ;; store at digests, a line a file: DIGEST SIZE MODIFIED PATH. A
    ;; compile trusts one while its file keeps that size and modification
    ;; time, so a large file is hashed once rather than every build. A
    ;; build that read new ones writes the whole list beside the old and
    ;; renames it over, so a reader sees one list or the other; of two
    ;; builds at once, the later rename wins and the other's files are
    ;; hashed again.

    (define (digests-path (builder Builder)) (→ String)
      (string-append (workspace-store builder) "/digests"))

    (define (known-digests (fs Fs) (builder Builder)) (→ (List LinkedFile))
      (match (read-text-file fs (digests-path builder) 1073741824)
        ((Ok text)
         (fold-left (lambda (files line)
                      (match (digest-line (pieces line #\space))
                        ((Some file) (Cons file files))
                        ((None) files)))
                    (Nil)
                    (pieces text #\newline)))
        ((Err _) (Nil))))

    ;; `text` cut at each `separator`.

    (define (pieces (text String) (separator Char)) (→ (List String))
      (map (lambda (chars) (list->string (reverse chars)))
           (reverse
            (fold-left (lambda (found char)
                         (match found
                           ((Cons piece rest)
                            (if (char=? char separator)
                                (Cons (Nil) found)
                                (Cons (Cons char piece) rest)))
                           ((Nil) (Nil))))
                       (list (Nil))
                       (string->list text)))))

    ;; A line's fields, the path the rest of the line, spaces and all.

    (define (digest-line (fields (List String))) (→ (Option LinkedFile))
      (match fields
        ((Cons digest (Cons size (Cons modified (Cons first rest))))
         (match (string->i64 size)
           ((Some size)
            (match (string->i64 modified)
              ((Some modified)
               (Some (new LinkedFile
                       (digest digest)
                       (path (string-join (Cons first rest) " "))
                       (size size)
                       (modified modified))))
              ((None) (None))))
           ((None) (None))))
        (_ (None))))

    ;; The list with `links` in it, written when one is new. A path with a
    ;; newline in it is not kept.

    (define (remember-digests (fs Fs) (builder Builder) (links (List LinkedFile)) (token String))
      (→ Unit)
      (let* ((table (by-path (empty-table) (known-digests fs builder)))
             (fresh (filter (lambda (link) (new-digest? table link)) links)))
        (unless (null? fresh)
          (let ((path (digests-path builder))
                (writing (string-append (digests-path builder) ".writing." token)))
            (write-file fs writing (digests-text (by-path table fresh)))
            (expect-done (rename-file fs writing path) (string-append "cannot write " path))))))

    (define (by-path (table (Table LinkedFile)) (files (List LinkedFile))) (→ (Table LinkedFile))
      (fold-left (lambda (table file) (table-set table (● file path) file)) table files))

    (define (new-digest? (table (Table LinkedFile)) (link LinkedFile)) (→ Bool)
      (and (match (string-index (● link path) #\newline) ((Some _) #f) ((None) #t))
           (match (table-ref table (● link path))
             ((Some known)
              (not (and (string=? (● known digest) (● link digest))
                        (= (● known size) (● link size))
                        (= (● known modified) (● link modified)))))
             ((None) #t))))

    (define (digests-text (table (Table LinkedFile))) (→ String)
      (string-join (map (lambda (file)
                          (string-join (list (● file digest)
                                             (show (● file size))
                                             (show (● file modified))
                                             (● file path))
                                       " "))
                        (table-values table))
                   "\n"))

    ;; A file is named for the digest of the bytes its compile read, so the
    ;; bytes placed must be those: a file edited since fails the build, and
    ;; the next one compiles against its new bytes. A link to a file is
    ;; read through, as the compile read it. The object is written beside
    ;; its place, under a name this build alone writes, and renamed into it,
    ;; so a reader never sees a partial object, and two builds placing one
    ;; object at once each rename the same bytes.

    (define (place-object (fs Fs) (link LinkedFile) (object String) (token String))
      (→ Unit)
      (let ((from (● link path)) (writing (string-append object ".writing." token)))
        (unless (match (followed-status fs from)
                  ((Ok status) (match (● status kind) ((RegularFile) #t) (_ #f)))
                  ((Err _) #f))
          (fail-build
           (string-append "cannot place the linked file " from ": there is no file there")))
        (let ((bytes (read-bytes fs from)))
          (unless (string=? (bytes->hex (sha256 bytes)) (● link digest))
            (fail-build (string-append "the linked file " from " changed during the build")))
          (expect-done (make-directories fs (directory-part object))
                       (string-append "cannot make " object))
          (write-bytes fs writing bytes)
          (expect-done (rename-file fs writing object) (string-append "cannot place " object)))))

    ;; Another name for the store's object, or a copy of it where the two
    ;; lie on different file systems.

    (define (name-object (fs Fs) (object String) (to String)) (→ Unit)
      (match (make-hard-link fs object to)
        ((Ok _) (unit))
        ((Err _) (copy-into fs object to (string-append "cannot copy " object)))))

    ;; Runs a command to its end, and stops the build with what it wrote to
    ;; stderr unless it exits with status 0.

    (define (run-command (processes Processes) (command Command) (name String))
      (→ Unit)
      (match (run processes command #u8())
        ((Err error) (fail-build (string-append "cannot run " name ": " (● error code))))
        ((Ok captured)
         (match (● captured exit)
           ((Exited 0) (unit))
           (exit (fail-build (string-append name " failed: " (failure-text captured exit))))))))

    ;; A failed command's stderr, or how it ended when it wrote nothing
    ;; that reads as text.

    (define (failure-text (captured Captured) (exit Exit)) (→ String)
      (match (utf8->string (● captured stderr))
        ((Ok stderr) (if (string=? stderr "") (how-it-ended exit) stderr))
        ((Err _) (how-it-ended exit))))

    (define (how-it-ended (exit Exit)) (→ String)
      (match exit
        ((Exited code) (string-append "exited with " (show code)))
        ((Signaled name) (string-append "ended by " name))))

    ;; ---- Producers ----

    ;; A compile, with each producer it asks for run first. A compile that
    ;; reaches a generated library whose output `working` does not hold
    ;; prints the producer there and asks for it; the producer is compiled,
    ;; linked and run, writing that output, and the compile starts again.
    ;; The producer's own compile does the same, and the libraries loading
    ;; when it was reached begin its source, so one that needs its own
    ;; library is an import cycle.

    (define (producing (processes Processes) (fs Fs) (builder Builder)
                       (working String)
                       (directories (List String))
                       (work (Fn → T)))
      (→ T)
      (∀ (T))
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (stop-build (CompileFailure diagnostics)))
        ((Err (Requested (GenerateInput key)))
         (produce processes fs builder working directories key)
         (producing processes fs builder working directories work))))

    (define (produce (processes Processes)
                     (fs Fs)
                     (builder Builder)
                     (working String)
                     (directories (List String))
                     (key String))
      (→ Unit)
      (let ((program (string-append working "/" key ".wasm")))
        (place-links fs builder
                     working
                     (link-program processes fs builder
                                   (string-append working "/" key ".sld")
                                   directories
                                   working
                                   program))
        (run-producer processes fs builder program (string-append working "/" key ".syntax"))))

    ;; A producer runs in the workspace, and its command line
    ;; names its output's path and then the build's tools (`producer-tools`).

    (define (run-producer (processes Processes)
                          (fs Fs)
                          (builder Builder)
                          (program String)
                          (output String))
      (→ Unit)
      (let ((tools (● builder tools)))
        (run-command processes (new Command (program (● tools node))
                                    (arguments (append (list "--no-warnings"
                                                             (string-append (● tools root)
                                                                            "/host/native/run-snail.mjs")
                                                             program
                                                             output
                                                             (● tools root)
                                                             (● tools runtime)
                                                             (● tools toolchain)
                                                             (● tools node))
                                                       (● tools building)))
                                    (directory (● builder workspace)))
                     "the producer")
        (unless (file-exists? fs output)
          (fail-build "the producer did not write its generated library"))))

    ;; ---- Node packages ----

    ;; A Node build's generation is an npm package around its module, which
    ;; runs wherever it is copied: `npm start -- ARGUMENT ...` runs it, as
    ;; `cargo run` runs a crate, and so does `node main.mjs`. Its main.mjs
    ;; runs NAME.wasm with the native host, whose files it holds under host/
    ;; as the repository keeps them, so their imports are unchanged. A
    ;; program that holds (snail runtime gpu) may ask for a device and
    ;; decode an image, and depends on the webgpu and @napi-rs/canvas
    ;; packages at the versions the repository's package.json pins; npm
    ;; installs them in the package, or Node finds the repository's in a
    ;; folder above. Other programs depend on nothing. An
    ;; executable made of the package, or its publication, is the work of
    ;; Node's own tools (doc/book/snail-scheme/projects.md, "A Node package").

    (define node-files (→ (List String))
      (list "native/run-snail.mjs"
            "native/answers.mjs"
            "native/async-files.mjs"
            "native/gpu.mjs"
            "native/process-imports.mjs"
            "native/process.mjs"
            "native/socket-imports.mjs"
            "native/tcp.mjs"
            "native/udp.mjs"
            "browser/gpu.mjs"
            "browser/load.mjs"
            "browser/tasks.mjs"))

    (define (package-node (fs Fs) (builder Builder)
                          (name String)
                          (directory String)
                          (libraries (List String)))
      (→ Unit)
      (let ((root (● (● builder tools) root)))
        (for-each (lambda (file)
                    (copy-into fs (string-append root "/host/" file)
                               (string-append directory "/host/" file)
                               (string-append "cannot copy the native host's " file)))
                  node-files)
        (write-file fs (string-append directory "/main.mjs") (node-main name))
        (write-file fs (string-append directory "/package.json")
                    (json->string (node-manifest fs root name libraries)))))

    ;; The package's entry, which runs NAME.wasm beside it with its own
    ;; arguments. Node warns that WASI is experimental as the runner loads,
    ;; which the command line's --no-warnings silences. The entry silences
    ;; warnings before it imports the runner, so the package runs alike
    ;; through npm, as `node main.mjs` and in an executable.

    (define (node-main (name String)) (→ String)
      (string-join (list "#!/usr/bin/env node"
                         (string-append "// Runs " (program-name name) ", a snail-scheme program.")
                         "import {join} from 'node:path';"
                         ""
                         "process.removeAllListeners('warning');"
                         (string-append "const program = join(import.meta.dirname, "
                                        (json->string (JsonString (program-name name)))
                                        ");")
                         "import('./host/native/run-snail.mjs').then(({start}) => start(program, process.argv.slice(2)));"
                         "")
                   "\n"))

    ;; package.json: the package is private, which keeps npm from
    ;; publishing it until its author gives it a version and a name of
    ;; their own. `npm start` and its one command, NAME, run main.mjs.

    (define (node-manifest (fs Fs) (root String) (name String) (libraries (List String))) (→ Json)
      (let ((command (base-name name)))
        (JsonObject
         (append (list (new Pair (first "name") (second (JsonString command)))
                       (new Pair (first "private") (second (JsonBool #t)))
                       (new Pair
                         (first "scripts")
                         (second (JsonObject (list (new Pair
                                                     (first "start")
                                                     (second (JsonString "node main.mjs")))))))
                       (new Pair
                         (first "bin")
                         (second (JsonObject (list (new Pair
                                                     (first command)
                                                     (second (JsonString "main.mjs"))))))))
                 (if (member? "snail.runtime.gpu" libraries)
                     (list (new Pair
                             (first "dependencies")
                             (second (JsonObject (map (lambda (package)
                                                        (new Pair
                                                          (first package)
                                                          (second
                                                           (pinned-version fs root package))))
                                                      (list "webgpu" "@napi-rs/canvas"))))))
                     (Nil))))))

    ;; The version of `package` the repository's package.json pins, which
    ;; its own runs use too.

    (define (pinned-version (fs Fs) (root String) (package String)) (→ Json)
      (let* ((path (string-append root "/package.json"))
             (manifest (match (read-text-file fs path 1048576)
                         ((Ok text) (string->json text))
                         ((Err _) (None)))))
        (match (member-of (member-of manifest "dependencies") package)
          ((Some (JsonString version)) (JsonString version))
          (_ (fail-build (string-append path " pins no version of " package))))))

    (define (member-of (value (Option Json)) (name String)) (→ (Option Json))
      (match value
        ((Some value) (json-member value name))
        ((None) (None))))

    ;; ---- Browser packages ----

    (define browser-files (→ (List String))
      (list "host.mjs"
            "application.mjs"
            "runtime.mjs"
            "tasks.mjs"
            "entry.mjs"
            "gpu.mjs"
            "storage.mjs"
            "load.mjs"
            "style.css"
            "ui.mjs"
            "dom.mjs"
            "fetch.mjs"
            "files.mjs"
            "install.mjs"
            "snail-icon.svg" "snail-icon-192.png" "snail-icon-512.png"))

    ;; The names a build of `target` writes at its generation's root: its
    ;; module, store/, the ownership marker and the browser host's files.
    ;; A public tree may use none of them.

    (define (generated-names (target String)) (→ (List String))
      (append (list (program-name target) "store" ".snail-target") browser-files))

    ;; The browser host's files, then the target's public tree, if it has
    ;; one. The page is the public folder's index.html; none is generated.
    ;; UTF-8 pages receive a web-app manifest link and are told where the
    ;; program's module is. A public web-app manifest replaces the default
    ;; whole.

    (define (package-browser (fs Fs) (builder Builder) (target Target) (directory String))
      (→ Unit)
      (let ((name (● target name)))
        (copy-browser-assets fs builder target directory)
        (ensure-web-manifest fs (string-append (base-name (● builder workspace)) " / " name)
                             directory)
        (prepare-browser-page fs directory (program-name name))))

    ;; Public assets were copied first. A supplied manifest is a complete
    ;; replacement; the default is a regular file in the same output tree.

    (define (ensure-web-manifest (fs Fs) (name String) (directory String)) (→ Unit)
      (let ((path (string-append directory "/manifest.webmanifest")))
        (unless (file-exists? fs path)
          (write-file fs path (json->string (web-app-manifest name))))))

    (define (prepare-browser-page (fs Fs) (directory String) (program String)) (→ Unit)
      (let ((path (string-append directory "/index.html")))
        (when (kind-is? fs path (RegularFile))
          (match (utf8->string (read-bytes fs path))
            ((Err _) (unit))
            ((Ok text) (write-file fs path (with-web-app text program)))))))

    (define (copy-browser-assets (fs Fs) (builder Builder) (target Target) (directory String))
      (→ Unit)
      (for-each (lambda (file)
                  (copy-into fs
                             (string-append (● (● builder tools) root) "/host/browser/" file)
                             (string-append directory "/" file)
                             (string-append "cannot copy the browser host's " file)))
                browser-files)
      (match (● target public)
        ((Some path)
         (copy-public fs
                      (public-directory fs builder path)
                      directory
                      (generated-names (● target name))))
        ((None) (unit))))

    ;; The public directory, which may not be the workspace or lie in
    ;; its build output, and whose every component is a directory, not a
    ;; link.

    (define (public-directory (fs Fs) (builder Builder) (text String)) (→ String)
      (begin
        (when (or (string=? text ".") (string=? (first-component text) "build"))
          (fail-build (string-append "public directory overlaps the build output: " text)))
        (fold-left (lambda (directory part)
                     (let ((next (string-append directory "/" part)))
                       (unless (kind-is? fs next (Directory))
                         (fail-build (string-append
                                      "public path must contain only directories, not links: "
                                      next)))
                       next))
                   (● builder workspace)
                   (split-path text))))

    ;; Copies a public tree into the generation. Nothing in it may replace
    ;; a file the build made, use a name `reserved` holds, which are those
    ;; the build writes at the root and none below, or be anything but a
    ;; regular file or a directory.

    (define (copy-public (fs Fs) (source String) (output String) (reserved (List String)))
      (→ Unit)
      (for-each (lambda (name)
                  (let ((from (string-append source "/" name)) (to (string-append output "/" name)))
                    (when (or (member? name reserved)
                              (exists? fs to)
                              (string=? name ".snail-publish"))
                      (fail-build
                       (string-append "public file conflicts with a build artifact: " from)))
                    (match (status-kind fs from)
                      ((Some (SymbolicLink))
                       (fail-build (string-append "public files cannot be symbolic links: " from)))
                      ((Some (Directory))
                       (make-directory fs to)
                       (copy-public fs from to (Nil)))
                      ((Some (RegularFile))
                       (copy-into fs from to (string-append "cannot copy " from)))
                      (_ (fail-build (string-append
                                      "public entry must be a regular file or directory: "
                                      from))))))
                (directory-names fs source)))

    ;; ---- Generations ----

    ;; A new generation for the target `name` beside its output link,
    ;; build/NAME, holding only its ownership marker. A script's target is
    ;; named for its path, so its link and generation may lie below build/.
    ;; The output link, if any, must be one a build published.

    (define (prepare-generation (fs Fs) (clock Clock) (builder Builder) (name String))
      (→ String)
      (let* ((build (string-append (● builder workspace) "/build"))
             (output (string-append build "/" name))
             (beside (directory-part output)))
        (when (kind-is? fs build (SymbolicLink))
          (fail-build (string-append "the build directory cannot be a symbolic link: " build)))
        (expect-done (make-directories fs beside) (string-append "cannot make " beside))
        (check-output fs output name)
        (let ((directory (fresh-directory fs (string-append beside "/.snail-")
                                          (string-append "-" (base-name name))
                                          (monotonic-nanoseconds clock))))
          (write-file fs (string-append directory "/.snail-target") name)
          directory)))

    ;; A directory `STEM N SUFFIX` that no other build has made, as mkdtemp
    ;; makes one: N starts at `token`, and goes up while the name is taken.

    (define (fresh-directory (fs Fs) (stem String) (suffix String) (token I64))
      (→ String)
      (let ((directory (string-append stem (show token) suffix)))
        (match (make-directory fs directory)
          ((Ok _) directory)
          ((Err (AlreadyExists)) (fresh-directory fs stem suffix (+ token 1)))
          ((Err error) (fail-build (string-append "cannot make " directory ": " (show error)))))))

    ;; An output is replaced only when it is a link to a generation beside
    ;; it whose marker names the target.

    (define (check-output (fs Fs) (output String) (name String)) (→ Unit)
      (match (status-kind fs output)
        ((None) (unit))
        ((Some (SymbolicLink))
         (let ((marker (string-append output "/.snail-target")))
           (unless (and (match (read-symbolic-link fs output)
                          ((Ok link) (and (starts-with? link ".snail-")
                                          (match (string-index link #\/)
                                            ((Some _) #f)
                                            ((None) #t))))
                          ((Err _) #f))
                        (kind-is? fs marker (RegularFile))
                        (string=? (read-file fs marker) name))
             (unmanaged output))))
        ((Some _) (unmanaged output))))

    (define (unmanaged (output String)) (→ A) (∀ (A))
      (fail-build (string-append "refusing to replace an unmanaged build output: " output)))

    ;; ---- Publication ----

    ;; Publishes a generation by replacing its target's link in the
    ;; workspace's build/ with one to it: a new link is made beside the
    ;; generation, then renamed into place, which is atomic. A failure
    ;; removes the generation and leaves the link as it was.

    (define (publish (fs Fs) (workspace String) (output Output)) (→ (Result Unit String))
      (let ((directory (● output directory))
            (link (string-append workspace "/build/" (● output name))))
        (match (attempt (lambda ()
                          (check-output fs link (● output name))
                          (expect-done (make-symbolic-link fs (base-name directory)
                                                           (string-append directory
                                                                          "/.snail-publish"))
                                       (string-append "cannot link " directory))
                          (expect-done
                           (rename-file fs (string-append directory "/.snail-publish") link)
                           (string-append "cannot publish " (● output name)))))
          ((Ok _) (Ok (unit)))
          ((Err failure)
           (remove-tree fs directory)
           (Err (failure->string failure))))))

    ;; ---- Files ----

    ;; The kind of what is at `path`, not following a link, or None when
    ;; nothing is.

    (define (status-kind (fs Fs) (path String)) (→ (Option FileKind))
      (match (file-status fs path)
        ((Ok status) (Some (● status kind)))
        ((Err _) (None))))

    (define (kind-is? (fs Fs) (path String) (kind FileKind)) (→ Bool)
      (match (new Pair (first (status-kind fs path)) (second kind))
        ((Pair (Some (RegularFile)) (RegularFile)) #t)
        ((Pair (Some (Directory)) (Directory)) #t)
        ((Pair (Some (SymbolicLink)) (SymbolicLink)) #t)
        (_ #f)))

    (define (exists? (fs Fs) (path String)) (→ Bool)
      (match (status-kind fs path)
        ((Some _) #t)
        ((None) #f)))

    (define (directory-names (fs Fs) (path String)) (→ (List String))
      (match (list-directory fs path)
        ((Ok names) names)
        ((Err error) (fail-build (string-append "cannot read directory " path ": " (show error))))))

    ;; Copies a file's bytes to `to`, making its directory first.

    (define (copy-into (fs Fs) (from String) (to String) (failure String)) (→ Unit)
      (unless (kind-is? fs from (RegularFile))
        (fail-build (string-append failure ": there is no file at " from)))
      (expect-done (make-directories fs (directory-part to)) failure)
      (write-bytes fs to (read-bytes fs from)))

    (define (expect-done (result (Result T FileError)) (failure String))
      (→ Unit)
      (∀ (T))
      (match result
        ((Ok _) (unit))
        ((Err error) (fail-build (string-append failure ": " (show error))))))

    ;; ---- Text ----

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (split-path (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (split-path (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    (define (first-component (path String)) (→ String)
      (match (string-index path #\/)
        ((Some index) (substring path 0 index))
        ((None) path)))

    (define (base-name (path String)) (→ String)
      (match (last (split-path path))
        ((Some name) name)
        ((None) path)))

    ;; The directory that holds `path`, which has at least one slash.

    (define (directory-part (path String)) (→ String)
      (substring path 0 (- (string-length path) (+ (string-length (base-name path)) 1))))

    ))
