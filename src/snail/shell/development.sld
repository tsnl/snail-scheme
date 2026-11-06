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
    (struct Paths
      ((root String)
       (project String)))

    ;; What the step needs of a project's description: each build's entry
    ;; and public directory, relative to the project, the names of the
    ;; builds that are browser applications, which the host serves, and its
    ;; run targets.
    (struct Description
      ((entries (List String))
       (publics (List String))
       (browsers (List String))
       (runs (List RunDefinition))))

    (struct RunDefinition
      ((name String)
       (build String)
       (arguments (List String))))

    ;; A built target of a candidate: its generation's directory, the
    ;; digest of what it holds, the digests of its files but its modules,
    ;; by relative name, which the host's pages compare, and the paths of
    ;; the files its program links, which are inputs while it is published.
    (struct Generation
      ((name String)
       (directory String)
       (digest String)
       (files (List (Pair String String)))
       (linked (List String))))

    ;; A build's targets, and how long it took, which the host's pages show.
    (struct Candidate
      ((description Description)
       (generations (List Generation))
       (milliseconds I64)))

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
    ;; that ended is not run again by a publication that changed nothing,
    ;; and a process asked again for the same digest keeps running from the
    ;; generation `directory` it was started in.
    (struct Identity
      ((build String)
       (digest String)
       (arguments (List String))
       (directory String)))

    (struct RunRequest
      ((build I64)
       (entry String)
       (arguments (List String))))

    (struct Run
      ((name String)
       (wanted Bool)
       (issued (Option Identity))))

    ;; `publications` are those whose generations are still on disk, newest
    ;; first, the latest being the one published.
    (struct Service
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

    (: new-service (-> String String Service))
    (define (new-service root project)
      (Service (Paths root project)
               0
               (None)
               (Nil)
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

    ;; What subscribers see: the publications are the service's, newest
    ;; first, the latest being the one published. The host adds each run's
    ;; process status.
    (struct Snapshot
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

    (: step (-> Service Event (Pair Service (List Command))))
    (define (step service event)
      (match event
        ((ResidentStarted) (Pair service (if (::closing service) (Nil) (list (Reconcile)))))
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
      (and (::dirty service)
           (not (::closing service))
           (match (::disk service)
             ((Unscanned) #f)
             (_ #t))
           (match (::attempt service)
             ((None) #t)
             ((Some _) #f))))

    (: arming (-> Service (List Command)))
    (define (arming service)
      (if (ready? service) (list (Arm)) (Nil)))

    (: request-build (-> Service (Pair Service (List Command))))
    (define (request-build service)
      (if (::closing service)
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
      (match (::attempt service)
        ((Some attempt)
         (Service-attempt-set service
                              (Some (Attempt-touched-set attempt
                                                         (append (::touched attempt)
                                                                 paths)))))
        ((None) service)))

    ;; A reconciliation, not an uncertain disk, establishes a change. Once
    ;; the disk can be read again after a failure, a build is wanted.
    (: uncertain (-> Service (Option String) (Pair Service (List Command))))
    (define (uncertain service error)
      (match (Pair (::disk service) error)
        ((Pair (Untrusted) (None)) (request-build service))
        (_ (Pair service (Nil)))))

    ;; The first reconciliation, at start-up, decides whether builds may
    ;; begin; one during an attempt decides what becomes of its reply.
    (: reconciled (-> Service (Result Unit String) (Pair Service (List Command))))
    (define (reconciled service result)
      (match (::attempt service)
        ((None) (scanned service result))
        ((Some attempt)
         (match (::stage attempt)
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
          (let ((service (begun service (+ (::epoch service) 1))))
            (Pair service (list (Notify (snapshot service)) (Build (::epoch service)))))
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
      (match (::description reply)
        ((Some description) (Service-description-set service (Some description)))
        ((None) service)))

    ;; With the disk reconciled, a candidate is published unless an input
    ;; changed while it was built, which supersedes it, or the disk could
    ;; not be read.
    (: decide (-> Service Attempt Reply (Result Unit String) (Pair Service (List Command))))
    (define (decide service attempt reply result)
      (let* ((superseded (or (::dirty service)
                             (any? (lambda (path) (input-path? service path))
                                   (::touched attempt))))
             (messages (match result
                         ((Ok _) (::diagnostics reply))
                         ((Err message) (list (failure message)))))
             (service (Service-dirty-set (match result
                                           ((Ok _) service)
                                           ((Err _) (Service-disk-set service (Untrusted))))
                                         superseded)))
        (settle service attempt (::candidate reply) messages superseded)))

    (: settle
       (-> Service Attempt (Option Candidate) (List Diagnostic) Bool (Pair Service (List Command))))
    (define (settle service attempt candidate messages superseded)
      (let ((epoch (::epoch attempt)))
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
         (match (Pair (::stage attempt) error)
           ((Pair (Publishing candidate messages) (None))
            (finish (Service-publications-set service
                                              (Cons (Published epoch candidate)
                                                    (::publications service)))
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
         (match (::stage attempt)
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
      (let* ((epoch (::epoch attempt))
             (accepted (accepting (Service-attempt-set service (None)) epoch))
             (reclaimed (reclaiming (::first accepted)))
             (service (report (::first reclaimed)
                              (outcome messages superseded)
                              (if superseded (Nil) messages))))
        (Pair service
              (concatenate (list (list (if owned (Abandon epoch) (Release epoch)))
                                 (::second accepted)
                                 (::second reclaimed)
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
      (match (::attempt service)
        ((Some attempt) (if (= (::epoch attempt) epoch) (Some attempt) (None)))
        ((None) (None))))

    (: untrusted? (-> Service Bool))
    (define (untrusted? service)
      (match (::disk service)
        ((Untrusted) #t)
        (_ #f)))

    ;; ---- Inputs ----

    ;; A path a build reads: the project's description, a library of the
    ;; project's or the repository's, the browser host's files, or the
    ;; entry or public directory of one of the description's builds, or a
    ;; directory that holds one.
    (: input-path? (-> Service String Bool))
    (define (input-path? service path)
      (let ((root (::root (::paths service)))
            (project (::project (::paths service))))
        (or (string=? path (string-append project "/project.datum"))
            (and (or (within? project path) (within? (string-append root "/src") path))
                 (ends-with? path ".sld"))
            (within? (string-append root "/host/browser") path)
            (match (::description service)
              ((Some description) (declared-input? project description path))
              ((None) #f))
            (linked-input? service path))))

    ;; A file the latest publication's programs link, which no compile
    ;; reads, but each build places again.
    (: linked-input? (-> Service String Bool))
    (define (linked-input? service path)
      (match (::publications service)
        ((Cons latest _)
         (any? (lambda (generation) (member? path (::linked generation)))
               (::generations (::candidate latest))))
        ((Nil) #f)))

    (: declared-input? (-> String Description String Bool))
    (define (declared-input? project description path)
      (or (any? (lambda (entry) (within? path (string-append project "/" entry)))
                (::entries description))
          (any? (lambda (public)
                  (let ((directory (string-append project "/" public)))
                    (or (within? directory path) (within? path directory))))
                (::publics description))))

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
      (match (published service)
        ((Some published)
         (if (= (::id published) epoch)
             (settle-runs (Service-runs-set service (accepted-runs service published)))
             (Pair service (Nil))))
        ((None) (Pair service (Nil)))))

    (: accepted-runs (-> Service Published (List Run)))
    (define (accepted-runs service published)
      (let* ((runs (::runs service))
             (new (filter (lambda (definition)
                            (not (any? (lambda (run)
                                         (string=? (::name run) (::name definition)))
                                       runs)))
                          (::runs
                           (::description (::candidate published))))))
        (map (lambda (run) (if (available? service (::name run)) run (Run-wanted-set run #f)))
             (append runs
                     (map (lambda (definition) (Run (::name definition) #f (None)))
                          new)))))

    (: settle-runs (-> Service (Pair Service (List Command))))
    (define (settle-runs service)
      (let ((settled (map (lambda (run) (settle-run service run)) (::runs service))))
        (Pair (Service-runs-set service (map ::first settled))
              (concatenate (map ::second settled)))))

    ;; A run asks its process for what it now wants, if that differs from
    ;; what it asked for last.
    (: settle-run (-> Service Run (Pair Run (List Command))))
    (define (settle-run service run)
      (let ((next (if (::wanted run) (launch service (::name run)) (None))))
        (if (same-intent? (::issued run) next)
            (Pair run (Nil))
            (match next
              ((Some (Pair identity request))
               (Pair (Run-issued-set run (Some identity))
                     (list (Launch (::name run) (Some request)))))
              ((None) (Pair (Run-issued-set run (None)) (list (Launch (::name run) (None)))))))))

    (: same-intent? (-> (Option Identity) (Option (Pair Identity RunRequest)) Bool))
    (define (same-intent? issued next)
      (match (Pair issued next)
        ((Pair (None) (None)) #t)
        ((Pair (Some was) (Some (Pair is _)))
         (and (string=? (::build was) (::build is))
              (string=? (::digest was) (::digest is))
              (same-strings? (::arguments was) (::arguments is))))
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
      (match (published service)
        ((Some published)
         (let ((candidate (::candidate published)))
           (match (find (lambda (definition) (string=? (::name definition) name))
                        (::runs (::description candidate)))
             ((Some definition) (launch-definition published definition))
             ((None) (None)))))
        ((None) (None))))

    (: launch-definition (-> Published RunDefinition (Option (Pair Identity RunRequest))))
    (define (launch-definition published definition)
      (match (find (lambda (generation)
                     (string=? (::name generation) (::build definition)))
                   (::generations (::candidate published)))
        ((Some generation)
         (Some (Pair (Identity (::build definition)
                               (::digest generation)
                               (::arguments definition)
                               (::directory generation))
                     (RunRequest (::id published)
                                 (string-append (::directory generation) "/modules.json")
                                 (::arguments definition)))))
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
         (if (::wanted run) (Pair service (Nil)) (controlled service (Run-wanted-set run #t))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    ;; A run stops whether or not its target can still launch.
    (: stop-run (-> Service String (Pair Service (List Command))))
    (define (stop-run service name)
      (match (required-run service name #f)
        ((Ok run)
         (if (::wanted run) (controlled service (Run-wanted-set run #f)) (Pair service (Nil))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    ;; Forgetting what it asked for makes the run ask again.
    (: restart-run (-> Service String (Pair Service (List Command))))
    (define (restart-run service name)
      (match (required-run service name #t)
        ((Ok run) (controlled service (Run-issued-set (Run-wanted-set run #t) (None))))
        ((Err refusal) (Pair service (list (Refuse refusal))))))

    (: required-run (-> Service String Bool (Result Run Refusal)))
    (define (required-run service name launchable)
      (cond ((::closing service) (Err (ServiceClosed)))
            ((and launchable (not (available? service name))) (Err (UnknownRunTarget name)))
            (else (match (find (lambda (run) (string=? (::name run) name)) (::runs service))
                    ((Some run) (Ok run))
                    ((None) (Err (UnknownRunTarget name)))))))

    (: controlled (-> Service Run (Pair Service (List Command))))
    (define (controlled service run)
      (let* ((settled (settle-run service run))
             (reclaimed (reclaiming (Service-runs-set service
                                                      (map (lambda (each)
                                                             (if (string=? (::name each)
                                                                           (::name run))
                                                                 (::first settled)
                                                                 each))
                                                           (::runs service)))))
             (service (::first reclaimed)))
        (Pair service
              (concatenate (list (::second settled)
                                 (::second reclaimed)
                                 (list (Notify (snapshot service))))))))

    ;; ---- Reclaiming generations ----

    ;; A publication's generations stay on disk while it is the latest or
    ;; the one before, which a page may still be loading from, and an older
    ;; one's while a run's process runs from it; the rest are reclaimed.
    ;; What was published before the service started is not its own to
    ;; reclaim, and what a publication that failed part way linked is not
    ;; among its publications, so both stay.
    (: reclaiming (-> Service (Pair Service (List Command))))
    (define (reclaiming service)
      (let* ((publications (::publications service))
             (older (list-tail publications (min 2 (length publications))))
             (kept (append (take publications (- (length publications) (length older)))
                           (still-held older
                                       (concatenate
                                        (map issued-directory (::runs service))))))
             (needed (concatenate (map published-directories kept)))
             (dropped (filter (lambda (directory) (not (member? directory needed)))
                              (concatenate (map published-directories older)))))
        (Pair (Service-publications-set service kept)
              (if (null? dropped) (Nil) (list (Reclaim dropped))))))

    (: issued-directory (-> Run (List String)))
    (define (issued-directory run)
      (match (::issued run)
        ((Some identity) (list (::directory identity)))
        ((None) (Nil))))

    ;; The publications with a generation in `held`, each with only those.
    (: still-held (-> (List Published) (List String) (List Published)))
    (define (still-held publications held)
      (filter (lambda (published) (not (null? (published-directories published))))
              (map (lambda (published)
                     (let ((candidate (::candidate published)))
                       (Published (::id published)
                                  (Candidate (::description candidate)
                                             (filter (lambda (generation)
                                                       (member? (::directory generation)
                                                                held))
                                                     (::generations candidate))
                                             (::milliseconds candidate)))))
                   publications)))

    (: published-directories (-> Published (List String)))
    (define (published-directories published)
      (map ::directory (::generations (::candidate published))))

    (: published (-> Service (Option Published)))
    (define (published service)
      (match (::publications service)
        ((Cons latest _) (Some latest))
        ((Nil) (None))))

    ;; ---- Ending ----

    ;; Closing gives up an attempt in flight at once: the host shuts the
    ;; resident down, which finishes the request it is answering, before it
    ;; gives up the attempt's directory, as its stage says. Replies after
    ;; that are not wanted.
    (: close (-> Service (Pair Service (List Command))))
    (define (close service)
      (if (::closing service)
          (Pair service (Nil))
          (Pair (Service-attempt-set (Service-closing-set service #t) (None))
                (append (Cons (Shutdown) (relinquished (::attempt service)))
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
      (if (::closing service)
          (Pair service (Nil))
          (let ((service (report service (Fatal) (list (failure message)))))
            (let ((closed (close service)))
              (Pair (::first closed) (Cons (Notify (snapshot service)) (::second closed)))))))

    (: unexpected (-> Service (Pair Service (List Command))))
    (define (unexpected service)
      (fatal service "unexpected compiler attempt result"))

    ;; ---- Reporting ----

    (: report (-> Service Phase (List Diagnostic) Service))
    (define (report service phase diagnostics)
      (Service-diagnostics-set (Service-phase-set service phase) diagnostics))

    (: snapshot (-> Service Snapshot))
    (define (snapshot service)
      (Snapshot (::phase service)
                (::epoch service)
                (::diagnostics service)
                (::publications service)
                (map (lambda (run)
                       (RunStatus (::name run)
                                  (::wanted run)
                                  (available? service (::name run))))
                     (::runs service))))

    (: failure (-> String Diagnostic))
    (define (failure message)
      (Diagnostic message (None)))))
