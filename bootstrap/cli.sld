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
;;     builds for the development service, keeping each target's compiler
;;     session from one build to the next (below);
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
 (only (snail shell compiler read)
       Loc
       SourceDiagnostic
       diagnostics->list
       diagnostic->string
       loc->string)
 (snail shell json)
 (snail shell json read)
 (snail shell project)
 (snail shell project build)
 (snail shell project service)
 (snail shell process))

;; ---- Requests ----

;; What one invocation asks for. A build's `target` is a build target, a
;; run's a run target.
(struct Job
  ((tools Tools)
   (run? Bool)
   (mode Mode)
   (project String)
   (target String)
   (arguments (List String))))

(define usage (→ String)
  "usage: snail build [--release] PROJECT BUILD-TARGET | snail run PROJECT RUN-TARGET [ARGUMENT ...]")

(define (request (arguments (List String))) (→ Job)
  (match arguments
    ((Cons _ (Cons root (Cons runtime (Cons action rest))))
     (let ((tools (Tools root runtime (match (environment-variable "NODE")
                                        ((Some node) node)
                                        ((None) "node")))))
       (cond ((string=? action "build") (build-request tools rest))
             ((string=? action "run") (run-request tools rest))
             ((string=? action "resident") (resident-request tools rest))
             (else (panic usage)))))
    (_ (panic usage))))

