;; The `snail` command line, which stage 0 builds (`scripts/snail-tool
;; cli-tools`) and ./snail runs on Node, after the repository's root and the
;; runtime module programs are linked with:
;;
;;   build [--release] PROJECT BUILD-TARGET
;;     builds a target, publishes it, and prints where its output is;
;;   run PROJECT RUN-TARGET [ARGUMENT ...]
;;     builds a run target's program, publishes it, and becomes it, with the
;;     run's arguments and then these, in the caller's directory;
;;   resident PROJECT
;;     rebuilds every configured target for each development request;
;;   dev EDITOR CLIENT [--port PORT] PROJECT
;;     runs the development service, (snail shell project service), with
;;     the editor's browser bundle, host/ide built, and the reload
;;     client's, host/browser/reload.sld built, until it is interrupted,
;;     as ./snail dev does.
;;
;; A failure prints its message and exits with status 1; the outputs of
;; earlier builds stay published.
(import
 (snail core base)
 (snail core io)
 (only (snail core forms) Host)
 (only (snail shell task) Tasks)
 (only (snail shell socket) Tcp)
 (only (snail shell watch) Hints)
 (only (snail shell compiler read)
       Loc
       Source-diagnostic
       diagnostics->list
       diagnostic->string
       loc->string)
 (snail shell json)
 (snail shell json read)
 (snail shell project)
 (snail shell project build)
 (only (snail shell project files) Modes)
 (snail shell project service)
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
  "usage: snail build [--release] PROJECT BUILD-TARGET | snail run PROJECT RUN-TARGET [ARGUMENT ...]")

(define (request (arguments (List String))) (→ Job)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons action rest))))
     (let ((tools
            (new Tools (root root) (runtime runtime) (node (match (environment-variable "NODE")
                                                             ((Some node) node)
                                                             ((None) "node"))))))
       (cond ((string=? action "build") (build-request tools rest))
             ((string=? action "run") (run-request tools rest))
             ((string=? action "resident") (resident-request tools rest))
             (else (panic (usage))))))
    (_ (panic (usage)))))

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

(define (resident-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons project (Nil))
     (new Job
       (tools tools)
       (run? #f)
       (mode (Development))
       (project (resolved project))
       (target "")
       (arguments (Nil))))
    (_ (panic "usage: snail resident PROJECT"))))

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
  (! Mut Fs Clock Processes)
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

(define (run-target (job Job) (description Project)) (→ Unit) (! Mut Fs Clock Processes)
  (match (find (lambda (run) (string=? (● run name) (● job target)))
               (● description runs))
    ((None) (panic (string-append "unknown project run target " (● job target))))
    ((Some run)
     (let* ((generation (build-and-publish job
                                           description
                                           (● (● run program) name)))
            (tools (● job tools))
            (error (exec (new Command (program (● tools node))
                              (arguments (append (list "--no-warnings"
                                                       (string-append (● tools root)
                                                                      "/host/native/run-snail.mjs")
                                                       (string-append generation "/program.wasm"))
                                                 (append (● run arguments) (● job arguments))))
                              (directory ".")))))
       (panic (string-append "cannot run " (● tools node) ": " (● error code)))))))

;; ---- The resident builder ----

;; `snail resident PROJECT` builds for the development service,
;; (snail shell project service), which writes it one request a line and
;; reads one reply a line, each a JSON object:
;;
;;   {"kind":"build","epoch":N,"prefix":P}
;;     builds every build target in development mode, naming each
;;     generation with P, and replies {"epoch":N,"description":D,
;;     "candidate":C,"diagnostics":[...]}, with D null when the project
;;     cannot be read and C null when the build fails. C names each
;;     target's generation, its digest, its files' digests and the paths
;;     of the files it links, and how long the build took. The resident holds
;;     C until a publish or a discard names its epoch, which the service
;;     sends before it asks for another build;
;;   {"kind":"publish","epoch":N}
;;     publishes it, and replies {"epoch":N,"error":E}, E null on success;
;;   {"kind":"discard","epoch":N}
;;     removes its generations, and replies {"epoch":N}.
;;
;; Each request rebuilds every configured target. Only an unpublished
;; candidate survives between requests; no compiler cache does. The
;; resident exits when its input ends.
(record Resident
  ((job Job)
   (held (Option (Pair I64 Candidate)))))

