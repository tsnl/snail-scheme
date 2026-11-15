;; The `snail-scheme` command line, stage 0's one product (scripts/bootstrap),
;; which ./snail-scheme runs on Node, after the repository's root and the
;; runtime modules programs are linked with, plain and the toolchain's:
;;
;;   build --target TARGET [--release] FILE
;;     builds the script FILE for TARGET, node, wasmtime or browser, into
;;     build/PATH of its workspace, PATH being FILE's there without its
;;     extension, publishes it, and prints where its output is;
;;   run --target TARGET [--release] FILE [ARGUMENT ...]
;;     builds the script as `build` does, then becomes it, with the
;;     arguments, in the caller's directory;
;;   wat FILE
;;     prints the WebAssembly text of the script's whole program;
;;   build [--release] PROJECT BUILD-TARGET
;;   run PROJECT RUN-TARGET [ARGUMENT ...]
;;     build and run a target of the project.datum in PROJECT, as until
;;     project files go;
;;   lsp
;;     serves the Language Server Protocol on standard input and output,
;;     (snail shell lsp), for the project the editor opens, as ./snail-scheme lsp
;;     does;
;;   format [--width COLUMNS] [--check|--write FILE ...]
;;     formats standard input to standard output, or reports or rewrites
;;     each file (snail shell format) would change, as ./snail-scheme
;;     format does;
;;   compile MODE SOURCE OUTPUT GENERATED [DIRECTORY ...]
;;     makes one compile, (snail shell compiler driver): the interface stage
;;     0 bootstraps this program through and its test harness compiles with.
;;
;; It is also the engine, (snail shell engine), which host/native/run-snail.mjs
;; and `snail run-wasm` start through the exports of "The engine" to run a
;; program compiled one library at a time: SNAIL_MANIFEST names its
;; manifest.
;;
;; A failure prints its message and exits with status 1; the outputs of
;; earlier builds stay published.
(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (snail shell engine)
 (only (snail shell wasm) wasm)
 (snail shell project)
 (snail shell project build)
 (snail shell lsp)
 (only (snail shell format) format-source format-width)
 (only (snail shell compiler driver) compile-arguments)
 (only (snail shell compiler) source->wat)
 (only (snail shell compiler inputs) no-inputs)
 (only (snail shell compiler read) compiling Failed Requested diagnostics->string Loc)
 (snail shell process))

;; ---- Requests ----

;; What one invocation asks for: a script, or a target of a project.
(enum Request
  (ScriptRequest ((script Script)))
  (ProjectRequest ((job Job))))

;; A project's target. A build's `target` is a build target, a run's a run
;; target.
(record Job
  ((tools Tools)
   (run? Bool)
   (mode Mode)
   (project String)
   (target String)
   (arguments (List String))))

(define (usage) (→ String)
  "usage: snail-scheme build|run --target node|wasmtime|browser [--release] FILE [ARGUMENT ...] | snail-scheme build [--release] PROJECT BUILD-TARGET | snail-scheme run PROJECT RUN-TARGET [ARGUMENT ...]")

;; A request names a target with --target exactly when it is a script's.

(define (request (arguments (List String))) (→ Request) (! fs)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons action rest)))))
     (let ((tools (tools-of root runtime toolchain))
           (run? (cond ((string=? action "build") #f)
                       ((string=? action "run") #t)
                       (else (panic (usage))))))
       (match (build-flags rest (None) (Debug))
         ((Pair (Some flags) rest) (ScriptRequest (script-request tools run? flags rest)))
         ((Pair (None) _)
          (ProjectRequest (if run? (run-request tools rest) (build-request tools rest)))))))
    (_ (panic (usage)))))

(define (tools-of (root String) (runtime String) (toolchain String)) (→ Tools)
  (new Tools
    (root root)
    (runtime runtime)
    (toolchain toolchain)
    (node (match (environment-variable "NODE")
            ((Some node) node)
            ((None) "node")))))

(define (build-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons "--release" (Cons project (Cons target (Nil))))
     (new Job
       (tools tools)
       (run? #f)
       (mode (Release))
       (project (resolved project))
       (target target)
       (arguments (Nil))))
    ((Cons project (Cons target (Nil)))
     (new Job
       (tools tools)
       (run? #f)
       (mode (Debug))
       (project (resolved project))
       (target target)
       (arguments (Nil))))
    (_ (panic (usage)))))

;; ---- Scripts ----

;; Where a script's program runs: on Node, on the native executable, or in
;; a page.
(enum Platform
  (Node)
  (Wasmtime)
  (Browser))

