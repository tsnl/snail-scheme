;; Workspace discovery through the launcher, including paths that collide
;; even though the program never imports them.
;;
;;   ./snail-scheme run --target node tests/contracts/workspaces.scm ROOT
(import
 (snail core base)
 (snail core io)
 (snail shell process)
 (contracts support))

(define manifest (→ String) "snail-scheme-workspace.datum")

(define (extends-path (path String)) (→ String)
  (string-append "(workspace (extends \"" path "\"))\n"))

;; The places one run lays out: an app whose tools/ holds the script, and
;; a team's shared workspace two folders away.
(record Area
  ((area String)
   (app String)
   (team String)
   (nested String)))

(define (in (c Context) (a Area) (action String)) (→ Ran)
  (snail c (list action "--target" "node" "main.scm") (● a nested)))

(define (lay-out! (c Context) (a Area)) (→ Unit)
  (put! c (string-append (● a team) "/" manifest) (extends-path (● c root)))
  (make-directories (● c fs) (string-append (● a team) "/child"))
  ;; Resolve a link before applying ..; the lexical parent is a different repo.
  (link! c (string-append (● a team) "/child")
         (string-append (● a area) "/alias"))
  (put! c (string-append (● a app) "/" manifest) (extends-path "../alias/.."))
  (put! c (string-append (● a team) "/src/demo/shared.sld")
        (string-append
         "(define-library (demo shared)\n  (export answer)\n  (import (snail core base))\n"
         "  (begin (define (answer) (→ I64) 42)))\n"))
  (put! c (string-append (● a app) "/src/demo/local.sld")
        (string-append "(define-library (demo local)\n  (export message)\n"
                       "  (import (snail core base) (demo shared))\n"
                       "  (begin (define (message) (→ String) (show (answer)))))\n"))
  (put! c (string-append (● a nested) "/main.scm")
        (string-append "(import (snail core base) (snail core io) (demo local))\n"
                       "(define (main (out OutputPort)) (→ Unit) (write-line out (message)))\n")))

(define (bases (c Context) (a Area)) (→ Unit)
  (make-directories (● c fs) (string-append (● a nested) "/src")) ; An incidental src/ below the declaration.
  (expect-text (● (succeeded (in c a "run") "run") stdout)
               "42\n"
               "a base's library reaches the script")
  (expect-text (first-line (● (in c a "build") stdout))
               (string-append (● a app) "/build/tools/main")
               "the output lies under the declaring workspace")
  (expect (starts-with? (● (in c a "wat") stdout) "(module") "wat prints the module")
  ;; A nearer declaration selects its own root. It may contain only scripts.
  (removed! c (string-append (● a nested) "/src"))
  (put! c (string-append (● a nested) "/" manifest) (extends-path ".."))
  (expect-text (first-line (● (in c a "build") stdout)) (string-append (● a nested) "/build/main")
               "a nearer declaration selects its own root")
  (removed! c (string-append (● a nested) "/" manifest)))

(define (conflicts (c Context) (a Area)) (→ Unit)
  (let* ((asset "src/demo/unused.txt")
         (mine (string-append (● a app) "/" asset))
         (theirs (string-append (● a team) "/" asset))
         (both? (lambda ((ran Ran))
                  (→ Bool)
                  (and (contains? (● ran stderr) "workspace source conflict")
                       (contains? (● ran stderr) mine)
                       (contains? (● ran stderr) theirs)))))
    (put! c mine "app")
    (put! c theirs "base")
    (expect (both? (in c a "build")) "a file both workspaces hold is a conflict")
    (removed! c mine)
    (make-directories (● c fs) mine)
    (expect (both? (in c a "wat")) "and so is a directory under the same name")
    (removed! c mine))
  ;; A third layer can conflict with the app across a disjoint middle layer.
  (put! c (string-append (● a app) "/src/snail/core/base.sld") "")
  (let ((ran (in c a "wat")))
    (expect (and (contains? (● ran stderr) (string-append (● c root) "/src/snail/core/base.sld"))
                 (contains? (● ran stderr) (string-append (● a app) "/src/snail/core/base.sld")))
            "the repository's own libraries conflict with an app's"))
  (removed! c (string-append (● a app) "/src/snail")))

(define (refusals (c Context) (a Area)) (→ Unit)
  (link! c (● a app) (string-append (● a team) "/back"))
  (put! c (string-append (● a team) "/" manifest) (extends-path "back"))
  (let ((ran (in c a "wat")))
    (expect (and (contains? (● ran stderr) "workspace base cycle")
                 (contains? (● ran stderr) (● a app))
                 (contains? (● ran stderr) (● a team)))
            "a cycle of bases is refused, naming both"))
  (put! c (string-append (● a app) "/" manifest) "(workspace (extends \"one\") (extends \"two\"))")
  (let ((ran (in c a "wat")))
    (expect (and (contains? (● ran stderr) manifest) (contains? (● ran stderr) "expected"))
            "two bases are refused"))
  (put! c (string-append (● a app) "/" manifest) (extends-path "missing"))
  (failed-with (in c a "build") (string-append (● a app) "/missing") "a missing base")
  (put! c (string-append (● a app) "/" manifest) "(workspace)")
  (failed-with (in c a "wat") "library not found" "a workspace without the base"))

;; An older compiler checkout can be the terminal base without a manifest.
(define (older (c Context) (a Area)) (→ Unit)
  (let ((old (string-append (● a area) "/older")))
    (make-directories (● c fs) old)
    (link! c (string-append (● c root) "/src") (string-append old "/src"))
    (put! c (string-append (● a team) "/" manifest) (extends-path old))
    (put! c (string-append (● a app) "/" manifest) (extends-path "../shared/team"))
    (expect-text (● (succeeded (in c a "run") "run") stdout) "42\n"
                 "an older checkout is a base without a manifest")))

(define (main (arguments Arguments)
              (fs Fs)
              (processes Processes)
              (environment ProcessEnvironment)
              (out OutputPort))
  (→ Unit)
  (let* ((c (context arguments fs processes environment))
         (area (scratch c "workspaces"))
         (a (new Area
              (area area)
              (app (string-append area "/app"))
              (team (string-append area "/shared/team"))
              (nested (string-append area "/app/tools")))))
    (lay-out! c a)
    (bases c a)
    (conflicts c a)
    (refusals c a)
    (older c a)
    (removed! c area)
    (write-line out "workspaces passed")))
