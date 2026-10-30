;; The `snail` command line, which stage 0 builds (`scripts/snail-tool
;; cli-tools`) and ./snail runs on Node, after the repository's root and the
;; runtime module programs are linked with:
;;
;;   build [--release] PROJECT BUILD-TARGET
;;     builds a target, publishes it, and prints where its output is;
;;   run PROJECT RUN-TARGET [ARGUMENT ...]
;;     builds a run target's program, publishes it, and becomes it, with the
;;     run's arguments and then these, in the caller's directory.
;;
;; A failure prints its message and exits with status 1; the outputs of
;; earlier builds stay published.
(import
 (snail core base)
 (snail core io)
 (snail shell project)
 (snail shell project build)
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
  (match (build-project (Job-tools job)
                        (Job-project job)
                        description
                        (list target)
                        (Job-mode job)
                        (string-append (Tools-root (Job-tools job)) "/build/snail-run"))
    ((Err message) (panic message))
    ((Ok candidate)
     (match (publish-project candidate)
       ((Err message) (panic message))
       ((Ok _) (generation-of candidate target))))))

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

;; ---- The invocation ----

(let ((job (request (command-line))))
  (match (read-project (Job-project job))
    ((Err message) (panic message))
    ((Ok description)
     (if (Job-run? job)
         (run-target job description)
         (begin
           (build-and-publish job description (Job-target job))
           (write-line (string-append (Job-project job) "/build/" (Job-target job))))))))