;; The flags every building command takes, parsed here alone.
(record BuildFlags
  ((platform Platform)
   (mode Mode)))

;; A script to build, and to run when `run?`: `file`, in `workspace`, the
;; nearest folder above it that holds src/, where every import resolves.
(record Script
  ((tools Tools)
   (run? Bool)
   (flags BuildFlags)
   (workspace String)
   (file String)
   (arguments (List String))))

;; The leading build flags, and what follows them; no flags when no
;; --target is among them.

(define (build-flags (arguments (List String)) (platform (Option Platform)) (mode Mode))
  (→ (Pair (Option BuildFlags) (List String)))
  (match arguments
    ((Cons "--target" (Cons name rest)) (build-flags rest (Some (platform-named name)) mode))
    ((Cons "--release" rest) (build-flags rest platform (Release)))
    (_ (new Pair
         (first (match platform
                  ((Some platform) (Some (new BuildFlags (platform platform) (mode mode))))
                  ((None) (None))))
         (second arguments)))))

(define (platform-library (platform Platform)) (→ (List String))
  (list "snail"
        "target"
        (match platform
          ((Node) "node")
          ((Wasmtime) "wasmtime")
          ((Browser) "browser"))))

(define (platform-named (name String)) (→ Platform)
  (cond ((string=? name "node") (Node))
        ((string=? name "wasmtime") (Wasmtime))
        ((string=? name "browser") (Browser))
        (else
         (panic (string-append "unknown target " name ": expected node, wasmtime or browser")))))

(define (script-request (tools Tools) (run? Bool) (flags BuildFlags) (arguments (List String)))
  (→ Script)
  (! fs)
  (match arguments
    ((Cons file rest)
     (let ((file (resolved file)))
       (unless (file-exists? file) (panic (string-append "there is no script at " file)))
       (new Script
         (tools tools)
         (run? run?)
         (flags flags)
         (workspace (workspace-of file (directory-of file)))
         (file file)
         (arguments rest))))
    ((Nil) (panic (usage)))))

;; The nearest folder above `file` that holds src/.

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

;; The one build target a script is: a page's, with the public/ folder
;; beside the script if there is one, or a program's.

(define (script-project (script Script)) (→ Project) (! fs)
  (let* ((loc (new Loc (file (● script file)) (line 1) (column 1)))
         (path (lambda (text) (new ProjectPath (text text) (loc loc))))
         (entry (SourceEntry (path (script-path script))))
         (name (script-name script))
         (roots (list (path "src"))))
    (new Project
      (builds (list (match (● (● script flags) platform)
                      ((Browser)
                       (BrowserTarget (new BrowserBuild
                                        (name name)
                                        (entry entry)
                                        (libraries roots)
                                        (public (script-public script path))
                                        (loc loc))))
                      (_
                       (ProgramTarget (new ProgramBuild
                                        (name name)
                                        (entry entry)
                                        (libraries roots)
                                        (platform (platform-library (● (● script flags) platform)))
                                        (loc loc)))))))
      (runs (Nil)))))

(define (script-public (script Script) (path (Fn String → ProjectPath))) (→ (Option ProjectPath))
  (! fs)
  (let ((public (string-append (directory-of (script-path script)) "/public")))
    (if (file-exists? (string-append (● script workspace) "/" public))
        (Some (path public))
        (None))))

;; Builds the script and publishes it; answers its generation.

(define (build-script (script Script)) (→ String) (! mut fs clock process)
  (publish-build (build-project (● script tools)
                                (● script workspace)
                                (script-project script)
                                (list (script-name script))
                                (● (● script flags) mode)
                                (scratch (● script tools))
                                ".snail-")
                 (script-name script)))

;; The script built, then this process, replaced by its program. A page
;; has nothing to run here, so it is refused before it is built.

(define (run-script (script Script)) (→ Unit) (! mut fs clock process)
  (let ((tools (● script tools)))
    (match (● (● script flags) platform)
      ((Node) (become (● tools node)
                      (Cons "--no-warnings"
                            (Cons (string-append (● tools root) "/host/native/run-snail.mjs")
                                  (Cons (built-manifest script) (● script arguments))))))
      ((Wasmtime) (become (string-append (● tools root) "/build/snail")
                          (Cons "run-wasm" (Cons (built-manifest script) (● script arguments)))))
      ((Browser) (panic "a page is not run here: build it, then serve its output")))))

(define (built-manifest (script Script)) (→ String) (! mut fs clock process)
  (string-append (build-script script) "/" (manifest-name (script-name script))))

(define (become (program String) (arguments (List String))) (→ Unit) (! process)
  (let ((error (exec (new Command (program program) (arguments arguments) (directory ".")))))
    (panic (string-append "cannot run " program ": " (● error code)))))

