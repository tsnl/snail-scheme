;; The `snail-scheme` command line, stage 0's one product (scripts/bootstrap),
;; which ./snail-scheme runs on Node, after the repository's root and the
;; runtime modules programs are linked with, plain and the toolchain's:
;;
;;   build [--release] PROJECT BUILD-TARGET
;;     builds a target, publishes it, and prints where its output is;
;;   run PROJECT RUN-TARGET [ARGUMENT ...]
;;     builds a run target's program, publishes it, and becomes it, with the
;;     run's arguments and then these, in the caller's directory;
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
 (snail shell process))

;; ---- Requests ----

;; What one invocation asks for. A build's `target` is a build target, a
;; run's a run target.
(record Job
  ((tools Tools)
   (run? Bool)
   (mode Mode)
   (project String)
   (target String)
   (arguments (List String))))

(define (usage) (→ String)
  "usage: snail-scheme build [--release] PROJECT BUILD-TARGET | snail-scheme run PROJECT RUN-TARGET [ARGUMENT ...]")

(define (request (arguments (List String))) (→ Job)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons action rest)))))
     (let ((tools (tools-of root runtime toolchain)))
       (cond ((string=? action "build") (build-request tools rest))
             ((string=? action "run") (run-request tools rest))
             (else (panic (usage))))))
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
  (match (build-project (● job tools)
                        (● job project)
                        description
                        (list target)
                        (● job mode)
                        (scratch job)
                        ".snail-")
    ((Err failure) (panic (failure->string failure)))
    ((Ok candidate)
     (match (publish-project candidate)
       ((Err message) (panic message))
       ((Ok _) (generation-of candidate target))))))

(define (scratch (job Job)) (→ String)
  (string-append (● (● job tools) root) "/build/snail-run"))

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
            (tools (● job tools))
            (error (exec (new Command (program (● tools node))
                              (arguments (append (list "--no-warnings"
                                                       (string-append (● tools root)
                                                                      "/host/native/run-snail.mjs")
                                                       (string-append generation
                                                                      "/"
                                                                      (manifest-name name)))
                                                 (append (● run arguments) (● job arguments))))
                              (directory ".")))))
       (panic (string-append "cannot run " (● tools node) ": " (● error code)))))))

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

;; A build or a run.

(define (invoke (job Job)) (→ Unit) (! mut fs clock process output-port)
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
    (arguments (invoke (request arguments))))
  (unit))
