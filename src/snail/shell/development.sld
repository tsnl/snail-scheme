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
;;   none.
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
   Candidate-description
   Candidate-generations
   SourcePoint
   SourcePoint-file
   SourcePoint-line
   SourcePoint-column
   Diagnostic
   Diagnostic-message
   Diagnostic-source
   Reply
   Reply-candidate
   Published
   Published-id
   Published-candidate
   Phase
   Starting
   Building
   Succeeded
   Failed
   Superseded
   Fatal
   RunRequest
   RunRequest-build
   RunRequest-entry
   RunRequest-arguments
   RunStatus
   RunStatus-name
   RunStatus-wanted
   RunStatus-available
   Snapshot
   Snapshot-phase
   Snapshot-id
   Snapshot-diagnostics
   Snapshot-published
   Snapshot-runs
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
    (struct Paths
      ((root String)
       (project String)))

    ;; What the step needs of a project's description: each build's entry
    ;; and public directory, relative to the project, and its run targets.
    (struct Description
      ((entries (List String))
       (publics (List String))
       (runs (List RunDefinition))))

    (struct RunDefinition
      ((name String)
       (build String)
       (arguments (List String))))

    ;; A built target of a candidate: its generation's directory and the
    ;; digest of what it holds.
    (struct Generation
      ((name String)
       (directory String)
       (digest String)))

    (struct Candidate
      ((description Description)
       (generations (List Generation))))

    (struct SourcePoint
      ((file String)
       (line I64)
       (column I64)))

    (struct Diagnostic
      ((message String)
       (source (Option SourcePoint))))

    ;; The resident's answer to a build: the description it read, even
    ;; when the build failed; a candidate, when it succeeded; and its
    ;; diagnostics.
    (struct Reply
      ((description (Option Description))
       (candidate (Option Candidate))
       (diagnostics (List Diagnostic))))

    (struct Published
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

    (struct Attempt
      ((epoch I64)
       (stage Stage)
       (touched (List String))))

    ;; What a run target last asked its process to run: the build, the
    ;; digest of its generation and the arguments, none once it asked for
    ;; nothing. A run is asked again only when this changes, so a process
    ;; that ended is not run again by a publication that changed nothing.
    (struct Identity
      ((build String)
       (digest String)
       (arguments (List String))))

    (struct RunRequest
      ((build I64)
       (entry String)
       (arguments (List String))))

    (struct Run
      ((name String)
       (wanted Bool)
       (issued (Option Identity))))

    (struct Service
      ((paths Paths)
       (epoch I64)
       (attempt (Option Attempt))
       (published (Option Published))
       (description (Option Description))
       (dirty Bool)
       (disk Disk)
       (closing Bool)
       (phase Phase)
       (diagnostics (List Diagnostic))
       (runs (List Run))))

    (: new-service (-> String String Service))
    (define (new-service root project)
      (Service (Paths root project)
               0
               (None)
               (None)
               (None)
               #t
               (Unscanned)
               #f
               (Starting)
               (Nil)
               (Nil)))

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

    (struct RunStatus
      ((name String)
       (wanted Bool)
       (available Bool)))

    ;; What subscribers see. The host adds each run's process status.
    (struct Snapshot
      ((phase Phase)
       (id I64)
       (diagnostics (List Diagnostic))
       (published (Option Published))
       (runs (List RunStatus))))

    (enum Refusal
      (UnknownRunTarget ((name String)))
      (ServiceClosed))

    ;; `Shutdown` stops the observer, the resident and every process, and
    ;; waits for them, before the commands after it run.
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
      (Shutdown)
      (Closed))

    (: step (-> Service Event (Pair Service (List Command))))
    (define (step service event)
      (match event
        ((ResidentStarted) (Pair service (if (Service-closing service) (Nil) (list (Reconcile)))))
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
    (: ready? (-> Service Bool))
    (define (ready? service)
      (and (Service-dirty service)
           (not (Service-closing service))
           (match (Service-disk service)
             ((Unscanned) #f)
             (_ #t))
           (match (Service-attempt service)
             ((None) #t)
             ((Some _) #f))))

    (: arming (-> Service (List Command)))
    (define (arming service)
      (if (ready? service) (list (Arm)) (Nil)))

    (: request-build (-> Service (Pair Service (List Command))))
    (define (request-build service)
      (if (Service-closing service)
          (Pair service (Nil))
          (let ((service (Service-dirty-set service #t))) (Pair service (arming service)))))

    ;; A changed path joins the attempt's, whatever it is, since the
    ;; description that decides whether it is an input may be the one the
    ;; attempt's reply brings.
    (: touched (-> Service (List String) (Pair Service (List Command))))
    (define (touched service paths)
      (let ((service (touching service paths)))
        (if (any? (lambda (path) (input-path? service path)) paths)
            (request-build service)
            (Pair service (Nil)))))

    (: touching (-> Service (List String) Service))
    (define (touching service paths)
      (match (Service-attempt service)
        ((Some attempt)
         (Service-attempt-set service
                              (Some (Attempt-touched-set attempt
                                                         (append (Attempt-touched attempt)
                                                                 paths)))))
        ((None) service)))

    ;; A reconciliation, not an uncertain disk, establishes a change. Once
    ;; the disk can be read again after a failure, a build is wanted.
    (: uncertain (-> Service (Option String) (Pair Service (List Command))))
    (define (uncertain service error)
      (match (Pair (Service-disk service) error)
        ((Pair (Untrusted) (None)) (request-build service))
        (_ (Pair service (Nil)))))

    ;; The first reconciliation, at start-up, decides whether builds may
    ;; begin; one during an attempt decides what becomes of its reply.
    (: reconciled (-> Service (Result Unit String) (Pair Service (List Command))))
    (define (reconciled service result)
      (match (Service-attempt service)
        ((None) (scanned service result))
        ((Some attempt)
         (match (Attempt-stage attempt)
           ((Reconciling reply) (decide service attempt reply result))
           (_ (unexpected service))))))

    (: scanned (-> Service (Result Unit String) (Pair Service (List Command))))
    (define (scanned service result)
      (match result
        ((Ok _)
         (let ((service (Service-disk-set service (Trusted)))) (Pair service (arming service))))
        ((Err message)
         (let ((service
                (report (Service-disk-set service (Untrusted)) (Failed) (list (failure message)))))
           (Pair service (list (Notify (snapshot service))))))))

    ;; ---- Attempts ----

    ;; Subscribers see the attempt begin, and earlier diagnostics go,
    ;; before the resident is asked to build.
    (: timer-fired (-> Service (Pair Service (List Command))))
    (define (timer-fired service)
      (if (ready? service)
          (let ((service (begun service (+ (Service-epoch service) 1))))
            (Pair service (list (Notify (snapshot service)) (Build (Service-epoch service)))))
          (Pair service (Nil))))

    ;; The service with attempt `epoch` begun: nothing is dirty yet, the
    ;; disk is trusted again, and the attempt's diagnostics are its own.
    (: begun (-> Service I64 Service))
    (define (begun service epoch)
      (report (Service-attempt-set
               (Service-disk-set (Service-dirty-set (Service-epoch-set service epoch) #f)
                                 (Trusted))
               (Some (Attempt epoch (Compiling) (Nil))))
              (Building)
              (Nil)))

    ;; The description a reply carries is kept even when the build failed,
    ;; since it decides which paths are inputs.
    (: build-replied (-> Service I64 Reply (Pair Service (List Command))))
    (define (build-replied service epoch reply)
      (match (attempt-of service epoch)
        ((Some (Attempt _ (Compiling) touched))
         (Pair (Service-attempt-set (retaining service reply)
                                    (Some (Attempt epoch (Reconciling reply) touched)))
               (list (Reconcile))))
        (_ (unexpected service))))

    (: retaining (-> Service Reply Service))
    (define (retaining service reply)
      (match (Reply-description reply)
        ((Some description) (Service-description-set service (Some description)))
        ((None) service)))

    ;; With the disk reconciled, a candidate is published unless an input
    ;; changed while it was built, which supersedes it, or the disk could
    ;; not be read.
    (: decide (-> Service Attempt Reply (Result Unit String) (Pair Service (List Command))))
    (define (decide service attempt reply result)
      (let* ((superseded (or (Service-dirty service)
                             (any? (lambda (path) (input-path? service path))
                                   (Attempt-touched attempt))))
             (messages (match result
                         ((Ok _) (Reply-diagnostics reply))
                         ((Err message) (list (failure message)))))
             (service (Service-dirty-set (match result
                                           ((Ok _) service)
                                           ((Err _) (Service-disk-set service (Untrusted))))
                                         superseded)))
        (settle service attempt (Reply-candidate reply) messages superseded)))

    (: settle
       (-> Service Attempt (Option Candidate) (List Diagnostic) Bool (Pair Service (List Command))))
    (define (settle service attempt candidate messages superseded)
      (let ((epoch (Attempt-epoch attempt)))
        (match candidate
          ((Some candidate)
           (if (or superseded (untrusted? service))
               (staging service attempt (Discarding messages superseded) (Discard epoch))
               (staging service attempt (Publishing candidate messages) (Publish epoch))))
          ((None) (finish service attempt #t messages superseded)))))

    (: staging (-> Service Attempt Stage Command (Pair Service (List Command))))
    (define (staging service attempt stage command)
      (Pair (Service-attempt-set service (Some (Attempt-stage-set attempt stage))) (list command)))

    (: publish-replied (-> Service I64 (Option String) (Pair Service (List Command))))
    (define (publish-replied service epoch error)
      (match (attempt-of service epoch)
        ((Some attempt)
         (match (Pair (Attempt-stage attempt) error)
           ((Pair (Publishing candidate messages) (None))
            (finish (Service-published-set service (Some (Published epoch candidate)))
                    attempt
                    #f
                    messages
                    #f))
           ((Pair (Publishing _ _) (Some error))
            (finish service attempt #f (list (failure error)) #f))
           (_ (unexpected service))))
        ((None) (unexpected service))))

    (: discard-replied (-> Service I64 (Pair Service (List Command))))
    (define (discard-replied service epoch)
      (match (attempt-of service epoch)
        ((Some attempt)
         (match (Attempt-stage attempt)
           ((Discarding messages superseded) (finish service attempt #t messages superseded))
           (_ (unexpected service))))
        ((None) (unexpected service))))

    ;; An attempt ends by giving up its directory: abandoned, with every
    ;; generation it made, while it still owns them, or only released once
    ;; publication took them. A publication of its own puts the run
    ;; targets on its generations; then the outcome is reported, and the
    ;; next attempt armed if one is wanted.
    (: finish (-> Service Attempt Bool (List Diagnostic) Bool (Pair Service (List Command))))
    (define (finish service attempt owned messages superseded)
      (let* ((epoch (Attempt-epoch attempt))
             (accepted (accepting (Service-attempt-set service (None)) epoch))
             (service (report (Pair-first accepted)
                              (outcome messages superseded)
                              (if superseded (Nil) messages))))
        (Pair service
              (concatenate (list (list (if owned (Abandon epoch) (Release epoch)))
                                 (Pair-second accepted)
                                 (list (Notify (snapshot service)))
                                 (arming service))))))

    (: outcome (-> (List Diagnostic) Bool Phase))
    (define (outcome messages superseded)
      (cond (superseded (Superseded))
            ((null? messages) (Succeeded))
            (else (Failed))))

    ;; The attempt numbered `epoch`, if it is the one in flight.
    (: attempt-of (-> Service I64 (Option Attempt)))
    (define (attempt-of service epoch)
      (match (Service-attempt service)
        ((Some attempt) (if (= (Attempt-epoch attempt) epoch) (Some attempt) (None)))
        ((None) (None))))

    (: untrusted? (-> Service Bool))
    (define (untrusted? service)
      (match (Service-disk service)
        ((Untrusted) #t)
        (_ #f)))

    ;; ---- Inputs ----

    ;; A path a build reads: the project's description, a library of the
    ;; project's or the repository's, the browser host's files, or the
    ;; entry or public directory of one of the description's builds, or a
    ;; directory that holds one.
    (: input-path? (-> Service String Bool))
    (define (input-path? service path)
      (let ((root (Paths-root (Service-paths service)))
            (project (Paths-project (Service-paths service))))
        (or (string=? path (string-append project "/project.datum"))
            (and (or (within? project path) (within? (string-append root "/src") path))
                 (ends-with? path ".sld"))
            (within? (string-append root "/host/browser") path)
            (match (Service-description service)
              ((Some description) (declared-input? project description path))
              ((None) #f)))))

    (: declared-input? (-> String Description String Bool))
    (define (declared-input? project description path)
      (or (any? (lambda (entry) (within? path (string-append project "/" entry)))
                (Description-entries description))
          (any? (lambda (public)
                  (let ((directory (string-append project "/" public)))
                    (or (within? directory path) (within? path directory))))
                (Description-publics description))))

    ;; Whether `path` is `directory` or under it.
    (: within? (-> String String Bool))
    (define (within? directory path)
      (or (string=? path directory) (starts-with? path (string-append directory "/"))))

    (: starts-with? (-> String String Bool))
    (define (starts-with? text prefix)
      (and (<= (string-length prefix) (string-length text))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (: ends-with? (-> String String Bool))
    (define (ends-with? text suffix)
      (and (<= (string-length suffix) (string-length text))
           (string=?
            (substring text (- (string-length text) (string-length suffix)) (string-length text))
            suffix)))

    ;; ---- Runs ----

    ;; A publication of the attempt that just ended adds a run for each
    ;; new target it defines and stops wanting those it no longer can
    ;; launch. A run is kept once added, so a name that comes back cannot
    ;; overlap the process it had. Then every run is asked again.
    (: accepting (-> Service I64 (Pair Service (List Command))))
    (define (accepting service epoch)
      (match (Service-published service)
        ((Some published)
         (if (= (Published-id published) epoch)
             (settle-runs (Service-runs-set service (accepted-runs service published)))
             (Pair service (Nil))))
        ((None) (Pair service (Nil)))))

    (: accepted-runs (-> Service Published (List Run)))
    (define (accepted-runs service published)
      (let* ((runs (Service-runs service))
             (new (filter (lambda (definition)
                            (not (any? (lambda (run)
                                         (string=? (Run-name run) (RunDefinition-name definition)))
                                       runs)))
                          (Description-runs
                           (Candidate-description (Published-candidate published))))))
        (map (lambda (run) (if (available? service (Run-name run)) run (Run-wanted-set run #f)))
             (append runs
                     (map (lambda (definition) (Run (RunDefinition-name definition) #f (None)))
                          new)))))

    (: settle-runs (-> Service (Pair Service (List Command))))
    (define (settle-runs service)
      (let ((settled (map (lambda (run) (settle-run service run)) (Service-runs service))))
        (Pair (Service-runs-set service (map Pair-first settled))
              (concatenate (map Pair-second settled)))))

    ;; A run asks its process for what it now wants, if that differs from
    ;; what it asked for last.
    (: settle-run (-> Service Run (Pair Run (List Command))))
    (define (settle-run service run)
      (let ((next (if (Run-wanted run) (launch service (Run-name run)) (None))))
        (if (same-intent? (Run-issued run) next)
            (Pair run (Nil))
            (match next
              ((Some (Pair identity request))
               (Pair (Run-issued-set run (Some identity))
                     (list (Launch (Run-name run) (Some request)))))
              ((None) (Pair (Run-issued-set run (None)) (list (Launch (Run-name run) (None)))))))))

    (: same-intent? (-> (Option Identity) (Option (Pair Identity RunRequest)) Bool))
    (define (same-intent? issued next)
      (match (Pair issued next)
        ((Pair (None) (None)) #t)
        ((Pair (Some was) (Some (Pair is _)))
         (and (string=? (Identity-build was) (Identity-build is))
              (string=? (Identity-digest was) (Identity-digest is))
              (same-strings? (Identity-arguments was) (Identity-arguments is))))
        (_ #f)))

    (: same-strings? (-> (List String) (List String) Bool))
    (define (same-strings? a b)
      (match (Pair a b)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons x rest-a) (Cons y rest-b)) (and (string=? x y) (same-strings? rest-a rest-b)))
        (_ #f)))

    ;; What the published candidate runs for the target `name`: its build's
    ;; generation, entered at its modules.json, with the target's
    ;; arguments.
    (: launch (-> Service String (Option (Pair Identity RunRequest))))
    (define (launch service name)
      (match (Service-published service)
        ((Some published)
         (let ((candidate (Published-candidate published)))
           (match (find (lambda (definition) (string=? (RunDefinition-name definition) name))
                        (Description-runs (Candidate-description candidate)))
             ((Some definition) (launch-definition published definition))
             ((None) (None)))))
        ((None) (None))))

    (: launch-definition (-> Published RunDefinition (Option (Pair Identity RunRequest))))
    (define (launch-definition published definition)
      (match (find (lambda (generation)
                     (string=? (Generation-name generation) (RunDefinition-build definition)))
                   (Candidate-generations (Published-candidate published)))
        ((Some generation)
         (Some (Pair (Identity (RunDefinition-build definition)
                               (Generation-digest generation)
                               (RunDefinition-arguments definition))
                     (RunRequest (Published-id published)
                                 (string-append (Generation-directory generation) "/modules.json")
                                 (RunDefinition-arguments definition)))))
        ((None) (None))))

    (: available? (-> Service String Bool))
    (define (available? service name)
      (match (launch service name)
        ((Some _) #t)
        ((None) #f)))

    ;; ---- Controlling runs ----

    (: start-run (-> Service String (Pair Service (List Command))))
    (define (start-run service name)
      (match (required-run service name #t)
        ((Ok run)
         (if (Run-wanted run) (Pair service (Nil)) (controlled service (Run-wanted-set run #t))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    ;; A run stops whether or not its target can still launch.
    (: stop-run (-> Service String (Pair Service (List Command))))
    (define (stop-run service name)
      (match (required-run service name #f)
        ((Ok run)
         (if (Run-wanted run) (controlled service (Run-wanted-set run #f)) (Pair service (Nil))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    ;; Forgetting what it asked for makes the run ask again.
    (: restart-run (-> Service String (Pair Service (List Command))))
    (define (restart-run service name)
      (match (required-run service name #t)
        ((Ok run) (controlled service (Run-issued-set (Run-wanted-set run #t) (None))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    (: required-run (-> Service String Bool (Result Run Refusal)))
    (define (required-run service name launchable)
      (cond ((Service-closing service) (Err (ServiceClosed)))
            ((and launchable (not (available? service name))) (Err (UnknownRunTarget name)))
            (else (match (find (lambda (run) (string=? (Run-name run) name)) (Service-runs service))
                    ((Some run) (Ok run))
                    ((None) (Err (UnknownRunTarget name)))))))

    (: controlled (-> Service Run (Pair Service (List Command))))
    (define (controlled service run)
      (let* ((settled (settle-run service run))
             (service (Service-runs-set service
                                        (map (lambda (each)
                                               (if (string=? (Run-name each) (Run-name run))
                                                   (Pair-first settled)
                                                   each))
                                             (Service-runs service)))))
        (Pair service (append (Pair-second settled) (list (Notify (snapshot service)))))))

    ;; ---- Ending ----

    ;; Closing gives up an attempt in flight at once: the host shuts the
    ;; resident down, which finishes the request it is answering, before it
    ;; gives up the attempt's directory, as its stage says. Replies after
    ;; that are not wanted.
    (: close (-> Service (Pair Service (List Command))))
    (define (close service)
      (if (Service-closing service)
          (Pair service (Nil))
          (Pair (Service-attempt-set (Service-closing-set service #t) (None))
                (append (Cons (Shutdown) (relinquished (Service-attempt service)))
                        (list (Closed))))))

    (: relinquished (-> (Option Attempt) (List Command)))
    (define (relinquished attempt)
      (match attempt
        ((Some (Attempt epoch (Publishing _ _) _)) (list (Release epoch)))
        ((Some (Attempt epoch _ _)) (list (Abandon epoch)))
        ((None) (Nil))))

    ;; A failure the service cannot continue past: the resident exited, or
    ;; answered what was not asked.
    (: fatal (-> Service String (Pair Service (List Command))))
    (define (fatal service message)
      (if (Service-closing service)
          (Pair service (Nil))
          (let ((service (report service (Fatal) (list (failure message)))))
            (let ((closed (close service)))
              (Pair (Pair-first closed) (Cons (Notify (snapshot service)) (Pair-second closed)))))))

    (: unexpected (-> Service (Pair Service (List Command))))
    (define (unexpected service)
      (fatal service "unexpected compiler attempt result"))

    ;; ---- Reporting ----

    (: report (-> Service Phase (List Diagnostic) Service))
    (define (report service phase diagnostics)
      (Service-diagnostics-set (Service-phase-set service phase) diagnostics))

    (: snapshot (-> Service Snapshot))
    (define (snapshot service)
      (Snapshot (Service-phase service)
                (Service-epoch service)
                (Service-diagnostics service)
                (Service-published service)
                (map (lambda (run)
                       (RunStatus (Run-name run)
                                  (Run-wanted run)
                                  (available? service (Run-name run))))
                     (Service-runs service))))

    (: failure (-> String Diagnostic))
    (define (failure message)
      (Diagnostic message (None)))))