;; The script's whole program as WebAssembly text. A generated library
;; needs a build to run its producer, so here it fails.

(define (print-wat (tools Tools) (arguments (List String))) (→ Unit) (! mut fs output-port)
  (match (build-flags arguments (None) (Debug))
    ((Pair (Some flags) (Cons file (Nil))) (print-script-wat tools flags file))
    (_ (panic "usage: snail-scheme wat --target node|wasmtime|browser FILE"))))

(define (print-script-wat (tools Tools) (flags BuildFlags) (file String)) (→ Unit)
  (! mut fs output-port)
  (let* ((file (resolved file)) (workspace (workspace-of file (directory-of file))))
    (match (compiling (lambda ()
                        (source->wat (delete-duplicates string=?
                                                        (list (string-append workspace "/src")
                                                              (string-append (● tools root)
                                                                             "/src")))
                                     file
                                     (lambda (loading forms)
                                       (panic "wat does not run producers: build the script"))
                                     (no-inputs)
                                     (Some (platform-library (● flags platform))))))
      ((Ok program) (write-string (● program text)))
      ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))
      ((Err (Requested _)) (panic "wat does not run producers: build the script")))))

;; ---- Projects ----

(define (run-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons project (Cons target rest))
     (new Job
       (tools tools)
       (run? #t)
       (mode (Debug))
       (project (resolved project))
       (target target)
       (arguments rest)))
    (_ (panic (usage)))))

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
                           (path-parts absolute))))
    (string-append "/" (string-join (reverse parts) "/"))))