(enum Request
  (Build-request ((epoch I64) (prefix String)))
  (Publish-request ((epoch I64)))
  (Discard-request ((epoch I64))))

(define (serve (resident Resident)) (→ Unit) (! Mut Fs Clock Processes Input-port Output-port)
  (match (read-line)
    ((None) (unit))
    ((Some line) (serve (answer resident (parse-request line))))))

(define (answer (resident Resident) (request Request))
  (→ Resident)
  (! Mut Fs Clock Processes Output-port)
  (match request
    ((Build-request epoch prefix) (build-for resident epoch prefix))
    ((Publish-request epoch)
     (let ((published (publish-project (held resident epoch))))
       (reply (list (new Pair (first "epoch") (second (Json-integer epoch)))
                    (new Pair (first "error") (second (match published
                                                        ((Ok _) (Json-null))
                                                        ((Err message) (Json-string message)))))))
       (resident-held-set resident (None))))
    ((Discard-request epoch)
     (discard-candidate (held resident epoch))
     (reply (list (new Pair (first "epoch") (second (Json-integer epoch)))))
     (resident-held-set resident (None)))))

(define (build-for (resident Resident) (epoch I64) (prefix String))
  (→ Resident)
  (! Mut Fs Clock Processes Output-port)
  (let ((job (● resident job)))
    (match (● resident held)
      ((Some _) (panic "internal error: a build was asked for before the last was decided"))
      ((None) (unit)))
    (match (read-project (● job project))
      ((Err failure)
       (reply (build-reply epoch (Json-null) (Json-null) failure))
       resident)
      ((Ok description)
       (let* ((began (monotonic-nanoseconds))
              (built (build-project (● job tools)
                                    (● job project)
                                    description
                                    (map build-name (● description builds))
                                    (Development)
                                    (scratch job)
                                    prefix))
              (milliseconds (quotient (- (monotonic-nanoseconds) began) 1000000)))
         (match built
           ((Ok candidate)
            (reply (list (new Pair (first "epoch") (second (Json-integer epoch)))
                         (new Pair (first "description") (second (description->json description)))
                         (new Pair
                           (first "candidate")
                           (second (candidate->json candidate description milliseconds)))
                         (new Pair (first "diagnostics") (second (Json-array (Nil))))))
            (new Resident (job job) (held (Some (new Pair (first epoch) (second candidate))))))
           ((Err failure)
            (reply (build-reply epoch (description->json description) (Json-null) failure))
            (new Resident (job job) (held (None))))))))))

(define (build-reply (epoch I64) (description Json) (candidate Json) (failure Failure))
  (→ (List (Pair String Json)))
  (list (new Pair (first "epoch") (second (Json-integer epoch)))
        (new Pair (first "description") (second description))
        (new Pair (first "candidate") (second candidate))
        (new Pair (first "diagnostics") (second (Json-array (failure-diagnostics failure))))))

(define (held (resident Resident) (epoch I64)) (→ Candidate)
  (match (● resident held)
    ((Some (Pair held-epoch candidate))
     (if (= held-epoch epoch)
         candidate
         (panic (string-append "internal error: no candidate for epoch " (show epoch)))))
    ((None) (panic (string-append "internal error: no candidate for epoch " (show epoch))))))

(define (reply (members (List (Pair String Json)))) (→ Unit) (! Output-port)
  (write-line (json->string (Json-object members))))

;; ---- Requests and replies as JSON ----

;; A request the service wrote. The service is trusted, so a line that is
;; not one is an internal error. A generation prefix names a directory
;; beside the published outputs, as the builder's own do.

(define (parse-request (line String)) (→ Request)
  (let* ((json (match (string->json line)
                 ((Some json) json)
                 ((None) (panic (string-append "internal error: a request is not JSON: " line)))))
         (epoch (match (json-member json "epoch")
                  ((Some (Json-integer epoch)) epoch)
                  (_ (panic (string-append "internal error: a request has no epoch: " line))))))
    (match (json-member json "kind")
      ((Some (Json-string "build")) (Build-request epoch (generation-prefix json line)))
      ((Some (Json-string "publish")) (Publish-request epoch))
      ((Some (Json-string "discard")) (Discard-request epoch))
      (_ (panic (string-append "internal error: an unknown request: " line))))))

