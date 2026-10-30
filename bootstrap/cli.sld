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
;;   dev FORMATTER [--port PORT] PROJECT
;;     runs the development service, (snail shell project service), with
;;     the editor's formatter, until it is interrupted, as ./snail dev
;;     does.
;;
;; A failure prints its message and exits with status 1; the outputs of
;; earlier builds stay published.
(import
 (snail core base)
 (snail core io)
 (only (snail shell compiler read)
       Loc
       Loc-file
       Loc-line
       Loc-column
       SourceDiagnostic-loc
       SourceDiagnostic-message
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

(: usage String)
(define usage
  "usage: snail build [--release] PROJECT BUILD-TARGET | snail run PROJECT RUN-TARGET [ARGUMENT ...]")

(: request (-> (List String) Job))
(define (request arguments)
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

(: build-request (-> Tools (List String) Job))
(define (build-request tools arguments)
  (match arguments
    ((Cons "--release" (Cons project (Cons target (Nil))))
     (Job tools #f (Release) (resolved project) target (Nil)))
    ((Cons project (Cons target (Nil))) (Job tools #f (Debug) (resolved project) target (Nil)))
    (_ (panic usage))))

(: run-request (-> Tools (List String) Job))
(define (run-request tools arguments)
  (match arguments
    ((Cons project (Cons target rest)) (Job tools #t (Debug) (resolved project) target rest))
    (_ (panic usage))))

(: resident-request (-> Tools (List String) Job))
(define (resident-request tools arguments)
  (match arguments
    ((Cons project (Nil)) (Job tools #f (Development) (resolved project) "" (Nil)))
    (_ (panic "usage: snail resident PROJECT"))))

;; A path made absolute against the working directory, without empty or
;; "." components, and with each ".." taking the component before it.
(: resolved (-> String String))
(define (resolved path)
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

(: path-parts (-> String (List String)))
(define (path-parts path)
  (match (string-index path #\/)
    ((Some index)
     (Cons (substring path 0 index) (path-parts (substring path (+ index 1) (string-length path)))))
    ((None) (list path))))

;; ---- Building ----

;; Builds `target`, with the root's build/snail-run/ for scratch, and
;; publishes it; answers the target's generation.
(: build-and-publish (-> Job Project String String ! mut fs clock process))
(define (build-and-publish job description target)
  (match (Pair-first (build-project (Job-tools job)
                                    (Job-project job)
                                    description
                                    (list target)
                                    (Job-mode job)
                                    (scratch job)
                                    ".snail-"
                                    (Nil)))
    ((Err failure) (panic (failure->string failure)))
    ((Ok candidate)
     (match (publish-project candidate)
       ((Err message) (panic message))
       ((Ok _) (generation-of candidate target))))))

(: scratch (-> Job String))
(define (scratch job)
  (string-append (Tools-root (Job-tools job)) "/build/snail-run"))

(: generation-of (-> Candidate String String))
(define (generation-of candidate target)
  (match (find (lambda (output) (string=? (Output-name output) target))
               (Candidate-outputs candidate))
    ((Some output) (Output-directory output))
    ((None) (panic (string-append "internal error: the build did not build " target)))))

;; ---- Running ----

;; The run target's program, built, then this process, replaced by Node
;; running it.
(: run-target (-> Job Project Unit ! mut fs clock process))
(define (run-target job description)
  (match (find (lambda (run) (string=? (RunTarget-name run) (Job-target job)))
               (Project-runs description))
    ((None) (panic (string-append "unknown project run target " (Job-target job))))
    ((Some run)
     (let* ((generation (build-and-publish job
                                           description
                                           (ProgramBuild-name (RunTarget-program run))))
            (tools (Job-tools job))
            (error (exec (Command (Tools-node tools)
                                  (append (list "--no-warnings"
                                                (string-append (Tools-root tools)
                                                               "/host/native/run-snail.mjs")
                                                (string-append generation "/program.wasm"))
                                          (append (RunTarget-arguments run) (Job-arguments job)))
                                  "."))))
       (panic (string-append "cannot run " (Tools-node tools) ": " (ProcessError-code error)))))))

;; ---- The resident builder ----

;; `snail resident PROJECT` builds for the development service
;; (host/native/resident.mjs), which writes it one request a line and reads
;; one reply a line, each a JSON object:
;;
;;   {"kind":"build","epoch":N,"prefix":P}
;;     builds every build target in development mode, naming each
;;     generation with P, and replies {"epoch":N,"description":D,
;;     "candidate":C,"diagnostics":[...]}, with D null when the project
;;     cannot be read and C null when the build fails. The resident holds
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

(: serve (-> Resident Unit ! mut fs clock process console))
(define (serve resident)
  (match (read-line)
    ((None) (unit))
    ((Some line) (serve (answer resident (parse-request line))))))

(: answer (-> Resident Request Resident ! mut fs clock process console))
(define (answer resident request)
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

(: build-for (-> Resident I64 String Resident ! mut fs clock process console))
(define (build-for resident epoch prefix)
  (let ((job (Resident-job resident)))
    (match (Resident-held resident)
      ((Some _) (panic "internal error: a build was asked for before the last was decided"))
      ((None) (unit)))
    (match (read-project (Job-project job))
      ((Err failure)
       (reply (build-reply epoch (JsonNull) (JsonNull) failure))
       resident)
      ((Ok description)
       (let ((built (build-project (Job-tools job)
                                   (Job-project job)
                                   description
                                   (map build-name (Project-builds description))
                                   (Development)
                                   (scratch job)
                                   prefix
                                   (Resident-retained resident))))
         (match (Pair-first built)
           ((Ok candidate)
            (reply (list (Pair "epoch" (JsonInteger epoch))
                         (Pair "description" (description->json description))
                         (Pair "candidate" (candidate->json candidate description))
                         (Pair "diagnostics" (JsonArray (Nil)))))
            (Resident job (Pair-second built) (Some (Pair epoch candidate))))
           ((Err failure)
            (reply (build-reply epoch (description->json description) (JsonNull) failure))
            (Resident job (Pair-second built) (None)))))))))

(: build-reply (-> I64 Json Json Failure (List (Pair String Json))))
(define (build-reply epoch description candidate failure)
  (list (Pair "epoch" (JsonInteger epoch))
        (Pair "description" description)
        (Pair "candidate" candidate)
        (Pair "diagnostics" (JsonArray (list (failure->json failure))))))

(: held (-> Resident I64 Candidate))
(define (held resident epoch)
  (match (Resident-held resident)
    ((Some (Pair held-epoch candidate))
     (if (= held-epoch epoch)
         candidate
         (panic (string-append "internal error: no candidate for epoch " (show epoch)))))
    ((None) (panic (string-append "internal error: no candidate for epoch " (show epoch))))))

(: reply (-> (List (Pair String Json)) Unit ! console))
(define (reply members)
  (write-line (json->string (JsonObject members))))

;; ---- Requests and replies as JSON ----

;; A request the service wrote. The service is trusted, so a line that is
;; not one is an internal error. A generation prefix names a directory
;; beside the published outputs, as the builder's own do.
(: parse-request (-> String Request))
(define (parse-request line)
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

(: generation-prefix (-> Json String String))
(define (generation-prefix json line)
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

(: build-name (-> BuildTarget String))
(define (build-name target)
  (match target
    ((ProgramTarget program) (ProgramBuild-name program))
    ((BrowserTarget browser) (BrowserBuild-name browser))))

;; The project as the service reads it: its build and run targets, each
;; with its source point.
(: description->json (-> Project Json))
(define (description->json description)
  (JsonObject (list (Pair "builds" (JsonArray (map build->json (Project-builds description))))
                    (Pair "runs" (JsonArray (map run->json (Project-runs description)))))))

(: build->json (-> BuildTarget Json))
(define (build->json target)
  (match target
    ((ProgramTarget program)
     (JsonObject (list (Pair "kind" (JsonString "program"))
                       (Pair "name" (JsonString (ProgramBuild-name program)))
                       (Pair "entry" (JsonString (ProjectPath-text (ProgramBuild-entry program))))
                       (Pair "location" (JsonString (loc->string (ProgramBuild-loc program))))
                       (Pair "libraries" (paths->json (ProgramBuild-libraries program))))))
    ((BrowserTarget browser)
     (JsonObject (list (Pair "kind" (JsonString "browser"))
                       (Pair "name" (JsonString (BrowserBuild-name browser)))
                       (Pair "entry" (JsonString (ProjectPath-text (BrowserBuild-entry browser))))
                       (Pair "location" (JsonString (loc->string (BrowserBuild-loc browser))))
                       (Pair "libraries" (paths->json (BrowserBuild-libraries browser)))
                       (Pair "public" (match (BrowserBuild-public browser)
                                        ((Some path) (JsonString (ProjectPath-text path)))
                                        ((None) (JsonNull)))))))))

(: paths->json (-> (List ProjectPath) Json))
(define (paths->json paths)
  (JsonArray (map (lambda (path) (JsonString (ProjectPath-text path))) paths)))

(: run->json (-> RunTarget Json))
(define (run->json run)
  (JsonObject (list (Pair "kind" (JsonString "run"))
                    (Pair "name" (JsonString (RunTarget-name run)))
                    (Pair "build" (JsonString (ProgramBuild-name (RunTarget-program run))))
                    (Pair "location" (JsonString (loc->string (RunTarget-loc run))))
                    (Pair "args" (JsonArray (map JsonString (RunTarget-arguments run)))))))

;; Each target's generation, with its digest and how many of its modules
;; the build compiled.
(: candidate->json (-> Candidate Project Json))
(define (candidate->json candidate description)
  (JsonObject
   (list (Pair "project" (JsonString (Candidate-project candidate)))
         (Pair "description" (description->json description))
         (Pair "targets" (JsonArray (map output->json (Candidate-outputs candidate)))))))

(: output->json (-> Output Json))
(define (output->json output)
  (JsonObject (list (Pair "name" (JsonString (Output-name output)))
                    (Pair "directory" (JsonString (Output-directory output)))
                    (Pair "digest" (JsonString (Output-digest output)))
                    (Pair "compiled" (JsonInteger (Output-compiled output)))
                    (Pair "modules" (JsonInteger (Output-modules output))))))

;; A diagnostic as the editor shows it. A compile's names its source point
;; when it has one. A location in line 0 is not a point: one about a file
;; as a whole, such as a missing source, names the file in its message.
(: failure->json (-> Failure Json))
(define (failure->json failure)
  (match failure
    ((CompileFailure diagnostic)
     (let ((loc (SourceDiagnostic-loc diagnostic)))
       (cond ((= (string-length (Loc-file loc)) 0)
              (diagnostic->json (SourceDiagnostic-message diagnostic) (JsonNull)))
             ((and (> (Loc-line loc) 0) (> (Loc-column loc) 0))
              (diagnostic->json (SourceDiagnostic-message diagnostic) (source->json loc)))
             (else (diagnostic->json (diagnostic->string diagnostic) (JsonNull))))))
    ((BuildFailure message) (diagnostic->json message (JsonNull)))))

(: source->json (-> Loc Json))
(define (source->json loc)
  (JsonObject (list (Pair "file" (JsonString (Loc-file loc)))
                    (Pair "line" (JsonInteger (Loc-line loc)))
                    (Pair "column" (JsonInteger (Loc-column loc))))))

(: diagnostic->json (-> String Json Json))
(define (diagnostic->json message source)
  (JsonObject (list (Pair "severity" (JsonString "error"))
                    (Pair "message" (JsonString message))
                    (Pair "source" source))))

;; ---- The development service ----

;; The service's setup, from `dev`'s arguments after the command line's
;; own: its path, the root and the runtime.
(: dev-setup (-> String String String (List String) Setup))
(define (dev-setup cli root runtime arguments)
  (let ((node (match (environment-variable "NODE")
                ((Some node) node)
                ((None) "node"))))
    (match arguments
      ((Cons formatter (Cons "--port" (Cons port (Cons project (Nil)))))
       (Setup root cli runtime node formatter (resolved project) (port-number port)))
      ((Cons formatter (Cons project (Nil)))
       (Setup root cli runtime node formatter (resolved project) 8000))
      (_ (panic "usage: snail dev [--port PORT] PROJECT")))))

(: port-number (-> String I32))
(define (port-number text)
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
(: invoke (-> Job Unit ! mut fs clock process console))
(define (invoke job)
  (match (Job-mode job)
    ((Development) (serve (Resident job (Nil) (None))))
    (_
     (match (read-project (Job-project job))
       ((Err failure) (panic (failure->string failure)))
       ((Ok description)
        (if (Job-run? job)
            (run-target job description)
            (begin
              (build-and-publish job description (Job-target job))
              (write-line (string-append (Job-project job) "/build/" (Job-target job))))))))))

(match (command-line)
  ((Cons cli (Cons root (Cons runtime (Cons "dev" arguments))))
   (develop (dev-setup cli root runtime arguments)))
  (arguments (invoke (request arguments))))
