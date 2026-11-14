;; The project development service's decisions, as a pure step: from the
;; service and one event to the next service and the commands its host
;; carries out, in order. The host owns everything with an identity:
;;
;; - the disk observer, whose hints and reconciliations arrive as `Touched`,
;;   `Uncertain` and `Reconciled`;
;; - the resident builder, which answers `Build`, `Publish` and `Discard`
;;   by epoch;
;; - the debounce timer, which `Arm` sets, replacing any it set before;
;; - each attempt's reserved build/.snail-attempt-* directory, which
;;   `Build` reserves and `Abandon` or `Release` gives up, by epoch;
;; - each run target's process, which `Launch` asks to run a request, or
;;   none;
;; - the generations it published, which `Reclaim` removes once nothing
;;   needs them.
;;
;; The step keeps what decides: the epoch that numbers every attempt and
;; the replies to it, so a late or duplicate reply is a number that does
;; not match; whether an input changed since the last attempt began; what
;; the disk can be trusted for; and which run targets are wanted. It is
;; #567 step B2; (snail shell project service) carries out its commands.
(define-library (snail shell development)
  (export
   Paths
   Description
   RunDefinition
   Generation
   Candidate
   SourcePoint
   Diagnostic
   Reply
   Published
   Phase
   Starting
   Building
   Succeeded
   Failed
   Superseded
   Fatal
   RunRequest
   RunStatus
   Snapshot
   Event
   ResidentStarted
   ResidentExited
   Touched
   Uncertain
   Reconciled
   BuildReplied
   PublishReplied
   DiscardReplied
   TimerFired
   RequestBuild
   StartRun
   StopRun
   RestartRun
   Close
   Command
   Build
   Reconcile
   Publish
   Discard
   Abandon
   Release
   Arm
   Launch
   Refuse
   Notify
   Reclaim
   Shutdown
   Closed
   Refusal
   UnknownRunTarget
   ServiceClosed
   Service
   new-service
   step)
  (import
   (snail core base))
  (begin

    ;; ---- What builds report ----

    ;; The repository's root and the project's directory, both absolute.
    (record Paths
      ((root String)
       (project String)))

    ;; What the step needs of a project's description: each build's entry
    ;; and public directory, relative to the project, the names of the
    ;; builds that are browser applications, which the host serves, and its
    ;; run targets.
    (record Description
      ((entries (List String))
       (publics (List String))
       (browsers (List String))
       (runs (List RunDefinition))))

    (record RunDefinition
      ((name String)
       (build String)
       (arguments (List String))))

    ;; A built target of a candidate: its generation's directory, the
    ;; digest of what it holds, the digests of its files but its modules,
    ;; by relative name, which the host's pages compare, and the paths of
    ;; the files its program links, which are inputs while it is published.
    (record Generation
      ((name String)
       (directory String)
       (digest String)
       (files (List (Pair String String)))
       (linked (List String))))

    ;; A build's targets, and how long it took, which the host's pages show.
    (record Candidate
      ((description Description)
       (generations (List Generation))
       (milliseconds I64)))

    (record SourcePoint
      ((file String)
       (line I64)
       (column I64)))

    (record Diagnostic
      ((message String)
       (source (Option SourcePoint))))

    ;; The resident's answer to a build: the description it read, even
    ;; when the build failed; a candidate, when it succeeded; and its
    ;; diagnostics.
    (record Reply
      ((description (Option Description))
       (candidate (Option Candidate))
       (diagnostics (List Diagnostic))))

    (record Published
      ((id I64)
       (candidate Candidate)))

    ;; ---- The service ----

    ;; Whether the disk has been read whole: not yet, at start-up; last
    ;; time it was; or the last reconciliation failed, so no candidate may
    ;; be published until an attempt starts again.
    (enum Disk
      (Unscanned)
      (Trusted)
      (Untrusted))

    (enum Phase
      (Starting)
      (Building)
      (Succeeded)
      (Failed)
      (Superseded)
      (Fatal))

    ;; An attempt's progress: the resident is compiling; it replied, and the
    ;; disk is being reconciled before deciding; the candidate is being
    ;; discarded; or it is being published, which consumes the attempt's
    ;; directory even if publication partly fails. `touched` is every path
    ;; that changed while the attempt ran, judged when it replies, under
    ;; the description the reply carries.
    (enum Stage
      (Compiling)
      (Reconciling ((reply Reply)))
      (Discarding
       ((messages (List Diagnostic))
        (superseded Bool)))
      (Publishing
       ((candidate Candidate)
        (messages (List Diagnostic)))))

    (record Attempt
      ((epoch I64)
       (stage Stage)
       (touched (List String))))

    ;; What a run target last asked its process to run: the build, the
    ;; digest of its generation and the arguments, none once it asked for
    ;; nothing. A run is asked again only when this changes, so a process
    ;; that ended is not run again by a publication that changed nothing,
    ;; and a process asked again for the same digest keeps running from the
    ;; generation `directory` it was started in.
    (record Identity
      ((build String)
       (digest String)
       (arguments (List String))
       (directory String)))

    (record RunRequest
      ((build I64)
       (entry String)
       (arguments (List String))))

    (record Run
      ((name String)
       (wanted Bool)
       (issued (Option Identity))))

    ;; `publications` are those whose generations are still on disk, newest
    ;; first, the latest being the one published.
    (record Service
      ((paths Paths)
       (epoch I64)
       (attempt (Option Attempt))
       (publications (List Published))
       (description (Option Description))
       (dirty Bool)
       (disk Disk)
       (closing Bool)
       (phase Phase)
       (diagnostics (List Diagnostic))
       (runs (List Run))))

    (define (new-service (root String) (project String)) (→ Service)
      (new Service (paths (new Paths (root root) (project project)))
           (epoch 0)
           (attempt (None))
           (publications (Nil))
           (description (None))
           (dirty #t)
           (disk (Unscanned))
           (closing #f)
           (phase (Starting))
           (diagnostics (Nil))
           (runs (Nil))))

    ;; ---- Events and commands ----

    (enum Event
      (ResidentStarted)
      (ResidentExited ((message String)))
      (Touched ((paths (List String))))
      (Uncertain ((error (Option String))))
      (Reconciled ((result (Result Unit String))))
      (BuildReplied
       ((epoch I64)
        (reply Reply)))
      (PublishReplied
       ((epoch I64)
        (error (Option String))))
      (DiscardReplied ((epoch I64)))
      (TimerFired)
      (RequestBuild)
      (StartRun ((name String)))
      (StopRun ((name String)))
      (RestartRun ((name String)))
      (Close))

    (record RunStatus
      ((name String)
       (wanted Bool)
       (available Bool)))

    ;; What subscribers see: the publications are the service's, newest
    ;; first, the latest being the one published. The host adds each run's
    ;; process status.
    (record Snapshot
      ((phase Phase)
       (id I64)
       (diagnostics (List Diagnostic))
       (publications (List Published))
       (runs (List RunStatus))))

    (enum Refusal
      (UnknownRunTarget ((name String)))
      (ServiceClosed))

    ;; `Reclaim` removes generations, as directories. `Shutdown` stops the
    ;; observer, the resident and every process, and waits for them, before
    ;; the commands after it run.
    (enum Command
      (Build ((epoch I64)))
      (Reconcile)
      (Publish ((epoch I64)))
      (Discard ((epoch I64)))
      (Abandon ((epoch I64)))
      (Release ((epoch I64)))
      (Arm)
      (Launch
       ((name String)
        (request (Option RunRequest))))
      (Refuse ((refusal Refusal)))
      (Notify ((snapshot Snapshot)))
      (Reclaim ((directories (List String))))
      (Shutdown)
      (Closed))

    (define (step (service Service) (event Event)) (→ (Pair Service (List Command)))
      (match event
        ((ResidentStarted)
         (new Pair (first service) (second (if (● service closing) (Nil) (list (Reconcile))))))
        ((ResidentExited message) (fatal service message))
        ((Touched paths) (touched service paths))
        ((Uncertain error) (uncertain service error))
        ((Reconciled result) (reconciled service result))
        ((BuildReplied epoch reply) (build-replied service epoch reply))
        ((PublishReplied epoch error) (publish-replied service epoch error))
        ((DiscardReplied epoch) (discard-replied service epoch))
        ((TimerFired) (timer-fired service))
        ((RequestBuild) (request-build service))
        ((StartRun name) (start-run service name))
        ((StopRun name) (stop-run service name))
        ((RestartRun name) (restart-run service name))
        ((Close) (close service))))

    ;; ---- Wanting a build ----

    ;; Builds are debounced: an input change arms the timer, and an attempt
    ;; starts when it fires, if one is still wanted and can start. Every
    ;; arming and firing asks the same question, so a stale timer starts
    ;; nothing and the host never cancels one.

    (define (ready? (service Service)) (→ Bool)
      (and (● service dirty)
           (not (● service closing))
           (match (● service disk)
             ((Unscanned) #f)
             (_ #t))
           (match (● service attempt)
             ((None) #t)
             ((Some _) #f))))

    (define (arming (service Service)) (→ (List Command))
      (if (ready? service) (list (Arm)) (Nil)))

    (define (request-build (service Service)) (→ (Pair Service (List Command)))
      (if (● service closing)
          (new Pair (first service) (second (Nil)))
          (let ((service (Service-dirty-set service #t)))
            (new Pair (first service) (second (arming service))))))

    ;; A changed path joins the attempt's, whatever it is, since the
    ;; description that decides whether it is an input may be the one the
    ;; attempt's reply brings.

    (define (touched (service Service) (paths (List String))) (→ (Pair Service (List Command)))
      (let ((service (touching service paths)))
        (if (any? (lambda (path) (input-path? service path)) paths)
            (request-build service)
            (new Pair (first service) (second (Nil))))))

    (define (touching (service Service) (paths (List String))) (→ Service)
      (match (● service attempt)
        ((Some attempt)
         (Service-attempt-set service
                              (Some (Attempt-touched-set attempt
                                                         (append (● attempt touched)
                                                                 paths)))))
        ((None) service)))

    ;; A reconciliation, not an uncertain disk, establishes a change. Once
    ;; the disk can be read again after a failure, a build is wanted.

    (define (uncertain (service Service) (error (Option String))) (→ (Pair Service (List Command)))
      (match (new Pair (first (● service disk)) (second error))
        ((Pair (Untrusted) (None)) (request-build service))
        (_ (new Pair (first service) (second (Nil))))))

    ;; The first reconciliation, at start-up, decides whether builds may
    ;; begin; one during an attempt decides what becomes of its reply.

    (define (reconciled (service Service) (result (Result Unit String)))
      (→ (Pair Service (List Command)))
      (match (● service attempt)
        ((None) (scanned service result))
        ((Some attempt)
         (match (● attempt stage)
           ((Reconciling reply) (decide service attempt reply result))
           (_ (unexpected service))))))

    (define (scanned (service Service) (result (Result Unit String)))
      (→ (Pair Service (List Command)))
      (match result
        ((Ok _)
         (let ((service (Service-disk-set service (Trusted))))
           (new Pair (first service) (second (arming service)))))
        ((Err message)
         (let ((service
                (report (Service-disk-set service (Untrusted)) (Failed) (list (failure message)))))
           (new Pair (first service) (second (list (Notify (snapshot service)))))))))

    ;; ---- Attempts ----

    ;; Subscribers see the attempt begin, and earlier diagnostics go,
    ;; before the resident is asked to build.

    (define (timer-fired (service Service)) (→ (Pair Service (List Command)))
      (if (ready? service)
          (let ((service (begun service (+ (● service epoch) 1))))
            (new Pair
              (first service)
              (second (list (Notify (snapshot service)) (Build (● service epoch))))))
          (new Pair (first service) (second (Nil)))))

    ;; The service with attempt `epoch` begun: nothing is dirty yet, the
    ;; disk is trusted again, and the attempt's diagnostics are its own.

    (define (begun (service Service) (epoch I64)) (→ Service)
      (report (Service-attempt-set
               (Service-disk-set (Service-dirty-set (Service-epoch-set service epoch) #f)
                                 (Trusted))
               (Some (new Attempt (epoch epoch) (stage (Compiling)) (touched (Nil)))))
              (Building)
              (Nil)))

    ;; The description a reply carries is kept even when the build failed,
    ;; since it decides which paths are inputs.

    (define (build-replied (service Service) (epoch I64) (reply Reply))
      (→ (Pair Service (List Command)))
      (match (attempt-of service epoch)
        ((Some (Attempt _ (Compiling) touched))
         (new Pair (first (Service-attempt-set (retaining service reply)
                                               (Some (new Attempt
                                                       (epoch epoch)
                                                       (stage (Reconciling reply))
                                                       (touched touched)))))
              (second (list (Reconcile)))))
        (_ (unexpected service))))

    (define (retaining (service Service) (reply Reply)) (→ Service)
      (match (● reply description)
        ((Some description) (Service-description-set service (Some description)))
        ((None) service)))

    ;; With the disk reconciled, a candidate is published unless an input
    ;; changed while it was built, which supersedes it, or the disk could
    ;; not be read.

    (define (decide (service Service) (attempt Attempt) (reply Reply) (result (Result Unit String)))
      (→ (Pair Service (List Command)))
      (let* ((superseded (or (● service dirty)
                             (any? (lambda (path) (input-path? service path))
                                   (● attempt touched))))
             (messages (match result
                         ((Ok _) (● reply diagnostics))
                         ((Err message) (list (failure message)))))
             (service (Service-dirty-set (match result
                                           ((Ok _) service)
                                           ((Err _) (Service-disk-set service (Untrusted))))
                                         superseded)))
        (settle service attempt (● reply candidate) messages superseded)))

    (define (settle (service Service)
                    (attempt Attempt)
                    (candidate (Option Candidate))
                    (messages (List Diagnostic))
                    (superseded Bool))
      (→ (Pair Service (List Command)))
      (let ((epoch (● attempt epoch)))
        (match candidate
          ((Some candidate)
           (if (or superseded (untrusted? service))
               (staging service attempt (Discarding messages superseded) (Discard epoch))
               (staging service attempt (Publishing candidate messages) (Publish epoch))))
          ((None) (finish service attempt #t messages superseded)))))

    (define (staging (service Service) (attempt Attempt) (stage Stage) (command Command))
      (→ (Pair Service (List Command)))
      (new Pair
        (first (Service-attempt-set service (Some (Attempt-stage-set attempt stage))))
        (second (list command))))

    (define (publish-replied (service Service) (epoch I64) (error (Option String)))
      (→ (Pair Service (List Command)))
      (match (attempt-of service epoch)
        ((Some attempt)
         (match (new Pair (first (● attempt stage)) (second error))
           ((Pair (Publishing candidate messages) (None))
            (finish (Service-publications-set service
                                              (Cons (new Published (id epoch) (candidate candidate))
                                                    (● service publications)))
                    attempt
                    #f
                    messages
                    #f))
           ((Pair (Publishing _ _) (Some error))
            (finish service attempt #f (list (failure error)) #f))
           (_ (unexpected service))))
        ((None) (unexpected service))))

    (define (discard-replied (service Service) (epoch I64)) (→ (Pair Service (List Command)))
      (match (attempt-of service epoch)
        ((Some attempt)
         (match (● attempt stage)
           ((Discarding messages superseded) (finish service attempt #t messages superseded))
           (_ (unexpected service))))
        ((None) (unexpected service))))

    ;; An attempt ends by giving up its directory: abandoned, with every
    ;; generation it made, while it still owns them, or only released once
    ;; publication took them. A publication of its own puts the run
    ;; targets on its generations; then the outcome is reported, and the
    ;; next attempt armed if one is wanted.

    (define (finish (service Service)
                    (attempt Attempt)
                    (owned Bool)
                    (messages (List Diagnostic))
                    (superseded Bool))
      (→ (Pair Service (List Command)))
      (let* ((epoch (● attempt epoch))
             (accepted (accepting (Service-attempt-set service (None)) epoch))
             (reclaimed (reclaiming (● accepted first)))
             (service (report (● reclaimed first)
                              (outcome messages superseded)
                              (if superseded (Nil) messages))))
        (new Pair (first service)
             (second (concatenate (list (list (if owned (Abandon epoch) (Release epoch)))
                                        (● accepted second)
                                        (● reclaimed second)
                                        (list (Notify (snapshot service)))
                                        (arming service)))))))

    (define (outcome (messages (List Diagnostic)) (superseded Bool)) (→ Phase)
      (cond (superseded (Superseded))
            ((null? messages) (Succeeded))
            (else (Failed))))

    ;; The attempt numbered `epoch`, if it is the one in flight.

    (define (attempt-of (service Service) (epoch I64)) (→ (Option Attempt))
      (match (● service attempt)
        ((Some attempt) (if (= (● attempt epoch) epoch) (Some attempt) (None)))
        ((None) (None))))

    (define (untrusted? (service Service)) (→ Bool)
      (match (● service disk)
        ((Untrusted) #t)
        (_ #f)))

    ;; ---- Inputs ----

    ;; A path a build reads: the project's description, a library of the
    ;; project's or the repository's, the browser host's files, or the
    ;; entry or public directory of one of the description's builds, or a
    ;; directory that holds one.

    (define (input-path? (service Service) (path String)) (→ Bool)
      (let ((root (● (● service paths) root))
            (project (● (● service paths) project)))
        (or (string=? path (string-append project "/project.datum"))
            (and (or (within? project path) (within? (string-append root "/src") path))
                 (ends-with? path ".sld"))
            (within? (string-append root "/host/browser") path)
            (match (● service description)
              ((Some description) (declared-input? project description path))
              ((None) #f))
            (linked-input? service path))))

    ;; A file the latest publication's programs link, which no compile
    ;; reads, but each build places again.

    (define (linked-input? (service Service) (path String)) (→ Bool)
      (match (● service publications)
        ((Cons latest _)
         (any? (lambda (generation) (member? path (● generation linked)))
               (● (● latest candidate) generations)))
        ((Nil) #f)))

    (define (declared-input? (project String) (description Description) (path String)) (→ Bool)
      (or (any? (lambda (entry) (within? path (string-append project "/" entry)))
                (● description entries))
          (any? (lambda (public)
                  (let ((directory (string-append project "/" public)))
                    (or (within? directory path) (within? path directory))))
                (● description publics))))

    ;; Whether `path` is `directory` or under it.

    (define (within? (directory String) (path String)) (→ Bool)
      (or (string=? path directory) (starts-with? path (string-append directory "/"))))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (ends-with? (text String) (suffix String)) (→ Bool)
      (and (<= (string-length suffix) (string-length text))
           (string=?
            (substring text (- (string-length text) (string-length suffix)) (string-length text))
            suffix)))

    ;; ---- Runs ----

    ;; A publication of the attempt that just ended adds a run for each
    ;; new target it defines and stops wanting those it no longer can
    ;; launch. A run is kept once added, so a name that comes back cannot
    ;; overlap the process it had. Then every run is asked again.

    (define (accepting (service Service) (epoch I64)) (→ (Pair Service (List Command)))
      (match (published service)
        ((Some published)
         (if (= (● published id) epoch)
             (settle-runs (Service-runs-set service (accepted-runs service published)))
             (new Pair (first service) (second (Nil)))))
        ((None) (new Pair (first service) (second (Nil))))))

    (define (accepted-runs (service Service) (published Published)) (→ (List Run))
      (let* ((runs (● service runs))
             (updated (filter (lambda (definition)
                                (not (any? (lambda (run)
                                             (string=? (● run name) (● definition name)))
                                           runs)))
                              (● (● (● published candidate) description) runs))))
        (map (lambda (run) (if (available? service (● run name)) run (Run-wanted-set run #f)))
             (append runs
                     (map (lambda (definition)
                            (new Run (name (● definition name)) (wanted #f) (issued (None))))
                          updated)))))

    (define (settle-runs (service Service)) (→ (Pair Service (List Command)))
      (let ((settled (map (lambda (run) (settle-run service run)) (● service runs))))
        (new Pair
          (first (Service-runs-set service (map (lambda (record) (● record first)) settled)))
          (second (concatenate (map (lambda (record) (● record second)) settled))))))

    ;; A run asks its process for what it now wants, if that differs from
    ;; what it asked for last.

    (define (settle-run (service Service) (run Run)) (→ (Pair Run (List Command)))
      (let ((next (if (● run wanted) (launch service (● run name)) (None))))
        (if (same-intent? (● run issued) next)
            (new Pair (first run) (second (Nil)))
            (match next
              ((Some (Pair identity request))
               (new Pair (first (Run-issued-set run (Some identity)))
                    (second (list (Launch (● run name) (Some request))))))
              ((None)
               (new Pair
                 (first (Run-issued-set run (None)))
                 (second (list (Launch (● run name) (None))))))))))

    (define (same-intent? (issued (Option Identity)) (next (Option (Pair Identity RunRequest))))
      (→ Bool)
      (match (new Pair (first issued) (second next))
        ((Pair (None) (None)) #t)
        ((Pair (Some was) (Some (Pair is _)))
         (and (string=? (● was build) (● is build))
              (string=? (● was digest) (● is digest))
              (same-strings? (● was arguments) (● is arguments))))
        (_ #f)))

    (define (same-strings? (a (List String)) (b (List String))) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x rest-a) (Cons y rest-b)) (and (string=? x y) (same-strings? rest-a rest-b)))
        (_ #f)))

    ;; What the published candidate runs for the target `name`: its build's
    ;; generation, entered at its modules.json, with the target's
    ;; arguments.

    (define (launch (service Service) (name String)) (→ (Option (Pair Identity RunRequest)))
      (match (published service)
        ((Some published)
         (let ((candidate (● published candidate)))
           (match (find (lambda (definition) (string=? (● definition name) name))
                        (● (● candidate description) runs))
             ((Some definition) (launch-definition published definition))
             ((None) (None)))))
        ((None) (None))))

    (define (launch-definition (published Published) (definition RunDefinition))
      (→ (Option (Pair Identity RunRequest)))
      (match (find (lambda (generation)
                     (string=? (● generation name) (● definition build)))
                   (● (● published candidate) generations))
        ((Some generation)
         (Some (new Pair (first (new Identity (build (● definition build))
                                     (digest (● generation digest))
                                     (arguments (● definition arguments))
                                     (directory (● generation directory))))
                    (second (new RunRequest (build (● published id))
                                 (entry (string-append (● generation directory) "/modules.json"))
                                 (arguments (● definition arguments)))))))
        ((None) (None))))

    (define (available? (service Service) (name String)) (→ Bool)
      (match (launch service name)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Controlling runs ----

    (define (start-run (service Service) (name String)) (→ (Pair Service (List Command)))
      (match (required-run service name #t)
        ((Ok run)
         (if (● run wanted)
             (new Pair (first service) (second (Nil)))
             (controlled service (Run-wanted-set run #t))))
        ((Err refusal) (new Pair (first service) (second (list (Refuse refusal)))))))

    ;; A run stops whether or not its target can still launch.

    (define (stop-run (service Service) (name String)) (→ (Pair Service (List Command)))
      (match (required-run service name #f)
        ((Ok run)
         (if (● run wanted)
             (controlled service (Run-wanted-set run #f))
             (new Pair (first service) (second (Nil)))))
        ((Err refusal) (new Pair (first service) (second (list (Refuse refusal)))))))

    ;; Forgetting what it asked for makes the run ask again.

    (define (restart-run (service Service) (name String)) (→ (Pair Service (List Command)))
      (match (required-run service name #t)
        ((Ok run) (controlled service (Run-issued-set (Run-wanted-set run #t) (None))))
        ((Err refusal) (new Pair (first service) (second (list (Refuse refusal)))))))

    (define (required-run (service Service) (name String) (launchable Bool))
      (→ (Result Run Refusal))
      (cond ((● service closing) (Err (ServiceClosed)))
            ((and launchable (not (available? service name))) (Err (UnknownRunTarget name)))
            (else (match (find (lambda (run) (string=? (● run name) name)) (● service runs))
                    ((Some run) (Ok run))
                    ((None) (Err (UnknownRunTarget name)))))))

    (define (controlled (service Service) (run Run)) (→ (Pair Service (List Command)))
      (let* ((settled (settle-run service run))
             (reclaimed (reclaiming (Service-runs-set service
                                                      (map (lambda (each)
                                                             (if (string=? (● each name)
                                                                           (● run name))
                                                                 (● settled first)
                                                                 each))
                                                           (● service runs)))))
             (service (● reclaimed first)))
        (new Pair (first service)
             (second (concatenate (list (● settled second)
                                        (● reclaimed second)
                                        (list (Notify (snapshot service)))))))))

    ;; ---- Reclaiming generations ----

    ;; A publication's generations stay on disk while it is the latest or
    ;; the one before, which a page may still be loading from, and an older
    ;; one's while a run's process runs from it; the rest are reclaimed.
    ;; What was published before the service started is not its own to
    ;; reclaim, and what a publication that failed part way linked is not
    ;; among its publications, so both stay.

    (define (reclaiming (service Service)) (→ (Pair Service (List Command)))
      (let* ((publications (● service publications))
             (older (list-tail publications (min 2 (length publications))))
             (kept (append (take publications (- (length publications) (length older)))
                           (still-held older
                                       (concatenate
                                        (map issued-directory (● service runs))))))
             (needed (concatenate (map published-directories kept)))
             (dropped (filter (lambda (directory) (not (member? directory needed)))
                              (concatenate (map published-directories older)))))
        (new Pair (first (Service-publications-set service kept))
             (second (if (null? dropped) (Nil) (list (Reclaim dropped)))))))

    (define (issued-directory (run Run)) (→ (List String))
      (match (● run issued)
        ((Some identity) (list (● identity directory)))
        ((None) (Nil))))

    ;; The publications with a generation in `held`, each with only those.

    (define (still-held (publications (List Published)) (held (List String))) (→ (List Published))
      (filter (lambda (published) (not (null? (published-directories published))))
              (map (lambda (published)
                     (let ((candidate (● published candidate)))
                       (new Published (id (● published id))
                            (candidate (new Candidate (description (● candidate description))
                                            (generations (filter (lambda (generation)
                                                                   (member? (● generation directory)
                                                                            held))
                                                                 (● candidate generations)))
                                            (milliseconds (● candidate milliseconds)))))))
                   publications)))

    (define (published-directories (published Published)) (→ (List String))
      (map (lambda (record) (● record directory)) (● (● published candidate) generations)))

    (define (published (service Service)) (→ (Option Published))
      (match (● service publications)
        ((Cons latest _) (Some latest))
        ((Nil) (None))))

    ;; ---- Ending ----

    ;; Closing gives up an attempt in flight at once: the host shuts the
    ;; resident down, which finishes the request it is answering, before it
    ;; gives up the attempt's directory, as its stage says. Replies after
    ;; that are not wanted.

    (define (close (service Service)) (→ (Pair Service (List Command)))
      (if (● service closing)
          (new Pair (first service) (second (Nil)))
          (new Pair (first (Service-attempt-set (Service-closing-set service #t) (None)))
               (second (append (Cons (Shutdown) (relinquished (● service attempt)))
                               (list (Closed)))))))

    (define (relinquished (attempt (Option Attempt))) (→ (List Command))
      (match attempt
        ((Some (Attempt epoch (Publishing _ _) _)) (list (Release epoch)))
        ((Some (Attempt epoch _ _)) (list (Abandon epoch)))
        ((None) (Nil))))

    ;; A failure the service cannot continue past: the resident exited, or
    ;; answered what was not asked.

    (define (fatal (service Service) (message String)) (→ (Pair Service (List Command)))
      (if (● service closing)
          (new Pair (first service) (second (Nil)))
          (let ((service (report service (Fatal) (list (failure message)))))
            (let ((closed (close service)))
              (new Pair
                (first (● closed first))
                (second (Cons (Notify (snapshot service)) (● closed second))))))))

    (define (unexpected (service Service)) (→ (Pair Service (List Command)))
      (fatal service "unexpected compiler attempt result"))

    ;; ---- Reporting ----

    (define (report (service Service) (phase Phase) (diagnostics (List Diagnostic))) (→ Service)
      (Service-diagnostics-set (Service-phase-set service phase) diagnostics))

    (define (snapshot (service Service)) (→ Snapshot)
      (new Snapshot (phase (● service phase))
           (id (● service epoch))
           (diagnostics (● service diagnostics))
           (publications (● service publications))
           (runs (map (lambda (run)
                        (new RunStatus (name (● run name))
                             (wanted (● run wanted))
                             (available (available? service (● run name)))))
                      (● service runs)))))

    (define (failure (message String)) (→ Diagnostic)
      (new Diagnostic (message message) (source (None))))))
