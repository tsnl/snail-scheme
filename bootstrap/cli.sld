;; The `snail-scheme` command line, stage 0's one product (scripts/bootstrap),
;; which ./snail-scheme runs on Node, after the repository's root and the
;; runtime modules programs are linked with, plain and the toolchain's:
;;
;;   build --target TARGET [--release] FILE
;;     builds the script FILE for TARGET, node or browser, into
;;     build/PATH of its workspace, PATH being FILE's there without its
;;     extension, publishes it, and prints where its output is;
;;   run --target TARGET [--release] FILE [ARGUMENT ...]
;;     builds the script as `build` does, then becomes it on Node, with
;;     the arguments, in the caller's directory;
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
  "usage: snail-scheme build|run --target node|browser [--release] FILE [ARGUMENT ...]")

(define (request (fs Fs) (arguments (List String))) (→ ScriptJob) (! mut)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons action rest)))))
     (let ((tools (tools-of root runtime toolchain))
           (run? (cond ((string=? action "build") #f)
                       ((string=? action "run") #t)
                       (else (panic (usage))))))
       (match (build-flags rest (None) (Debug))
         ((Pair (Some flags) rest) (script-request fs tools run? flags rest))
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

;; The flags every building command takes, parsed here alone.
(record BuildFlags
  ((platform Platform)
   (mode Mode)))

;; A script to build, and to run when `run?`, with its arguments.
(record ScriptJob
  ((tools Tools)
   (run? Bool)
   (flags BuildFlags)
   (script Script)
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

(define (platform-named (name String)) (→ Platform)
  (cond ((string=? name "node") (Node))
        ((string=? name "browser") (Browser))
        (else (panic (string-append "unknown target " name ": expected node or browser")))))

(define (script-request (fs Fs)
                        (tools Tools)
                        (run? Bool)
                        (flags BuildFlags)
                        (arguments (List String)))
  (→ ScriptJob)
  (! mut)
  (match arguments
    ((Cons file rest)
     (new ScriptJob
       (tools tools)
       (run? run?)
       (flags flags)
       (script (script-at fs file))
       (arguments rest)))
    ((Nil) (panic (usage)))))

(define (build-job (processes Processes) (fs Fs) (clock Clock) (job ScriptJob)) (→ String) (! mut)
  (build-script processes
                fs
                clock
                (● job tools)
                (● job script)
                (● (● job flags) platform)
                (● (● job flags) mode)))

;; The script built, then this process, replaced by its program on Node.
;; A page has nothing to run here, so it is refused before it is built.

(define (run-script (processes Processes) (fs Fs) (clock Clock) (job ScriptJob)) (→ Unit) (! mut)
  (let ((tools (● job tools)))
    (match (● (● job flags) platform)
      ((Node) (become processes (● tools node)
                      (Cons "--no-warnings"
                            (Cons (string-append (● tools root) "/host/native/run-snail.mjs")
                                  (Cons (built-program processes fs clock job)
                                        (● job arguments))))))
      ((Browser) (panic "a page is not run here: build it, then serve its output")))))

(define (built-program (processes Processes) (fs Fs) (clock Clock) (job ScriptJob))
  (→ String)
  (! mut)
  (string-append (build-job processes fs clock job)
                 "/"
                 (program-name (script-name (● job script)))))

(define (become (processes Processes) (program String) (arguments (List String))) (→ Unit) (! mut)
  (let ((error
         (exec processes (new Command (program program) (arguments arguments) (directory ".")))))
    (panic (string-append "cannot run " program ": " (● error code)))))

;; The script's whole program as WebAssembly text. A generated library
;; needs a build to run its producer, so here it fails.

(define (print-wat (fs Fs) (out OutputPort) (tools Tools) (arguments (List String)))
  (→ Unit)
  (! mut)
  (match (build-flags arguments (None) (Debug))
    ((Pair (Some flags) (Cons file (Nil))) (print-script-wat fs out tools flags file))
    (_ (panic "usage: snail-scheme wat --target node|browser FILE"))))

(define (print-script-wat (fs Fs) (out OutputPort) (tools Tools) (flags BuildFlags) (file String))
  (→ Unit)
  (! mut)
  (let ((script (script-at fs file)))
    (match (compiling (lambda ()
                        (source->wat fs (workspace-directories tools (● script workspace))
                                     (● script file)
                                     (lambda (loading forms)
                                       (panic "wat does not run producers: build the script"))
                                     (Some (platform-library (● flags platform)))
                                     (Nil))))
      ((Ok program) (write-string out (● program text)))
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
    (_ (new FormatRequest (width format-width) (input (format-input arguments))))))

(define (bad-width) (→ FormatRequest)
  (panic "snail-scheme format: --width takes a positive number of columns"))

(define (format-input (arguments (List String))) (→ FormatInput)
  (match arguments
    ((Nil) (StandardInput))
    ((Cons "--check" (Cons path rest)) (CheckFiles (Cons path rest)))
    ((Cons "--write" (Cons path rest)) (WriteFiles (Cons path rest)))
    (_ (panic "usage: snail-scheme format [--width COLUMNS] [--write|--check FILE ...]"))))

;; Scalars, not lines, so the end of input invents no final newline.

(define (read-input (in InputPort)) (→ String) (! mut)
  (let loop ((characters (Nil)))
    (match (read-char in)
      ((None) (list->string (reverse characters)))
      ((Some char) (loop (Cons char characters))))))

;; Every changed path, in order. Checking leaves files alone; writing
;; leaves formatted files alone, timestamps and all.

(define (format-files (fs Fs) (width I64) (write? Bool) (paths (List String)))
  (→ (List String))
  (! mut)
  (let loop ((paths paths) (changed (Nil)))
    (match paths
      ((Nil) (reverse changed))
      ((Cons path rest)
       (let* ((before (read-file fs path)) (after (format-source before width)))
         (if (string=? before after)
             (loop rest changed)
             (begin
               (when write? (write-file fs path after))
               (loop rest (Cons path changed)))))))))

;; Every file that needs formatting is reported, not just the first, and
;; then the command fails as any does, with status 1.

(define (check-files (fs Fs) (width I64) (paths (List String))) (→ Unit) (! mut)
  (match (format-files fs width #f paths)
    ((Nil) (unit))
    (changed
     (panic (string-join (map (lambda (path) (string-append path ": needs formatting")) changed)
                         "\n")))))

(define (format-command (fs Fs) (in InputPort) (out OutputPort) (request FormatRequest))
  (→ Unit)
  (! mut)
  (match (● request input)
    ((StandardInput) (write-string out (format-source (read-input in) (● request width))))
    ((CheckFiles paths) (check-files fs (● request width) paths))
    ((WriteFiles paths) (format-files fs (● request width) #t paths) (unit))))

;; ---- The invocation ----

;; A script's build, or its run.

(define (invoke (processes Processes) (fs Fs) (clock Clock) (out OutputPort) (job ScriptJob))
  (→ Unit)
  (! mut)
  (if (● job run?)
      (run-script processes fs clock job)
      (begin
        (build-job processes fs clock job)
        (write-line out
                    (string-append (● (● job script) workspace)
                                   "/build/"
                                   (script-name (● job script)))))))

(define (main (processes Processes) (fs Fs) (clock Clock) (in InputPort) (out OutputPort))
  (→ Unit)
  (! mut)

  (match (command-line)
    ((Cons _ (Cons _ (Cons _ (Cons _ (Cons "compile" arguments)))))
     (compile-arguments fs arguments))
    ((Cons _ (Cons _ (Cons _ (Cons _ (Cons "format" arguments)))))
     (format-command fs in out (format-request arguments)))
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons "lsp" (Nil))))))
     (serve-language processes fs clock in out (tools-of root runtime toolchain)))
    ((Cons _ (Cons root (Cons runtime (Cons toolchain (Cons "wat" arguments)))))
     (print-wat fs out (tools-of root runtime toolchain) arguments))
    (arguments (invoke processes fs clock out (request fs arguments))))
  (unit))
