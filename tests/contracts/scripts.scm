;; Scripts: a source file built and run for an explicit target, with its
;; imports under its workspace's src/ and its output at build/PATH.
;;
;;   ./snail-scheme run --target node tests/contracts/scripts.scm ROOT
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (snail shell json)
 (snail shell json read)
 (contracts support))

(define script
  (→ String)
  (string-append "(import (snail core base) (snail core io) (tools greeting))\n"
                 "(define (main (arguments Arguments) (out OutputPort)) (→ Unit)\n"
                 "  (write-line out (greeting))\n"
                 "  (match (command-line arguments)\n"
                 "    ((Cons _ rest) (for-each (lambda (argument) (write-line out argument)) rest))\n"
                 "    ((Nil) (unit))))\n"))

;; The visible names in a directory, sorted.
(define (files (c Context) (directory String)) (→ (List String))
  (match (list-directory (● c fs) directory)
    ((Ok names)
     (list-sort string<? (filter (lambda (name) (not (contains? (substring name 0 1) "."))) names)))
    ((Err why) (panic (string-append directory ": " (show why))))))

(define (manifest (c Context) (directory String)) (→ Json)
  (match (string->json (text-of c (string-append directory "/package.json")))
    ((Some json) json)
    ((None) (panic "package.json is not JSON"))))

(define (size (c Context) (file String)) (→ I64)
  (match (file-status (● c fs) file)
    ((Ok status) (● status size))
    ((Err why) (panic (string-append file ": " (show why))))))