(define (generation-prefix (json Json) (line String)) (→ String)
  (match (json-member json "prefix")
    ((Some (Json-string prefix))
     (if (and (> (string-length prefix) 7)
              (string=? (substring prefix 0 7) ".snail-")
              (match (string-index prefix #\/)
                ((Some _) #f)
                ((None) #t)))
         prefix
         (panic (string-append
                 "internal error: a generation prefix must begin .snail- and name no directory: "
                 line))))
    (_ (panic (string-append "internal error: a build request has no prefix: " line)))))

(define (build-name (target Build-target)) (→ String)
  (match target
    ((Program-target program) (● program name))
    ((Browser-target browser) (● browser name))))

;; The project as the service reads it: its build and run targets, each
;; with its source point.

(define (description->json (description Project)) (→ Json)
  (Json-object
   (list (new Pair (first "builds") (second (Json-array (map build->json (● description builds)))))
         (new Pair (first "runs") (second (Json-array (map run->json (● description runs))))))))

(define (entry->json (entry Project-entry)) (→ Json)
  (match entry
    ((Source-entry path) (Json-string (● path text)))
    ((Application-entry library name)
     (Json-object (list (new Pair (first "library") (second (Json-array (map Json-string library))))
                        (new Pair (first "type") (second (Json-string name))))))))

(define (build->json (target Build-target)) (→ Json)
  (match target
    ((Program-target program)
     (Json-object (list (new Pair (first "kind") (second (Json-string "program")))
                        (new Pair (first "name") (second (Json-string (● program name))))
                        (new Pair (first "entry") (second (entry->json (● program entry))))
                        (new Pair
                          (first "location")
                          (second (Json-string (loc->string (● program loc)))))
                        (new Pair
                          (first "libraries")
                          (second (paths->json (● program libraries)))))))
    ((Browser-target browser)
     (Json-object (list (new Pair (first "kind") (second (Json-string "browser")))
                        (new Pair (first "name") (second (Json-string (● browser name))))
                        (new Pair (first "entry") (second (entry->json (● browser entry))))
                        (new Pair
                          (first "location")
                          (second (Json-string (loc->string (● browser loc)))))
                        (new Pair (first "libraries") (second (paths->json (● browser libraries))))
                        (new Pair (first "public") (second (match (● browser public)
                                                             ((Some path)
                                                              (Json-string (● path text)))
                                                             ((None) (Json-null))))))))))

(define (paths->json (paths (List Project-path))) (→ Json)
  (Json-array (map (lambda (path) (Json-string (● path text))) paths)))

(define (run->json (run Run-target)) (→ Json)
  (Json-object (list (new Pair (first "kind") (second (Json-string "run")))
                     (new Pair (first "name") (second (Json-string (● run name))))
                     (new Pair (first "build") (second (Json-string (● (● run program) name))))
                     (new Pair (first "location") (second (Json-string (loc->string (● run loc)))))
                     (new Pair
                       (first "args")
                       (second (Json-array (map Json-string (● run arguments))))))))

;; How long the build took, and each target's generation, with its
;; digests and how many of its modules the build compiled.

(define (candidate->json (candidate Candidate) (description Project) (milliseconds I64)) (→ Json)
  (Json-object
   (list (new Pair (first "project") (second (Json-string (● candidate project))))
         (new Pair (first "milliseconds") (second (Json-integer milliseconds)))
         (new Pair (first "description") (second (description->json description)))
         (new Pair
           (first "targets")
           (second (Json-array (map output->json (● candidate outputs))))))))

(define (output->json (output Output)) (→ Json)
  (Json-object (list (new Pair (first "name") (second (Json-string (● output name))))
                     (new Pair (first "directory") (second (Json-string (● output directory))))
                     (new Pair (first "digest") (second (Json-string (● output digest))))
                     (new Pair (first "compiled") (second (Json-integer (● output compiled))))
                     (new Pair (first "modules") (second (Json-integer (● output modules))))
                     (new Pair (first "files")
                          (second (Json-object (map (lambda (file)
                                                      (new Pair (first (● file first))
                                                           (second (Json-string (● file second)))))
                                                    (● output files)))))
                     (new Pair
                       (first "linked")
                       (second (Json-array (map Json-string (● output linked))))))))

;; A failure's diagnostics as the editor shows them: a compile's, each
;; naming its source point when it has one, or the build's one.

(define (failure-diagnostics (failure Failure)) (→ (List Json))
  (match failure
    ((Compile-failure diagnostics) (map source-diagnostic->json (diagnostics->list diagnostics)))
    ((Build-failure message) (list (diagnostic->json message (Json-null))))))

;; A location in line 0 is not a point: one about a file as a whole, such
;; as a missing source, names the file in its message.

(define (source-diagnostic->json (diagnostic Source-diagnostic)) (→ Json)
  (let ((loc (● diagnostic loc)))
    (cond ((= (string-length (● loc file)) 0)
           (diagnostic->json (● diagnostic message) (Json-null)))
          ((and (> (● loc line) 0) (> (● loc column) 0))
           (diagnostic->json (● diagnostic message) (source->json loc)))
          (else (diagnostic->json (diagnostic->string diagnostic) (Json-null))))))

(define (source->json (loc Loc)) (→ Json)
  (Json-object (list (new Pair (first "file") (second (Json-string (● loc file))))
                     (new Pair (first "line") (second (Json-integer (● loc line))))
                     (new Pair (first "column") (second (Json-integer (● loc column)))))))

(define (diagnostic->json (message String) (source Json)) (→ Json)
  (Json-object (list (new Pair (first "severity") (second (Json-string "error")))
                     (new Pair (first "message") (second (Json-string message)))
                     (new Pair (first "source") (second source)))))

;; ---- The development service ----

;; The service's setup, from `dev`'s arguments after the command line's
;; own: its path, the root and the runtime.

(define (dev-setup (cli String) (root String) (runtime String) (arguments (List String))) (→ Setup)
  (let ((node (match (environment-variable "NODE")
                ((Some node) node)
                ((None) "node"))))
    (match arguments
      ((Cons editor (Cons client (Cons "--port" (Cons port (Cons project (Nil))))))
       (new Setup
         (root root)
         (cli cli)
         (runtime runtime)
         (node node)
         (editor editor)
         (client client)
         (project (resolved project))
         (port (port-number port))))
      ((Cons editor (Cons client (Cons project (Nil))))
       (new Setup
         (root root)
         (cli cli)
         (runtime runtime)
         (node node)
         (editor editor)
         (client client)
         (project (resolved project))
         (port 8000)))
      (_ (panic "usage: snail dev [--port PORT] PROJECT")))))

(define (port-number (text String)) (→ I32)
  (let ((digits (string->list text)))
    (if (and (not (null? digits))
             (<= (length digits) 5)
             (every? (lambda (char) (and (>= (char->i32 char) 48) (<= (char->i32 char) 57)))
                     digits))
        (let ((number (fold-left (lambda (number char) (+ (* number 10) (- (char->i32 char) 48)))
                                 0
                                 digits)))
          (if (<= number 65535) number (panic "port must be an integer from 0 to 65535")))
        (panic "port must be an integer from 0 to 65535"))))

;; ---- The invocation ----

;; A build, a run, or the resident builder.

(define (invoke (job Job)) (→ Unit) (! Mut Fs Clock Processes Input-port Output-port)
  (match (● job mode)
    ((Development) (serve (new Resident (job job) (held (None)))))
    (_
     (match (read-project (● job project))
       ((Err failure) (panic (failure->string failure)))
       ((Ok description)
        (if (● job run?)
            (run-target job description)
            (begin
              (build-and-publish job description (● job target))
              (write-line (string-append (● job project) "/build/" (● job target))))))))))

(define (main)
  (→ Unit)
  (! Host Mut Clock Fs Input-port Output-port Processes Signals Modes Tcp Tasks Hints)

  (match (command-line)
    ((Cons cli (Cons root (Cons runtime (Cons "dev" arguments))))
     (develop (dev-setup cli root runtime arguments)))
    (arguments (invoke (request arguments))))
  (unit))