(define (path-parts (path String)) (→ (List String))
  (match (string-index path #\/)
    ((Some index)
     (Cons (substring path 0 index) (path-parts (substring path (+ index 1) (string-length path)))))
    ((None) (list path))))

;; ---- Building ----

;; Builds `target`, with the root's build/snail-run/ for scratch, and
;; publishes it; answers the target's generation.

(define (build-and-publish (job Job) (description Project) (target String))
  (→ String)
  (! mut fs clock process)
  (publish-build (build-project (● job tools)
                                (● job project)
                                description
                                (list target)
                                (● job mode)
                                (scratch (● job tools))
                                ".snail-")
                 target))

(define (publish-build (built (Result Candidate Failure)) (target String)) (→ String) (! fs)
  (match built
    ((Err failure) (panic (failure->string failure)))
    ((Ok candidate)
     (match (publish-project candidate)
       ((Err message) (panic message))
       ((Ok _) (generation-of candidate target))))))

(define (scratch (tools Tools)) (→ String)
  (string-append (● tools root) "/build/snail-run"))

(define (generation-of (candidate Candidate) (target String)) (→ String)
  (match (find (lambda (output) (string=? (● output name) target))
               (● candidate outputs))
    ((Some output) (● output directory))
    ((None) (panic (string-append "internal error: the build did not build " target)))))

;; ---- Running ----

;; The run target's program, built, then this process, replaced by Node
;; running it.

(define (run-target (job Job) (description Project)) (→ Unit) (! mut fs clock process)
  (match (find (lambda (run) (string=? (● run name) (● job target)))
               (● description runs))
    ((None) (panic (string-append "unknown project run target " (● job target))))
    ((Some run)
     (let* ((name (● (● run program) name))
            (generation (build-and-publish job description name))
            (tools (● job tools)))
       (become (● tools node)
               (append (list "--no-warnings"
                             (string-append (● tools root) "/host/native/run-snail.mjs")
                             (string-append generation "/" (manifest-name name)))
                       (append (● run arguments) (● job arguments))))))))

;; ---- Formatting ----

;; What `format` reads and where it answers: standard input to standard
;; output, or files, each reported or rewritten if formatting changes it.
(enum FormatInput
  (StandardInput)
  (CheckFiles ((paths (List String))))
  (WriteFiles ((paths (List String)))))

(record FormatRequest
  ((width I64)
   (input FormatInput)))

(define (format-request (arguments (List String))) (→ FormatRequest)
  (match arguments
    ((Cons "--width" (Cons columns rest))
     (match (string->i64 columns)
       ((Some width)
        (if (> width 0) (new FormatRequest (width width) (input (format-input rest))) (bad-width)))
       ((None) (bad-width))))
    (_ (new FormatRequest (width (format-width)) (input (format-input arguments))))))

(define (bad-width) (→ FormatRequest)
  (panic "snail-scheme format: --width takes a positive number of columns"))

(define (format-input (arguments (List String))) (→ FormatInput)
  (match arguments
    ((Nil) (StandardInput))
    ((Cons "--check" (Cons path rest)) (CheckFiles (Cons path rest)))
    ((Cons "--write" (Cons path rest)) (WriteFiles (Cons path rest)))
    (_ (panic "usage: snail-scheme format [--width COLUMNS] [--write|--check FILE ...]"))))

;; Scalars, not lines, so the end of input invents no final newline.

(define (read-input) (→ String) (! input-port)
  (let loop ((characters (Nil)))
    (match (read-char)
      ((None) (list->string (reverse characters)))
      ((Some char) (loop (Cons char characters))))))

;; Every changed path, in order. Checking leaves files alone; writing
;; leaves formatted files alone, timestamps and all.

(define (format-files (width I64) (write? Bool) (paths (List String))) (→ (List String)) (! fs)
  (let loop ((paths paths) (changed (Nil)))
    (match paths
      ((Nil) (reverse changed))
      ((Cons path rest)
       (let* ((before (read-file path)) (after (format-source before width)))
         (if (string=? before after)
             (loop rest changed)
             (begin
               (when write? (write-file path after))
               (loop rest (Cons path changed)))))))))

;; Every file that needs formatting is reported, not just the first, and
;; then the command fails as any does, with status 1.

(define (check-files (width I64) (paths (List String))) (→ Unit) (! fs)
  (match (format-files width #f paths)
    ((Nil) (unit))
    (changed
     (panic (string-join (map (lambda (path) (string-append path ": needs formatting")) changed)
                         "\n")))))

(define (format-command (request FormatRequest)) (→ Unit) (! input-port output-port fs)
  (match (● request input)
    ((StandardInput) (write-string (format-source (read-input) (● request width))))
    ((CheckFiles paths) (check-files (● request width) paths))
    ((WriteFiles paths) (format-files (● request width) #t paths) (unit))))

;; ---- The engine ----

;; The store is files: an object is read at once, and one that is not
;; there is none.

(define (with-files (body (Fn → A ! linked-content-store e))) (→ A) (! fs e) (∀ (A e))
  (handle linked-content-store
      ((read-object (lambda (path)
                      (if (file-exists? path)
                          (Some (read-bytes path))
                          (None)))))
    (body)))

(define (read-file-resource (engine Engine) (ticket I64) (handle I32)) (→ Unit) (! mut host fs)
  (with-files (lambda () (resource-read engine ticket handle))))

(expose engine-turn "engine:turn")
(expose engine-wake "engine:wake")
(expose engine-close-tasks "engine:close-tasks")
(expose engine-running "engine:running")
(expose engine-live "engine:live")
(expose read-file-resource "resource:read")
(expose resource-finish "resource:finish")
(expose resource-byte "resource:byte")
(expose program-status "engine:status")
(expose close-program "engine:close")

(define (start-engine (engine Engine)) (→ Unit) (! mut host fs wasm)
  (match (environment-variable "SNAIL_MANIFEST")
    ((Some manifest)
     (with-files (lambda () (run-manifest engine manifest (read-file manifest)))))
    ((None) (panic "the engine needs SNAIL_MANIFEST, the manifest of the program to run"))))

(expose make-engine "engine:create")
(expose start-engine "engine:start")

;; ---- The invocation ----

;; A build or a run, of a script or a project's target.

(define (invoke (request Request)) (→ Unit) (! mut fs clock process output-port)
  (match request
    ((ScriptRequest script)
     (if (● script run?)
         (run-script script)
         (begin
           (build-script script)
           (write-line (string-append (● script workspace) "/build/" (script-name script))))))
    ((ProjectRequest job) (invoke-project job))))

(define (invoke-project (job Job)) (→ Unit) (! mut fs clock process output-port)
  (match (read-project (● job project))
    ((Err failure) (panic (failure->string failure)))
    ((Ok description)
     (if (● job run?)
         (run-target job description)
         (begin
           (build-and-publish job description (● job target))
           (write-line (string-append (● job project) "/build/" (● job target))))))))

(define (main)
  (→ Unit)
  (! mut clock fs input-port output-port process)

  (match (command-line)
    ((Cons _ (Cons _ (Cons _ (Cons _ (Cons "compile" arguments))))) (compile-arguments arguments))
    ((Cons _ (Cons _ (Cons _ (Cons _ (Cons "format" arguments)))))
     (format-command (format-request arguments)))
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons "lsp" (Nil))))))
     (serve-language (tools-of root runtime toolchain)))
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons "wat" arguments)))))
     (print-wat (tools-of root runtime toolchain) arguments))
    (arguments (invoke (request arguments))))
  (unit))
