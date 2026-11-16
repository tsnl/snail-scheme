;; The `snail-scheme` command line, stage 0's one product (scripts/bootstrap),
;; which ./snail-scheme runs on Node, after the repository's root and the
;; runtime modules programs are linked with, plain and the toolchain's:
;;
;;   build --target TARGET [--release] FILE
;;     builds the script FILE for TARGET, node, wasmtime, browser or
;;     portable, into build/PATH of its workspace, PATH being FILE's there
;;     without its extension, publishes it, and prints where its output is;
;;   run --target TARGET [--release] [--engine ENGINE] FILE [ARGUMENT ...]
;;     builds the script as `build` does, then becomes it, with the
;;     arguments, in the caller's directory, on ENGINE, node or wasmtime:
;;     without one, the engine TARGET is named for, and node for portable;
;;   wat --target TARGET FILE
;;     prints the WebAssembly text of the script's whole program;
;;   lsp
;;     serves the Language Server Protocol on standard input and output,
;;     (snail shell lsp), for the workspace the editor opens, as
;;     ./snail-scheme lsp does;
;;   format [--width COLUMNS] [--check|--write FILE ...]
;;     formats standard input to standard output, or reports or rewrites
;;     each file (snail shell format) would change, as ./snail-scheme
;;     format does;
;;   compile TARGET SOURCE OUTPUT [DIRECTORY ...]
;;     makes one compile, (snail shell compiler driver): the interface stage
;;     0 bootstraps this program through.
;;
;; A failure prints its message and exits with status 1; the outputs of
;; earlier builds stay published.
(import
 (snail core base)
 (snail core io)
 (snail shell project build)
 (snail shell lsp)
 (only (snail shell format) format-source format-width)
 (only (snail shell compiler driver) compile-arguments)
 (only (snail shell compiler) source->wat)
 (only (snail shell compiler read) compiling Failed Requested diagnostics->string Loc)
 (snail shell process))

;; ---- Requests ----

;; What a build or run names: a script, with --target.

(define (usage) (→ String)
  "usage: snail-scheme build|run --target node|wasmtime|browser|portable [--release] FILE [ARGUMENT ...]")

(define (request (arguments (List String))) (→ ScriptJob) (! fs)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons action rest)))))
     (let ((tools (tools-of root runtime toolchain))
           (run? (cond ((string=? action "build") #f)
                       ((string=? action "run") #t)
                       (else (panic (usage))))))
       (match (build-flags rest (None) (Debug) (None))
         ((Pair (Some flags) rest)
          (script-request tools run? (if run? flags (without-engine flags)) rest))
         ((Pair (None) _) (panic (usage))))))
    (_ (panic (usage)))))

(define (tools-of (root String) (runtime String) (toolchain String)) (→ Tools)
  (new Tools
    (root root)
    (runtime runtime)
    (toolchain toolchain)
    (node (match (environment-variable "NODE")
            ((Some node) node)
            ((None) "node")))
    (building (Nil))))

;; ---- Scripts ----

;; What runs a built program. A target names the capabilities a program
;; may use, not its host: every build but a page's runs on either engine,
;; where a call to a capability the engine lacks traps.
(enum Engine
  (OnNode)
  (OnWasmtime))

;; The flags every building command takes, parsed here alone, and the
;; engine `run` was told to use.
(record BuildFlags
  ((platform Platform)
   (mode Mode)
   (engine (Option Engine))))

;; A script to build, and to run when `run?`, with its arguments.
(record ScriptJob
  ((tools Tools)
   (run? Bool)
   (flags BuildFlags)
   (script Script)
   (arguments (List String))))

;; The leading build flags, and what follows them; no flags when no
;; --target is among them.

(define (build-flags (arguments (List String))
                     (platform (Option Platform))
                     (mode Mode)
                     (engine (Option Engine)))
  (→ (Pair (Option BuildFlags) (List String)))
  (match arguments
    ((Cons "--target" (Cons name rest))
     (build-flags rest (Some (platform-named name)) mode engine))
    ((Cons "--release" rest) (build-flags rest platform (Release) engine))
    ((Cons "--engine" (Cons name rest))
     (build-flags rest platform mode (Some (engine-named name))))
    (_ (new Pair
         (first (match platform
                  ((Some platform)
                   (Some (new BuildFlags (platform platform) (mode mode) (engine engine))))
                  ((None) (None))))
         (second arguments)))))