(define (build-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons "--release" (Cons project (Cons target (Nil))))
     (Job tools #f (Release) (resolved project) target (Nil)))
    ((Cons project (Cons target (Nil))) (Job tools #f (Debug) (resolved project) target (Nil)))
    (_ (panic usage))))

(define (run-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons project (Cons target rest)) (Job tools #t (Debug) (resolved project) target rest))
    (_ (panic usage))))

(define (resident-request (tools Tools) (arguments (List String))) (→ Job)
  (match arguments
    ((Cons project (Nil)) (Job tools #f (Development) (resolved project) "" (Nil)))
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
  (! mut fs clock process)
  (match (::first (build-project (::tools job)
                                 (::project job)
                                 description
                                 (list target)
                                 (::mode job)
                                 (scratch job)
                                 ".snail-"
                                 (Nil)))
    ((Err failure) (panic (failure->string failure)))
    ((Ok candidate)
     (match (publish-project candidate)
       ((Err message) (panic message))
       ((Ok _) (generation-of candidate target))))))

(define (scratch (job Job)) (→ String)
  (string-append (::root (::tools job)) "/build/snail-run"))

(define (generation-of (candidate Candidate) (target String)) (→ String)
  (match (find (lambda (output) (string=? (::name output) target))
               (::outputs candidate))
    ((Some output) (::directory output))
    ((None) (panic (string-append "internal error: the build did not build " target)))))

;; ---- Running ----

;; The run target's program, built, then this process, replaced by Node
;; running it.

(define (run-target (job Job) (description Project)) (→ Unit) (! mut fs clock process)
  (match (find (lambda (run) (string=? (::name run) (::target job)))
               (::runs description))
    ((None) (panic (string-append "unknown project run target " (::target job))))
    ((Some run)
     (let* ((generation (build-and-publish job
                                           description
                                           (::name (::program run))))
            (tools (::tools job))
            (error (exec (Command (::node tools)
                                  (append (list "--no-warnings"
                                                (string-append (::root tools)
                                                               "/host/native/run-snail.mjs")
                                                (string-append generation "/program.wasm"))
                                          (append (::arguments run) (::arguments job)))
                                  "."))))
       (panic (string-append "cannot run " (::node tools) ": " (::code error)))))))

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
;; Each target's compiler session goes from one build to the next, so a
;; build compiles only the libraries an edit reaches. The resident exits
;; when its input ends.
(struct Resident
  ((job Job)
   (retained (List Retained))
   (held (Option (Pair I64 Candidate)))))

(enum Request
  (BuildRequest ((epoch I64) (prefix String)))
  (PublishRequest ((epoch I64)))
  (DiscardRequest ((epoch I64))))

(define (serve (resident Resident)) (→ Unit) (! mut fs clock process console)
  (match (read-line)
    ((None) (unit))
    ((Some line) (serve (answer resident (parse-request line))))))

(define (answer (resident Resident) (request Request)) (→ Resident) (! mut fs clock process console)
  (match request
    ((BuildRequest epoch prefix) (build-for resident epoch prefix))
    ((PublishRequest epoch)
     (let ((published (publish-project (held resident epoch))))
       (reply (list (Pair "epoch" (JsonInteger epoch))
                    (Pair "error" (match published
                                    ((Ok _) (JsonNull))
                                    ((Err message) (JsonString message))))))
       (Resident-held-set resident (None))))
    ((DiscardRequest epoch)
     (discard-candidate (held resident epoch))
     (reply (list (Pair "epoch" (JsonInteger epoch))))
     (Resident-held-set resident (None)))))

(define (build-for (resident Resident) (epoch I64) (prefix String))
  (→ Resident)
  (! mut fs clock process console)
  (let ((job (::job resident)))
    (match (::held resident)
      ((Some _) (panic "internal error: a build was asked for before the last was decided"))
      ((None) (unit)))
    (match (read-project (::project job))
      ((Err failure)
       (reply (build-reply epoch (JsonNull) (JsonNull) failure))
       resident)
      ((Ok description)
       (let* ((began (monotonic-nanoseconds))
              (built (build-project (::tools job)
                                    (::project job)
                                    description
                                    (map build-name (::builds description))
                                    (Development)
                                    (scratch job)
                                    prefix
                                    (::retained resident)))
              (milliseconds (quotient (- (monotonic-nanoseconds) began) 1000000)))
         (match (::first built)
           ((Ok candidate)
            (reply (list (Pair "epoch" (JsonInteger epoch))
                         (Pair "description" (description->json description))
                         (Pair "candidate" (candidate->json candidate description milliseconds))
                         (Pair "diagnostics" (JsonArray (Nil)))))
            (Resident job (::second built) (Some (Pair epoch candidate))))
           ((Err failure)
            (reply (build-reply epoch (description->json description) (JsonNull) failure))
            (Resident job (::second built) (None)))))))))

(define (build-reply (epoch I64) (description Json) (candidate Json) (failure Failure))
  (→ (List (Pair String Json)))
  (list (Pair "epoch" (JsonInteger epoch))
        (Pair "description" description)
        (Pair "candidate" candidate)
        (Pair "diagnostics" (JsonArray (failure-diagnostics failure)))))

(define (held (resident Resident) (epoch I64)) (→ Candidate)
  (match (::held resident)
    ((Some (Pair held-epoch candidate))
     (if (= held-epoch epoch)
         candidate
         (panic (string-append "internal error: no candidate for epoch " (show epoch)))))
    ((None) (panic (string-append "internal error: no candidate for epoch " (show epoch))))))

(define (reply (members (List (Pair String Json)))) (→ Unit) (! console)
  (write-line (json->string (JsonObject members))))

;; ---- Requests and replies as JSON ----

;; A request the service wrote. The service is trusted, so a line that is
;; not one is an internal error. A generation prefix names a directory
;; beside the published outputs, as the builder's own do.

(define (parse-request (line String)) (→ Request)
  (let* ((json (match (string->json line)
                 ((Some json) json)
                 ((None) (panic (string-append "internal error: a request is not JSON: " line)))))
         (epoch (match (json-member json "epoch")
                  ((Some (JsonInteger epoch)) epoch)
                  (_ (panic (string-append "internal error: a request has no epoch: " line))))))
    (match (json-member json "kind")
      ((Some (JsonString "build")) (BuildRequest epoch (generation-prefix json line)))
      ((Some (JsonString "publish")) (PublishRequest epoch))
      ((Some (JsonString "discard")) (DiscardRequest epoch))
      (_ (panic (string-append "internal error: an unknown request: " line))))))

(define (generation-prefix (json Json) (line String)) (→ String)
  (match (json-member json "prefix")
    ((Some (JsonString prefix))
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

(define (build-name (target BuildTarget)) (→ String)
  (match target
    ((ProgramTarget program) (::name program))
    ((BrowserTarget browser) (::name browser))))

;; The project as the service reads it: its build and run targets, each
;; with its source point.

(define (description->json (description Project)) (→ Json)
  (JsonObject (list (Pair "builds" (JsonArray (map build->json (::builds description))))
                    (Pair "runs" (JsonArray (map run->json (::runs description)))))))

(define (entry->json (entry ProjectEntry)) (→ Json)
  (match entry
    ((SourceEntry path) (JsonString (::text path)))
    ((ApplicationEntry library name)
     (JsonObject (list (Pair "library" (JsonArray (map JsonString library)))
                       (Pair "type" (JsonString name)))))))

(define (build->json (target BuildTarget)) (→ Json)
  (match target
    ((ProgramTarget program)
     (JsonObject (list (Pair "kind" (JsonString "program"))
                       (Pair "name" (JsonString (::name program)))
                       (Pair "entry" (entry->json (::entry program)))
                       (Pair "location" (JsonString (loc->string (::loc program))))
                       (Pair "libraries" (paths->json (::libraries program))))))
    ((BrowserTarget browser)
     (JsonObject (list (Pair "kind" (JsonString "browser"))
                       (Pair "name" (JsonString (::name browser)))
                       (Pair "entry" (entry->json (::entry browser)))
                       (Pair "location" (JsonString (loc->string (::loc browser))))
                       (Pair "libraries" (paths->json (::libraries browser)))
                       (Pair "public" (match (::public browser)
                                        ((Some path) (JsonString (::text path)))
                                        ((None) (JsonNull)))))))))

(define (paths->json (paths (List ProjectPath))) (→ Json)
  (JsonArray (map (lambda (path) (JsonString (::text path))) paths)))

(define (run->json (run RunTarget)) (→ Json)
  (JsonObject (list (Pair "kind" (JsonString "run"))
                    (Pair "name" (JsonString (::name run)))
                    (Pair "build" (JsonString (::name (::program run))))
                    (Pair "location" (JsonString (loc->string (::loc run))))
                    (Pair "args" (JsonArray (map JsonString (::arguments run)))))))

;; How long the build took, and each target's generation, with its
;; digests and how many of its modules the build compiled.

(define (candidate->json (candidate Candidate) (description Project) (milliseconds I64)) (→ Json)
  (JsonObject
   (list (Pair "project" (JsonString (::project candidate)))
         (Pair "milliseconds" (JsonInteger milliseconds))
         (Pair "description" (description->json description))
         (Pair "targets" (JsonArray (map output->json (::outputs candidate)))))))

(define (output->json (output Output)) (→ Json)
  (JsonObject (list (Pair "name" (JsonString (::name output)))
                    (Pair "directory" (JsonString (::directory output)))
                    (Pair "digest" (JsonString (::digest output)))
                    (Pair "compiled" (JsonInteger (::compiled output)))
                    (Pair "modules" (JsonInteger (::modules output)))
                    (Pair "files"
                          (JsonObject (map (lambda (file)
                                             (Pair (::first file)
                                                   (JsonString (::second file))))
                                           (::files output))))
                    (Pair "linked" (JsonArray (map JsonString (::linked output)))))))

;; A failure's diagnostics as the editor shows them: a compile's, each
;; naming its source point when it has one, or the build's one.

(define (failure-diagnostics (failure Failure)) (→ (List Json))
  (match failure
    ((CompileFailure diagnostics) (map source-diagnostic->json (diagnostics->list diagnostics)))
    ((BuildFailure message) (list (diagnostic->json message (JsonNull))))))

;; A location in line 0 is not a point: one about a file as a whole, such
;; as a missing source, names the file in its message.

(define (source-diagnostic->json (diagnostic SourceDiagnostic)) (→ Json)
  (let ((loc (::loc diagnostic)))
    (cond ((= (string-length (::file loc)) 0)
           (diagnostic->json (::message diagnostic) (JsonNull)))
          ((and (> (::line loc) 0) (> (::column loc) 0))
           (diagnostic->json (::message diagnostic) (source->json loc)))
          (else (diagnostic->json (diagnostic->string diagnostic) (JsonNull))))))

(define (source->json (loc Loc)) (→ Json)
  (JsonObject (list (Pair "file" (JsonString (::file loc)))
                    (Pair "line" (JsonInteger (::line loc)))
                    (Pair "column" (JsonInteger (::column loc))))))

(define (diagnostic->json (message String) (source Json)) (→ Json)
  (JsonObject (list (Pair "severity" (JsonString "error"))
                    (Pair "message" (JsonString message))
                    (Pair "source" source))))

;; ---- The development service ----

;; The service's setup, from `dev`'s arguments after the command line's
;; own: its path, the root and the runtime.

(define (dev-setup (cli String) (root String) (runtime String) (arguments (List String))) (→ Setup)
  (let ((node (match (environment-variable "NODE")
                ((Some node) node)
                ((None) "node"))))
    (match arguments
      ((Cons editor (Cons client (Cons "--port" (Cons port (Cons project (Nil))))))
       (Setup root cli runtime node editor client (resolved project) (port-number port)))
      ((Cons editor (Cons client (Cons project (Nil))))
       (Setup root cli runtime node editor client (resolved project) 8000))
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

(define (invoke (job Job)) (→ Unit) (! mut fs clock process console)
  (match (::mode job)
    ((Development) (serve (Resident job (Nil) (None))))
    (_
     (match (read-project (::project job))
       ((Err failure) (panic (failure->string failure)))
       ((Ok description)
        (if (::run? job)
            (run-target job description)
            (begin
              (build-and-publish job description (::target job))
              (write-line (string-append (::project job) "/build/" (::target job))))))))))

(match (command-line)
  ((Cons cli (Cons root (Cons runtime (Cons "dev" arguments))))
   (develop (dev-setup cli root runtime arguments)))
  (arguments (invoke (request arguments))))