(define (packages (c Context) (workspace String)) (→ Unit)
  (let* ((in (lambda ((name String)) (→ String) (string-append workspace "/" name)))
         (output (in "build/apps/hello/main"))
         (build (lambda ((arguments (List String))) (→ Ran)
                  (succeeded (snail c (Cons "build" arguments) workspace) "build"))))
    (expect-text (first-line (● (build (list "--target" "node" "apps/hello/main.scm")) stdout))
                 output
                 "the output is the script path without its extension")
    (let ((generation (resolved c output)))
      (expect (string=? (parent-of generation) (parent-of output))
              "the generation lies beside its link")
      (expect
       (equal-names? (files c generation) (list "host" "main.mjs" "main.wasm" "package.json"))
       "a Node build is an npm package around one linked module, named for the script")
      (expect-text (json->string (manifest c generation))
                   (json->string
                    (JsonObject (list (field "name" (JsonString "main"))
                                      (field "private" (JsonBool #t))
                                      (field "scripts"
                                             (JsonObject
                                              (list (field "start" (JsonString "node main.mjs")))))
                                      (field "bin"
                                             (JsonObject
                                              (list (field "main" (JsonString "main.mjs"))))))))
                   "which npm starts, whose one command runs the module, and which depends on nothing")
      (let ((ran (succeeded
                  (snail c (list "run" "--target" "node" "apps/hello/main.scm" "one" "two words")
                         workspace)
                  "run")))
        (expect-text (● ran stdout) "hello from src\none\ntwo words\n"
                     "run runs the script with its arguments")
        (standalone c generation (● ran stdout))))))

;; The package copied elsewhere runs on its own, and through npm.
(define (standalone (c Context) (generation String) (printed String)) (→ Unit)
  (let* ((elsewhere (scratch c "package"))
         (hello (string-append elsewhere "/hello")))
    (succeeded (command c "cp" (list "-R" generation hello) "/" "") "copying the package")
    (let ((packaged (node c (list (string-append hello "/main.mjs") "one" "two words") elsewhere)))
      (expect-text (● packaged stdout) printed "the package runs on its own, as run does")
      (expect-text (● packaged stderr) "" "and warns of nothing")
      (let ((started (command c "npm"
                              (list "start"
                                    "--silent"
                                    "--no-update-notifier"
                                    "--"
                                    "one"
                                    "two words")
                              hello "")))
        (expect-text (● started stdout) printed "as it does through npm")))
    (removed! c elsewhere)))

(define (drawing (c Context) (workspace String)) (→ Unit)
  (put! c (string-append workspace "/apps/drawing/main.scm")
        (string-append "(import (snail core base) (snail core io) (snail shell gpu)) "
                       "(define (main (out OutputPort)) (→ Unit) (write-line out \"no device asked for\"))"))
  (succeeded (snail c (list "build" "--target" "node" "apps/drawing/main.scm") workspace)
             "build drawing")
  (let* ((output (string-append workspace "/build/apps/drawing/main"))
         (pinned (member-of (manifest c (● c root)) "dependencies")))
    (expect-text (json->string (member-of (manifest c output) "dependencies")) (json->string pinned)
                 "a program that may ask for a device depends on the repository's webgpu and @napi-rs/canvas")
    (expect-text (● (node c (list (string-append output "/main.mjs")) workspace) stdout)
                 "no device asked for\n"
                 "and runs without it until it asks")))

(define (releases (c Context) (workspace String)) (→ Unit)
  (let* ((output (string-append workspace "/build/apps/hello/main"))
         (debug (size c (string-append (resolved c output) "/main.wasm"))))
    (succeeded
     (snail c (list "build" "--release" "--target" "node" "apps/hello/main.scm") workspace)
     "release")
    (let ((release (resolved c output)))
      (expect (equal-names? (files c release) (list "host" "main.mjs" "main.wasm" "package.json"))
              "a release build is the same package")
      (expect (< (size c (string-append release "/main.wasm")) debug)
              "which wasm-opt made smaller"))
    (expect-text
     (● (succeeded (snail c (list "run" "--release" "--target" "node" "apps/hello/main.scm" "one")
                          workspace)
                   "release run")
        stdout)
     "hello from src\none\n" "run runs the release build")))

(define (pages (c Context) (workspace String)) (→ Unit)
  (let ((output (string-append workspace "/build/apps/hello/main")))
    (put! c
          (string-append workspace "/apps/hello/public/index.html")
          "<!doctype html><title>Hello</title>")
    (succeeded (snail c (list "build" "--target" "browser" "apps/hello/main.scm") workspace)
               "page build")
    (let ((page (resolved c output)))
      (expect (contains? (text-of c (string-append page "/index.html")) "content=\"./main.wasm\"")
              "a page names its module")
      (expect (member? "host.mjs" (files c page)) "a page holds the browser host"))
    (failed-with (snail c (list "run" "--target" "browser" "apps/hello/main.scm") workspace)
                 "a page is not run here" "running a page")
    (succeeded
     (snail c (list "build" "--release" "--target" "browser" "apps/hello/main.scm") workspace)
     "release page build")
    (expect (contains? (text-of c (string-append (resolved c output) "/index.html"))
                       "content=\"./main.wasm\"")
            "as a release page does")))

(define (refusals (c Context) (workspace String)) (→ Unit)
  (failed-with (snail c (list "run" "--target" "deno" "apps/hello/main.scm") workspace)
               "unknown target deno" "an unknown target")
  (failed-with (snail c (list "run" "--target" "node" "apps/missing.scm") workspace)
               "there is no script at" "a missing script")
  (let ((outside (scratch c "no-workspace")))
    (put! c (string-append outside "/lost.scm") script)
    (failed-with
     (snail c (list "build" "--target" "node" (string-append outside "/lost.scm")) outside)
     "holds src/" "a script with no workspace")
    (removed! c outside))
  (expect
   (starts-with? (● (snail c (list "wat" "--target" "node" "apps/hello/main.scm") workspace) stdout)
                 "(module")
   "wat prints the module's text"))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let* ((c (context arguments fs processes environment))
         (workspace (scratch c "scripts")))
    (put! c (string-append workspace "/src/tools/greeting.sld")
          (string-append
           "(define-library (tools greeting) (export greeting) (import (snail core base)) "
           "(begin (define (greeting) (→ String) \"hello from src\")))"))
    (put! c (string-append workspace "/apps/hello/main.scm") script)
    (packages c workspace)
    (drawing c workspace)
    (releases c workspace)
    (pages c workspace)
    (refusals c workspace)
    (removed! c workspace)
    (write-line out "scripts passed")))

;; ---- Helpers ----

(define (field (name String) (value Json)) (→ (Pair String Json))
  (new Pair (first name) (second value)))

(define (member-of (json Json) (name String)) (→ Json)
  (match json
    ((JsonObject fields)
     (match (find (lambda (field) (string=? (● field first) name)) fields)
       ((Some found) (● found second))
       ((None) (panic (string-append "no " name " in the manifest")))))
    (_ (panic "the manifest is not an object"))))

(define (equal-names? (a (List String)) (b (List String))) (→ Bool)
  (and (= (length a) (length b)) (every? (lambda (name) (member? name b)) a)))

(define (parent-of (path String)) (→ String)
  (let loop ((at (- (string-length path) 1)))
    (cond ((<= at 0) "/")
          ((char=? (string-ref path at) #\/) (substring path 0 at))
          (else (loop (- at 1))))))

(define (first-line (text String)) (→ String)
  (match (string-index text #\newline)
    ((Some at) (substring text 0 at))
    ((None) text)))

(define (starts-with? (text String) (prefix String)) (→ Bool)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))
