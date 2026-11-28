;; `./snail-scheme` asks stage 0 for its tools only when something stage 0's
;; rule reads may have changed. The launcher runs here in a root of its own,
;; with stage 0 (scripts/bootstrap) and Node replaced by scripts that count
;; their calls, so nothing is built:
;;
;;   ./snail-scheme run --target node tests/contracts/launcher.scm ROOT
;;
;; A second call reuses the first's answer; an edit to a source, the runtime
;; crate or stage 0, a missing tool, and an edit made while stage 0 runs each
;; ask again; a file that is no input does not; a failure caches nothing;
;; and every command shares the answer.
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (contracts support))

;; Stage 0 names the command line and the two runtimes, making each. It can
;; be told to fail, or to edit a source while it runs.
(define stage-0
  (→ String)
  (string-append "#!/bin/sh\n"
                 "root=$(CDPATH= cd -- \"$(dirname -- \"$0\")/..\" && pwd)\n"
                 "echo bootstrap >> \"$root/stage0.calls\"\n"
                 "[ -f \"$root/stage0.fails\" ] && exit 1\n"
                 "[ -f \"$root/stage0.edits\" ] && touch \"$root/src/a.sld\"\n"
                 "mkdir -p \"$root/build\"\n"
                 "for tool in cli runtime toolchain; do : > \"$root/build/$tool.wasm\"; "
                 "echo \"$root/build/$tool.wasm\"; done\n"))

;; Node records its arguments.
(define (fake-node (root String)) (→ String)
  (string-append "#!/bin/sh\necho \"$*\" >> \"" root "/node.calls\"\n"))

(record Launcher
  ((c Context)
   (root String)))

(define (at (l Launcher) (name String)) (→ String)
  (string-append (● l root) "/" name))

(define (calls (l Launcher) (name String)) (→ (List String))
  (if (file-exists? (● (● l c) fs) (at l name))
      (filter (lambda (line) (not (string=? line ""))) (lines (text-of (● l c) (at l name))))
      (Nil)))

(define (touch! (l Launcher) (name String)) (→ Unit)
  (succeeded (command (● l c) "touch" (list (at l name)) "/" "") "touch")
  (unit))

;; The launcher run with Node replaced.
(define (launch (l Launcher) (arguments (List String))) (→ Ran)
  (command (● l c) "env"
           (Cons (string-append "NODE=" (at l "node")) (Cons (at l "snail-scheme") arguments))
           (● l root) ""))

;; A build through the launcher, and how often stage 0 has been asked.
(define (build (l Launcher)) (→ I64)
  (succeeded (launch l (list "build" "project" "target")) "build")
  (length (calls l "stage0.calls")))

(define (tools (l Launcher)) (→ String)
  (string-join (list (at l "build/cli.wasm")
                     (● l root)
                     (at l "build/runtime.wasm")
                     (at l "build/toolchain.wasm"))
               " "))

(define (last-node-call (l Launcher)) (→ String)
  (match (reverse (calls l "node.calls"))
    ((Cons call _) call)
    ((Nil) "")))

(define (ends-with? (text String) (suffix String)) (→ Bool)
  (and (>= (string-length text) (string-length suffix))
       (string=?
        (substring text (- (string-length text) (string-length suffix)) (string-length text))
        suffix)))

(define (lay-out! (l Launcher)) (→ Unit)
  (let ((c (● l c)))
    (succeeded
     (command c "cp" (list (string-append (● c root) "/snail-scheme") (at l "snail-scheme")) "/" "")
     "cp")
    (put! c (at l "scripts/bootstrap") stage-0)
    (put! c (at l "node") (fake-node (● l root)))
    (succeeded (command c
                        "chmod"
                        (list "755" (at l "snail-scheme") (at l "scripts/bootstrap") (at l "node"))
                        "/"
                        "")
               "chmod")
    (for-each (lambda (name) (put! c (at l name) ""))
              (list "src/a.sld" "bootstrap/cli.sld" "host/browser/host.mjs" "host/chez/load.scm"
                    "rust-toolchain.toml" "crates/snail-scheme-support/Cargo.toml"
                    "crates/snail-scheme-support/src/lib.rs"))))

(define (caching (l Launcher)) (→ Unit)
  (expect (= (build l) 1) "the first call asks stage 0")
  (expect (ends-with? (last-node-call l) (string-append (tools l) " build project target"))
          "and hands Node the tools and the command")
  (expect (= (build l) 1) "the second reuses its answer")
  (for-each (lambda (input)
              (let ((before (length (calls l "stage0.calls"))))
                (touch! l input)
                (expect (= (build l) (+ before 1))
                        (string-append "an edit to " input " asks again"))
                (expect (= (build l) (+ before 1)) (string-append "once, for " input))))
            (list "src/a.sld"
                  "bootstrap/cli.sld"
                  "crates/snail-scheme-support/src/lib.rs"
                  "rust-toolchain.toml"
                  "host/chez/load.scm"))
  (touch! l "host/browser/host.mjs")
  (expect (= (build l) 6) "a file stage 0 does not read is no reason to ask")
  (removed! (● l c) (at l "build/cli.wasm"))
  (expect (= (build l) 7) "a missing tool asks again")
  (expect (file-exists? (● (● l c) fs) (at l "build/cli.wasm")) "and stage 0 made it"))

(define (edits-and-failures (l Launcher)) (→ Unit)
  (let ((c (● l c)))
    (put! c (at l "stage0.edits") "")
    (touch! l "src/a.sld")
    (expect (= (build l) 8) "an edit asks again")
    (removed! c (at l "stage0.edits"))
    (expect (= (build l) 9) "an edit made while stage 0 runs is newer than its answer")
    (expect (= (build l) 9) "and is asked about once")
    (put! c (at l "stage0.fails") "")
    (touch! l "src/a.sld")
    (let ((before (length (calls l "node.calls"))))
      (expect (not (= (● (launch l (list "build" "project" "target")) status) 0))
              "stage 0's failure is the command's")
      (expect (= (length (calls l "node.calls")) before) "and runs nothing"))
    (removed! c (at l "stage0.fails"))
    (expect (= (build l) 11) "a failure keeps no answer")))

(define (commands (l Launcher)) (→ Unit)
  (for-each (lambda (arguments)
              (succeeded (launch l arguments) (string-join arguments " "))
              (expect (ends-with? (last-node-call l)
                                  (string-append (tools l) " " (string-join arguments " ")))
                      (string-append (string-join arguments " ") " hands Node the same tools")))
            (list (list "lsp") (list "run" "project" "target") (list "format" "--check" "a.sld")))
  (expect (= (length (calls l "stage0.calls")) 11) "every command shares the answer")
  (for-each (lambda (unknown)
              (expect (not (= (● (launch l (list unknown)) status) 0))
                      (string-append unknown " is refused")))
            (list "dev" "watch")))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let* ((c (context arguments fs processes environment))
         (l (new Launcher (c c) (root (scratch c "launcher")))))
    (lay-out! l)
    (caching l)
    (edits-and-failures l)
    (commands l)
    (removed! c (● l root))
    (write-line out
                "launcher: cached tools, inputs, missing tools, edits while building, failures, every command")))