(define (engine-named (name String)) (→ Engine)
  (cond ((string=? name "node") (OnNode))
        ((string=? name "wasmtime") (OnWasmtime))
        (else (panic (string-append "unknown engine " name ": expected node or wasmtime")))))

;; Only `run` chooses an engine.

(define (without-engine (flags BuildFlags)) (→ BuildFlags)
  (match (● flags engine)
    ((Some _) (panic "--engine belongs to run: a build runs on either engine"))
    ((None) flags)))

(define (platform-named (name String)) (→ Platform)
  (cond ((string=? name "node") (Node))
        ((string=? name "wasmtime") (Wasmtime))
        ((string=? name "browser") (Browser))
        ((string=? name "portable") (Portable))
        (else
         (panic (string-append "unknown target "
                               name
                               ": expected node, wasmtime, browser or portable")))))

(define (script-request (tools Tools) (run? Bool) (flags BuildFlags) (arguments (List String)))
  (→ ScriptJob)
  (! fs)
  (match arguments
    ((Cons file rest)
     (new ScriptJob
       (tools tools)
       (run? run?)
       (flags flags)
       (script (script-at file))
       (arguments rest)))
    ((Nil) (panic (usage)))))

(define (build-job (job ScriptJob)) (→ String) (! mut fs clock process)
  (build-script (● job tools) (● job script) (● (● job flags) platform) (● (● job flags) mode)))

;; The script built, then this process, replaced by its program on the
;; job's engine.

(define (run-script (job ScriptJob)) (→ Unit) (! mut fs clock process)
  (let ((tools (● job tools)))
    (match (job-engine (● job flags))
      ((OnNode) (become (● tools node)
                        (Cons "--no-warnings"
                              (Cons (string-append (● tools root) "/host/native/run-snail.mjs")
                                    (Cons (built-program job) (● job arguments))))))
      ((OnWasmtime) (become (string-append (● tools root) "/build/snail")
                            (Cons "run-wasm" (Cons (built-program job) (● job arguments))))))))

;; The engine asked for, or else the one the target is named for; a
;; portable program names none and runs on Node, as this command line
;; does. A page has nothing to run here, so it is refused before it is
;; built.

(define (job-engine (flags BuildFlags)) (→ Engine)
  (match (new Pair (first (● flags platform)) (second (● flags engine)))
    ((Pair (Browser) _) (panic "a page is not run here: build it, then serve its output"))
    ((Pair _ (Some engine)) engine)
    ((Pair (Wasmtime) _) (OnWasmtime))
    (_ (OnNode))))

(define (built-program (job ScriptJob)) (→ String) (! mut fs clock process)
  (string-append (build-job job)
                 "/"
                 (program-name (script-name (● job script)))))

(define (become (program String) (arguments (List String))) (→ Unit) (! process)
  (let ((error (exec (new Command (program program) (arguments arguments) (directory ".")))))
    (panic (string-append "cannot run " program ": " (● error code)))))

;; The script's whole program as WebAssembly text. A generated library
;; needs a build to run its producer, so here it fails.

(define (print-wat (tools Tools) (arguments (List String))) (→ Unit) (! mut fs output-port)
  (match (build-flags arguments (None) (Debug) (None))
    ((Pair (Some flags) (Cons file (Nil))) (print-script-wat tools (without-engine flags) file))
    (_ (panic "usage: snail-scheme wat --target node|wasmtime|browser|portable FILE"))))

(define (print-script-wat (tools Tools) (flags BuildFlags) (file String)) (→ Unit)
  (! mut fs output-port)
  (let ((script (script-at file)))
    (match (compiling (lambda ()
                        (source->wat (workspace-directories tools (● script workspace))
                                     (● script file)
                                     (lambda (loading forms)
                                       (panic "wat does not run producers: build the script"))
                                     (Some (platform-library (● flags platform))))))
      ((Ok program) (write-string (● program text)))
      ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))
      ((Err (Requested _)) (panic "wat does not run producers: build the script")))))

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

;; ---- The invocation ----

;; A script's build, or its run.

(define (invoke (job ScriptJob)) (→ Unit) (! mut fs clock process output-port)
  (if (● job run?)
      (run-script job)
      (begin
        (build-job job)
        (write-line
         (string-append (● (● job script) workspace) "/build/" (script-name (● job script)))))))

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
