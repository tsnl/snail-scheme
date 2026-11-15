;; snailc, the single-file compiler: one source file, not a project,
;; compiled with the compiler inside it, assembled and linked in-process,
;; beside `snail-scheme` as `lli` sits beside `clang`. It is an ordinary
;; program of the repository's project, linked with the toolchain's
;; runtime, whose services include the assembler:
;;
;;   ./snail-scheme run . snailc wat [-I DIRECTORY] SOURCE
;;   ./snail-scheme run . snailc compile [-I DIRECTORY] -o OUTPUT SOURCE
;;   ./snail-scheme run . snailc run [-I DIRECTORY] SOURCE [ARGUMENT ...]
;;
;; `wat` prints the program's text; `compile`
;; writes OUTPUT, a runnable module, and OUTPUT.wat; `run` runs the program
;; with the arguments, and becomes it. A source's libraries resolve in each
;; -I directory, then src/. The launcher names the repository and the
;; runtime programs link with (SNAIL_ROOT, SNAIL_RUNTIME). What needs a
;; project's build, a `generate-library` recipe's producer or the files a
;; program links, fails the compile here.
(import
 (snail core base)
 (snail core io)
 (only (snail shell compiler driver) compile-arguments)
 (only (snail shell assembler) link)
 (snail shell process))

;; ---- Requests ----

;; What to do with the compile: print its text, write the linked program,
;; or run it.
(enum Action
  (Print)
  (Write ((path String)))
  (Run))

(record Request
  ((action Action)
   (directories (List String))
   (source String)
   (arguments (List String))))

(define (usage) (→ String)
  "usage: snailc wat|compile -o OUTPUT|run [-I DIRECTORY] SOURCE [ARGUMENT ...]")

(define (request (arguments (List String))) (→ Request)
  (match arguments
    ((Cons name rest) (options name (Nil) (None) rest))
    ((Nil) (panic (usage)))))

(define (options (name String)
                 (directories (List String))
                 (output (Option String))
                 (arguments (List String)))
  (→ Request)
  (match arguments
    ((Cons "-I" (Cons directory rest)) (options name (Cons directory directories) output rest))
    ((Cons "-o" (Cons path rest)) (options name directories (Some path) rest))
    ((Cons source rest)
     (new Request (action (action name output)) (directories (reverse directories))
          (source source) (arguments rest)))
    ((Nil) (panic (usage)))))

(define (action (name String) (output (Option String))) (→ Action)
  (match (new Pair (first name) (second output))
    ((Pair "wat" (None)) (Print))
    ((Pair "compile" (Some path)) (Write path))
    ((Pair "run" (None)) (Run))
    (_ (panic (usage)))))

;; ---- The repository ----

(define (setting (name String)) (→ String)
  (match (environment-variable name)
    ((Some value) value)
    ((None)
     (panic (string-append "snailc: " name " is unset; run it as ./snail-scheme run . snailc")))))

(define (library-directories (request Request)) (→ (List String))
  (append (● request directories) (list (string-append (setting "SNAIL_ROOT") "/src"))))

;; A directory of this run's own under build/snailc-work, removed once `work`
;; is done with it.

(define (with-scratch (work (Fn String → T ! mut fs e))) (→ T) (! mut fs e) (∀ (T e))
  (let* ((base (string-append (setting "SNAIL_ROOT") "/build/snailc-work"))
         (scratch (begin (done (make-directories base) base) (fresh-directory base 0)))
         (result (work scratch)))
    (done (remove-tree scratch) scratch)
    result))

(define (done (result (Result T FileError)) (path String)) (→ Unit) (∀ (T))
  (match result
    ((Ok _) (unit))
    ((Err error) (panic (string-append "snailc: " path ": " (show error))))))

(define (fresh-directory (base String) (number I64)) (→ String) (! fs)
  (let ((path (string-append base "/scratch-" (show number))))
    (match (make-directory path)
      ((Ok _) path)
      ((Err (AlreadyExists)) (fresh-directory base (+ number 1)))
      ((Err error) (panic (string-append "snailc: cannot make " path ": " (show error)))))))

;; ---- Compiling ----

;; The compile's output in `mode`, made in `scratch`.

(define (compiled (request Request) (mode String) (scratch String)) (→ String) (! mut fs)
  (let ((output (string-append scratch "/output")) (generated (string-append scratch "/generated")))
    (done (make-directories generated) generated)
    (compile-arguments
     (append (list mode (● request source) output generated) (library-directories request)))
    (when (and (file-exists? (string-append generated "/links.datum"))
               (not (string=? (read-file (string-append generated "/links.datum")) "")))
      (panic "snailc: the program links files, which only a project's build places"))
    (read-file output)))

(define (linked (text String)) (→ Bytes) (! fs)
  (match (link text (read-bytes (setting "SNAIL_RUNTIME")))
    ((Ok bytes) bytes)
    ((Err message) (panic (string-append "snailc: cannot link: " message)))))

;; The program, linked, at `path`, its text beside it.

(define (write-program (request Request) (path String)) (→ Unit) (! mut fs)
  (let ((text (with-scratch (lambda (scratch) (compiled request "wat" scratch)))))
    (write-file (string-append path ".wat") text)
    (write-bytes path (linked text))))

;; ---- Running ----

;; A run's program is build/snailc-work/NAME.wasm, for the source's NAME, written
;; whole in scratch of its own before it is renamed there, so a run never
;; starts half of one; two runs of one source write the same bytes.

(define (run-program (request Request)) (→ Unit) (! mut fs process)
  (let ((root (setting "SNAIL_ROOT"))
        (program (string-append (setting "SNAIL_ROOT") "/build/snailc-work/"
                                (source-name (● request source)) ".wasm")))
    (with-scratch (lambda (scratch)
                    (let ((written (string-append scratch "/program.wasm")))
                      (write-program request written)
                      (done (rename-file written program) program))))
    (let ((error (exec (new Command (program (node))
                            (arguments (append (list "--no-warnings"
                                                     (string-append root
                                                                    "/host/native/run-snail.mjs")
                                                     program)
                                               (● request arguments)))
                            (directory ".")))))
      (panic (string-append "snailc: cannot run " (node) ": " (● error code))))))

(define (node) (→ String)
  (match (environment-variable "NODE") ((Some node) node) ((None) "node")))

;; The source's file name, without a directory or `.sld`.

(define (source-name (source String)) (→ String)
  (let* ((name (file-name (string->vector source) (string-length source)))
         (length (string-length name)))
    (if (and (> length 4) (string=? (substring name (- length 4) length) ".sld"))
        (substring name 0 (- length 4))
        name)))

(define (file-name (chars (Vector Char)) (end I64)) (→ String)
  (let loop ((start end))
    (if (and (> start 0) (not (char=? (vector-ref chars (- start 1)) #\/)))
        (loop (- start 1))
        (vector->string (subvector chars start end)))))

;; ---- The invocation ----

(define (perform (request Request)) (→ Unit) (! mut fs process output-port)
  (match (● request action)
    ((Print) (write-string (with-scratch (lambda (scratch) (compiled request "wat" scratch)))))
    ((Write path) (write-program request path))
    ((Run) (run-program request))))

(define (main) (→ Unit) (! mut fs process output-port)
  (match (command-line)
    ((Cons _ arguments) (perform (request arguments)))
    ((Nil) (panic (usage)))))
