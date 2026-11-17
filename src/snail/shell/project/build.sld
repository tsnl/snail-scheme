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
   script-name
   build-script
   check-script
   check-library
   workspace-directories
   producer-tools
   resolved)
  (import
   (snail shell project web-app)
   (snail core base)
   (snail core io)
   (snail shell compiler)
   (only (snail shell compiler read)
         compile
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
    ;; its directory can be served or shipped on its own. A release build
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

    (define (script-at (path String)) (→ Script) (! fs)
      (let ((file (resolved path)))
        (unless (file-exists? file) (panic (string-append "there is no script at " file)))
        (new Script (file file) (workspace (workspace-of file (directory-of file))))))

    (define (workspace-of (file String) (directory String)) (→ String) (! fs)
      (cond ((file-exists? (string-append directory "/src")) directory)
            ((string=? directory "") (panic (string-append "no folder above " file " holds src/")))
            (else (workspace-of file (directory-of directory)))))

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

    (define (build-script (tools Tools) (script Script) (platform Platform) (mode Mode))
      (→ String)
      (! mut fs clock process)
      (match (with-builder (building-script tools script)
                           (● script workspace)
                           mode
                           (lambda (builder)
                             (build-target builder (script-target tools script platform))))
        ((Err failure) (panic (failure->string failure)))
        ((Ok output)
         (match (publish (● script workspace) output)
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

    (define (script-target (tools Tools) (script Script) (platform Platform)) (→ Target) (! fs)
      (new Target
        (name (script-name script))
        (browser? (match platform ((Browser) #t) (_ #f)))
        (platform (Some (platform-library platform)))
        (entry (● script file))
        (directories (workspace-directories tools (● script workspace)))
        (public (match platform
                  ((Browser) (script-public script))
                  (_ (None))))))

    (define (script-public (script Script)) (→ (Option String)) (! fs)
      (let* ((directory (directory-of (script-path script)))
             (public (if (string=? directory "") "public" (string-append directory "/public"))))
        (if (file-exists? (string-append (● script workspace) "/" public)) (Some public) (None))))

    ;; Where a workspace's imports resolve: its src/, then the standard
    ;; libraries', unless they are the same, as in this repository.

    (define (workspace-directories (tools Tools) (workspace String)) (→ (List String))
      (let ((own (string-append workspace "/src")) (standard (string-append (● tools root) "/src")))
        (if (string=? own standard) (list own) (list own standard))))

    ;; ---- Checks ----

    ;; The script checked for `platform` as a build would, its producers
    ;; run, and nothing written: its program as the checker typed it.

    (define (check-script (tools Tools) (script Script) (platform Platform))
      (→ (Result Typed Failure))
      (! mut fs clock process)
      (checking (building-script tools script)
                (● script workspace)
                (lambda (working) (script-target tools script platform))))

    ;; The library `name` of `workspace`, checked as the program that
    ;; imports it is, under no target.

    (define (check-library (tools Tools) (workspace String) (name (List String)))
      (→ (Result Typed Failure))
      (! mut fs clock process)
      (checking tools
                workspace
                (lambda (working)
                  (let ((entry (string-append working "/check.scm")))
                    (write-file entry (string-append "(import (" (string-join name " ") "))\n"))
                    (new Target
                      (name "check")
                      (browser? #f)
                      (platform (None))
                      (entry entry)
                      (directories (workspace-directories tools workspace))
                      (public (None)))))))

    ;; The program `target` gives, in a working directory of its own,
    ;; checked as a debug build would check it.

    (define (checking (tools Tools) (workspace String) (target (Fn String → Target ! fs)))
      (→ (Result Typed Failure))
      (! mut fs clock process)
      (with-builder tools
                    workspace
                    (Debug)
                    (lambda (builder)
                      (in-working builder
                                  "check"
                                  (lambda (working)
                                    (● (check-target builder (target working) working) typed))))))

    ;; What a producer's build runs, from its command line: a build runs a
    ;; producer with the path its output goes to, then the build's tools,
    ;; the scripts being built last.

    (define (producer-tools) (→ Tools)
      (match (command-line)
        ((Cons _ (Cons _ (Cons root (Cons runtime (Cons toolchain (Cons node building))))))
         (new Tools
           (root root)
           (runtime runtime)
           (toolchain toolchain)
           (node node)
           (building building)))
        (_ (panic "producer-tools: this program is not a producer a build ran"))))

    ;; A path made absolute against the working directory, without empty or
    ;; "." components, and with each ".." taking the component before it.

    (define (resolved (path String)) (→ String)
      (let* ((absolute (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/))
                           path
                           (string-append (match (working-directory)
                                            ((Some directory) directory)
                                            ((None) (panic "there is no working directory")))
                                          "/"
                                          path)))
             (parts (fold-left (lambda (kept part)
                                 (cond ((or (string=? part "") (string=? part ".")) kept)
                                       ((string=? part "..") (match kept
                                                               ((Cons _ rest) rest)
                                                               ((Nil) (Nil))))
                                       (else (Cons part kept))))
                               (Nil)
                               (split-path absolute))))
        (string-append "/" (string-join (reverse parts) "/"))))

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
    ;; failure runs, so a yield to this effect saves no frames. `attempt`
    ;; turns the work into a Result.
    (effect building
      ((ctl stop (Fn Failure → Never))))

    (define (fail-build (message String)) (→ A) (! building) (∀ (A))
      (absurd (stop (BuildFailure message))))

    (define (attempt (work (Fn → T ! building e))) (→ (Result T Failure)) (! e) (∀ (T e))
      (handle building
          ((stop (lambda (failure) (Err failure))))
        (Ok (work))))

    ;; A compile that fails stops the build with its diagnostic. One that
    ;; needs no producer asks for nothing.

    (define (compiled (work (Fn → T ! compile e)))
      (→ T)
      (! building e)
      (∀ (T e))
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (absurd (stop (CompileFailure diagnostics))))
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

    (define (with-builder (tools Tools)
                          (workspace String)
                          (mode Mode)
                          (work (Fn Builder → T ! mut fs clock process building)))
      (→ (Result T Failure))
      (! mut fs clock process)
      (∀ (T))
      (match (attempt (lambda () (fresh-scratch (string-append (● tools root) "/build/snail-run"))))
        ((Err failure) (Err failure))
        ((Ok scratch)
         (let ((result (attempt (lambda ()
                                  (work (new Builder
                                          (tools tools)
                                          (workspace workspace)
                                          (mode mode)
                                          (scratch scratch)))))))
           (remove-tree scratch)
           result))))

    (define (fresh-scratch (scratch String)) (→ String) (! fs clock building)
      (expect-done (make-directories scratch) (string-append "cannot make " scratch))
      (fresh-directory (string-append scratch "/build-") "" (monotonic-nanoseconds)))

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

    (define (build-target (builder Builder) (target Target))
      (→ Output)
      (! mut fs clock process building)
      (let* ((name (● target name))
             (directory (prepare-generation builder name)))
        (removing directory
                  (lambda ()
                    (build-program builder target directory)
                    (when (● target browser?)
                      (package-browser builder target directory))
                    (new Output (name name) (directory directory))))))

    ;; `work`'s value; when it fails, `directory` goes before the failure
    ;; does.

    (define (removing (directory String) (work (Fn → T ! building e)))
      (→ T)
      (! fs building e)
      (∀ (T e))
      (match (attempt work)
        ((Ok value) value)
        ((Err failure)
         (remove-tree directory)
         (absurd (stop failure)))))

    ;; The target's program in its generation, compiled anew, with the
    ;; files it links.

    (define (build-program (builder Builder) (target Target) (directory String))
      (→ Unit)
      (! mut fs process building)
      (in-working builder (● target name)
                  (lambda (working)
                    (let ((checked (check-target builder target working)))
                      (write-program builder target directory working checked)))))

    (define (check-target (builder Builder) (target Target) (working String)) (→ Checked)
      (! mut fs process building)
      (let ((directories (● target directories)))
        (producing builder working directories
                   (lambda ()
                     (source->checked directories
                                      (● target entry)
                                      (lambda (loading forms)
                                        (generated-syntax working directories loading forms))
                                      (● target platform))))))

    ;; The program's one module, NAME.wasm, and copies of the files it links
    ;; in its store/. A release build's is linked in `working` and optimized
    ;; from there.

    (define (write-program (builder Builder)
                           (target Target)
                           (directory String)
                           (working String)
                           (checked Checked))
      (→ Unit)
      (! mut fs process building)
      (let* ((program (compiled (lambda () (checked->wat checked))))
             (output (string-append directory "/" (program-name (● target name)))))
        (match (● builder mode)
          ((Debug) (write-bytes output (linked-program builder program)))
          ((Release)
           (let ((linked (string-append working "/linked.wasm")))
             (write-bytes linked (linked-program builder program))
             (optimize linked output))))
        (place-links builder directory (● program links))))

    ;; `work` in a directory of its own in the build's scratch, removed after.

    (define (in-working (builder Builder) (name String) (work (Fn String → T ! fs e)))
      (→ T)
      (! fs e)
      (∀ (T e))
      (let ((working (in-scratch builder (string-append "target-" (base-name name)))))
        (make-directories working)
        (let ((result (work working)))
          (remove-tree working)
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

    (define (link-program (builder Builder)
                          (entry String)
                          (directories (List String))
                          (working String)
                          (output String))
      (→ (List LinkedFile))
      (! mut fs process building)
      (let ((program (producing builder working directories
                                (lambda ()
                                  (source->wat directories
                                               entry
                                               (lambda (loading forms)
                                                 (generated-syntax working
                                                                   directories
                                                                   loading
                                                                   forms))
                                               (Some (list "snail" "target" "node")))))))
        (write-bytes output (linked-program builder program))
        (● program links)))

    ;; The whole program fused with its runtime into one module.

    (define (linked-program (builder Builder) (program WholeProgram)) (→ Bytes) (! fs building)
      (match (link (● program text) (read-bytes (program-runtime builder (● program libraries))))
        ((Ok bytes) bytes)
        ((Err message) (fail-build (string-append "cannot link program: " message)))))

    ;; wasm-opt's -O2 over the linked module, enabling exactly the
    ;; proposals the program may use: the compiler's GC, typed references,
    ;; tail calls, bulk memory for its constant data and saturating
    ;; conversions, and the Rust runtime's wasm32-wasip1 defaults. Enabling
    ;; every feature would let it introduce one a host lacks: it then emits
    ;; exact reference types, which Node 26 rejects.

    (define (optimize (linked String) (output String)) (→ Unit)
      (! process building)
      (run-command (new Command (program "wasm-opt")
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

    (define (place-links (builder Builder) (directory String) (links (List LinkedFile)))
      (→ Unit)
      (! fs building)
      (for-each (lambda (link)
                  (let ((object (object-path (workspace-store builder) (● link digest)))
                        (to (object-path (string-append directory "/store") (● link digest))))
                    (unless (kind-is? object (RegularFile))
                      (place-object link object (base-name directory)))
                    (expect-done (make-directories (directory-part to))
                                 (string-append "cannot make " to))
                    (name-object object to)))
                (delete-duplicates (lambda (a b) (string=? (● a digest) (● b digest))) links)))

    ;; A file is named for the digest of the bytes its compile read, so the
    ;; bytes placed must be those: a file edited since fails the build, and
    ;; the next one compiles against its new bytes. A link to a file is
    ;; read through, as the compile read it. The object is written beside
    ;; its place, under a name this build alone writes, and renamed into it,
    ;; so a reader never sees a partial object, and two builds placing one
    ;; object at once each rename the same bytes.

    (define (place-object (link LinkedFile) (object String) (token String)) (→ Unit) (! fs building)
      (let ((from (● link path)) (writing (string-append object ".writing." token)))
        (unless (match (followed-status from)
                  ((Ok status) (match (● status kind) ((RegularFile) #t) (_ #f)))
                  ((Err _) #f))
          (fail-build
           (string-append "cannot place the linked file " from ": there is no file there")))
        (let ((bytes (read-bytes from)))
          (unless (string=? (bytes->hex (sha256 bytes)) (● link digest))
            (fail-build (string-append "the linked file " from " changed during the build")))
          (expect-done (make-directories (directory-part object))
                       (string-append "cannot make " object))
          (write-bytes writing bytes)
          (expect-done (rename-file writing object) (string-append "cannot place " object)))))

    ;; Another name for the store's object, or a copy of it where the two
    ;; lie on different file systems.

    (define (name-object (object String) (to String)) (→ Unit) (! fs building)
      (match (make-hard-link object to)
        ((Ok _) (unit))
        ((Err _) (copy-into object to (string-append "cannot copy " object)))))

    ;; Runs a command to its end, and stops the build with what it wrote to
    ;; stderr unless it exits with status 0.

    (define (run-command (command Command) (name String)) (→ Unit) (! process building)
      (match (run command #u8())
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

    (define (producing (builder Builder)
                       (working String)
                       (directories (List String))
                       (work (Fn → T ! compile e)))
      (→ T)
      (! mut fs process building e)
      (∀ (T e))
      (match (compiling work)
        ((Ok value) value)
        ((Err (Failed diagnostics)) (absurd (stop (CompileFailure diagnostics))))
        ((Err (Requested (GenerateInput key)))
         (produce builder working directories key)
         (producing builder working directories work))))

    (define (produce (builder Builder) (working String) (directories (List String)) (key String))
      (→ Unit)
      (! mut fs process building)
      (let ((program (string-append working "/" key ".wasm")))
        (place-links builder
                     working
                     (link-program builder
                                   (string-append working "/" key ".sld")
                                   directories
                                   working
                                   program))
        (run-producer builder program (string-append working "/" key ".syntax"))))

    ;; A producer runs in the workspace, and its command line
    ;; names its output's path and then the build's tools (`producer-tools`).

    (define (run-producer (builder Builder) (program String) (output String))
      (→ Unit)
      (! fs process building)
      (let ((tools (● builder tools)))
        (run-command (new Command (program (● tools node))
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
        (unless (file-exists? output)
          (fail-build "the producer did not write its generated library"))))

    ;; ---- Browser packages ----

    (define browser-files (→ (List String))
      (list "host.mjs"
            "application.mjs"
            "runtime.mjs"
            "tasks.mjs"
            "entry.mjs"
            "gpu.mjs"
            "storage.mjs" "load.mjs" "style.css" "ui.mjs" "dom.mjs" "fetch.mjs" "install.mjs"
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

    (define (package-browser (builder Builder) (target Target) (directory String))
      (→ Unit)
      (! fs building)
      (let ((name (● target name)))
        (copy-browser-assets builder target directory)
        (ensure-web-manifest (string-append (base-name (● builder workspace)) " / " name)
                             directory)
        (prepare-browser-page directory (program-name name))))

    ;; Public assets were copied first. A supplied manifest is a complete
    ;; replacement; the default is a regular file in the same output tree.

    (define (ensure-web-manifest (name String) (directory String)) (→ Unit) (! fs)
      (let ((path (string-append directory "/manifest.webmanifest")))
        (unless (file-exists? path)
          (write-file path (json->string (web-app-manifest name))))))

    (define (prepare-browser-page (directory String) (program String)) (→ Unit) (! fs)
      (let ((path (string-append directory "/index.html")))
        (when (kind-is? path (RegularFile))
          (match (utf8->string (read-bytes path))
            ((Err _) (unit))
            ((Ok text) (write-file path (with-web-app text program)))))))

    (define (copy-browser-assets (builder Builder) (target Target) (directory String))
      (→ Unit)
      (! fs building)
      (for-each (lambda (file)
                  (copy-into
                   (string-append (● (● builder tools) root) "/host/browser/" file)
                   (string-append directory "/" file)
                   (string-append "cannot copy the browser host's " file)))
                browser-files)
      (match (● target public)
        ((Some path)
         (copy-public (public-directory builder path) directory (generated-names (● target name))))
        ((None) (unit))))

    ;; The public directory, which may not be the workspace or lie in
    ;; its build output, and whose every component is a directory, not a
    ;; link.

    (define (public-directory (builder Builder) (text String)) (→ String) (! fs building)
      (begin
        (when (or (string=? text ".") (string=? (first-component text) "build"))
          (fail-build (string-append "public directory overlaps the build output: " text)))
        (fold-left (lambda (directory part)
                     (let ((next (string-append directory "/" part)))
                       (unless (kind-is? next (Directory))
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

    (define (copy-public (source String) (output String) (reserved (List String)))
      (→ Unit)
      (! fs building)
      (for-each (lambda (name)
                  (let ((from (string-append source "/" name)) (to (string-append output "/" name)))
                    (when (or (member? name reserved)
                              (exists? to)
                              (string=? name ".snail-publish"))
                      (fail-build
                       (string-append "public file conflicts with a build artifact: " from)))
                    (match (status-kind from)
                      ((Some (SymbolicLink))
                       (fail-build (string-append "public files cannot be symbolic links: " from)))
                      ((Some (Directory))
                       (make-directory to)
                       (copy-public from to (Nil)))
                      ((Some (RegularFile)) (copy-into from to (string-append "cannot copy " from)))
                      (_ (fail-build (string-append
                                      "public entry must be a regular file or directory: "
                                      from))))))
                (directory-names source)))

    ;; ---- Generations ----

    ;; A new generation for the target `name` beside its output link,
    ;; build/NAME, holding only its ownership marker. A script's target is
    ;; named for its path, so its link and generation may lie below build/.
    ;; The output link, if any, must be one a build published.

    (define (prepare-generation (builder Builder) (name String)) (→ String) (! fs clock building)
      (let* ((build (string-append (● builder workspace) "/build"))
             (output (string-append build "/" name))
             (beside (directory-part output)))
        (when (kind-is? build (SymbolicLink))
          (fail-build (string-append "the build directory cannot be a symbolic link: " build)))
        (expect-done (make-directories beside) (string-append "cannot make " beside))
        (check-output output name)
        (let ((directory (fresh-directory (string-append beside "/.snail-")
                                          (string-append "-" (base-name name))
                                          (monotonic-nanoseconds))))
          (write-file (string-append directory "/.snail-target") name)
          directory)))

    ;; A directory `STEM N SUFFIX` that no other build has made, as mkdtemp
    ;; makes one: N starts at `token`, and goes up while the name is taken.

    (define (fresh-directory (stem String) (suffix String) (token I64)) (→ String) (! fs building)
      (let ((directory (string-append stem (show token) suffix)))
        (match (make-directory directory)
          ((Ok _) directory)
          ((Err (AlreadyExists)) (fresh-directory stem suffix (+ token 1)))
          ((Err error) (fail-build (string-append "cannot make " directory ": " (show error)))))))

    ;; An output is replaced only when it is a link to a generation beside
    ;; it whose marker names the target.

    (define (check-output (output String) (name String)) (→ Unit) (! fs building)
      (match (status-kind output)
        ((None) (unit))
        ((Some (SymbolicLink))
         (let ((marker (string-append output "/.snail-target")))
           (unless (and (match (read-symbolic-link output)
                          ((Ok link) (and (starts-with? link ".snail-")
                                          (match (string-index link #\/)
                                            ((Some _) #f)
                                            ((None) #t))))
                          ((Err _) #f))
                        (kind-is? marker (RegularFile))
                        (string=? (read-file marker) name))
             (unmanaged output))))
        ((Some _) (unmanaged output))))

    (define (unmanaged (output String)) (→ A) (! building) (∀ (A))
      (fail-build (string-append "refusing to replace an unmanaged build output: " output)))

    ;; ---- Publication ----

    ;; Publishes a generation by replacing its target's link in the
    ;; workspace's build/ with one to it: a new link is made beside the
    ;; generation, then renamed into place, which is atomic. A failure
    ;; removes the generation and leaves the link as it was.

    (define (publish (workspace String) (output Output)) (→ (Result Unit String)) (! fs)
      (let ((directory (● output directory))
            (link (string-append workspace "/build/" (● output name))))
        (match (attempt (lambda ()
                          (check-output link (● output name))
                          (expect-done (make-symbolic-link (base-name directory)
                                                           (string-append directory
                                                                          "/.snail-publish"))
                                       (string-append "cannot link " directory))
                          (expect-done
                           (rename-file (string-append directory "/.snail-publish") link)
                           (string-append "cannot publish " (● output name)))))
          ((Ok _) (Ok (unit)))
          ((Err failure)
           (remove-tree directory)
           (Err (failure->string failure))))))

    ;; ---- Files ----

    ;; The kind of what is at `path`, not following a link, or None when
    ;; nothing is.

    (define (status-kind (path String)) (→ (Option FileKind)) (! fs)
      (match (file-status path)
        ((Ok status) (Some (● status kind)))
        ((Err _) (None))))

    (define (kind-is? (path String) (kind FileKind)) (→ Bool) (! fs)
      (match (new Pair (first (status-kind path)) (second kind))
        ((Pair (Some (RegularFile)) (RegularFile)) #t)
        ((Pair (Some (Directory)) (Directory)) #t)
        ((Pair (Some (SymbolicLink)) (SymbolicLink)) #t)
        (_ #f)))

    (define (exists? (path String)) (→ Bool) (! fs)
      (match (status-kind path)
        ((Some _) #t)
        ((None) #f)))

    (define (directory-names (path String)) (→ (List String)) (! fs building)
      (match (list-directory path)
        ((Ok names) names)
        ((Err error) (fail-build (string-append "cannot read directory " path ": " (show error))))))

    ;; Copies a file's bytes to `to`, making its directory first.

    (define (copy-into (from String) (to String) (failure String)) (→ Unit) (! fs building)
      (unless (kind-is? from (RegularFile))
        (fail-build (string-append failure ": there is no file at " from)))
      (expect-done (make-directories (directory-part to)) failure)
      (write-bytes to (read-bytes from)))

    (define (expect-done (result (Result T FileError)) (failure String))
      (→ Unit)
      (! building)
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
