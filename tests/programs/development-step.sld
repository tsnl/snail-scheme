(import
 (snail core base)
 (snail core io)
 (snail shell development))

;; The development service's step, driven through the races its host can
;; deliver: edits that coalesce or supersede an attempt, replies that are
;; late or for another epoch, a disk that cannot be read, publication
;; that partly fails, closing and the resident's exit with an attempt in
;; flight, and run targets wanted across publications. Each line is an
;; event and the commands the step answers with.

;; ---- A project ----

(define root "/r")

(define project "/r/apps/p")

(: description Description)
(define description
  (Description (list "main.sld")
               (list "public")
               (Nil)
               (list (RunDefinition "app" "server" (list "--port")))))

(: candidate (-> String Candidate))
(define (candidate digest)
  (Candidate description
             (list (Generation "server" (string-append "/r/apps/p/build/s-" digest) digest (Nil)))
             0))

(: succeeded (-> String Reply))
(define (succeeded digest)
  (Reply (Some description) (Some (candidate digest)) (Nil)))

;; A build into generation `name`, whose files have the digest given, as a
;; build of an unchanged program does into a new generation.
(: built-in (-> String String Reply))
(define (built-in name digest)
  (Reply (Some description)
         (Some (Candidate description
                          (list (Generation "server"
                                            (string-append "/r/apps/p/build/" name)
                                            digest
                                            (Nil)))
                          0))
         (Nil)))

;; An edit, and the attempt it starts built and published as `epoch`.
(: rebuilt (-> I64 Reply (List Event)))
(define (rebuilt epoch reply)
  (list (Touched (list "/r/apps/p/main.sld"))
        (TimerFired)
        (BuildReplied epoch reply)
        (Reconciled (Ok (unit)))
        (PublishReplied epoch (None))))

(: failed Reply)
(define failed
  (Reply (Some description)
         (None)
         (list (Diagnostic "unbound identifier x" (Some (SourcePoint "/r/apps/p/main.sld" 1 2))))))

;; A publication whose description has no run targets.
(: without-runs Reply)
(define without-runs
  (let ((bare (Description (list "main.sld") (Nil) (Nil) (Nil))))
    (Reply (Some bare)
           (Some (Candidate bare (list (Generation "server" "/r/apps/p/build/s-x" "x" (Nil))) 0))
           (Nil))))

;; ---- Printing ----

(: event->string (-> Event String))
(define (event->string event)
  (match event
    ((ResidentStarted) "resident started")
    ((ResidentExited message) (string-append "resident exited: " message))
    ((Touched paths) (string-append "touched " (string-join paths " ")))
    ((Uncertain error)
     (match error
       ((Some message) (string-append "uncertain: " message))
       ((None) "uncertain")))
    ((Reconciled result)
     (match result
       ((Ok _) "reconciled")
       ((Err message) (string-append "reconcile failed: " message))))
    ((BuildReplied epoch reply)
     (string-append "built " (show epoch) (match (Reply-candidate reply)
                                            ((Some _) " a candidate")
                                            ((None) " nothing"))))
    ((PublishReplied epoch error)
     (string-append "published " (show epoch) (match error
                                                ((Some message) (string-append ": " message))
                                                ((None) ""))))
    ((DiscardReplied epoch) (string-append "discarded " (show epoch)))
    ((TimerFired) "timer")
    ((RequestBuild) "build requested")
    ((StartRun name) (string-append "start " name))
    ((StopRun name) (string-append "stop " name))
    ((RestartRun name) (string-append "restart " name))
    ((Close) "close")))

(: command->string (-> Command String))
(define (command->string command)
  (match command
    ((Build epoch) (string-append "build " (show epoch)))
    ((Reconcile) "reconcile")
    ((Publish epoch) (string-append "publish " (show epoch)))
    ((Discard epoch) (string-append "discard " (show epoch)))
    ((Abandon epoch) (string-append "abandon " (show epoch)))
    ((Release epoch) (string-append "release " (show epoch)))
    ((Arm) "arm")
    ((Launch name request)
     (match request
       ((Some request)
        (string-append "launch " name " from build " (show (RunRequest-build request)) " at "
                       (RunRequest-entry request)))
       ((None) (string-append "launch " name " nothing"))))
    ((Refuse refusal)
     (match refusal
       ((UnknownRunTarget name) (string-append "refuse unknown " name))
       ((ServiceClosed) "refuse closed")))
    ((Notify snapshot) (snapshot->string snapshot))
    ((Reclaim directories) (string-append "reclaim " (string-join directories " ")))
    ((Shutdown) "shutdown")
    ((Closed) "closed")))

(: snapshot->string (-> Snapshot String))
(define (snapshot->string snapshot)
  (string-append "notify "
                 (phase->string (Snapshot-phase snapshot))
                 " "
                 (show (Snapshot-id snapshot))
                 (string-concatenate (map (lambda (diagnostic)
                                            (string-append " ["
                                                           (Diagnostic-message diagnostic)
                                                           "]"))
                                          (Snapshot-diagnostics snapshot)))
                 (match (Snapshot-publications snapshot)
                   ((Cons published _)
                    (string-append " published " (show (Published-id published))))
                   ((Nil) ""))
                 (string-concatenate (map run->string (Snapshot-runs snapshot)))))

(: run->string (-> RunStatus String))
(define (run->string run)
  (string-append " run "
                 (RunStatus-name run)
                 (if (RunStatus-wanted run) " wanted" "")
                 (if (RunStatus-available run) " available" "")))

(: phase->string (-> Phase String))
(define (phase->string phase)
  (match phase
    ((Starting) "starting")
    ((Building) "building")
    ((Succeeded) "succeeded")
    ((Failed) "failed")
    ((Superseded) "superseded")
    ((Fatal) "fatal")))

;; ---- Driving ----

(: drive (-> Service (List Event) Service ! console))
(define (drive service events)
  (fold-left (lambda (service event)
               (let ((stepped (step service event)))
                 (write-line (string-append "  "
                                            (event->string event)
                                            " -> "
                                            (match (Pair-second stepped)
                                              ((Nil) "nothing")
                                              (commands
                                               (string-join (map command->string commands) "; ")))))
                 (Pair-first stepped)))
             service
             events))

(: scenario (-> String (List Event) Service ! console))
(define (scenario name events)
  (write-line name)
  (drive (new-service root project) events))

;; Starting up, and the first attempt replied to and published.
(define started (list (ResidentStarted) (Reconciled (Ok (unit))) (TimerFired)))

(define first-published
  (append started
          (list (BuildReplied 1 (succeeded "a"))
                (Reconciled (Ok (unit)))
                (PublishReplied 1 (None)))))

;; ---- Scenarios ----

(scenario "edits coalesce into one attempt"
          (append started
                  (list (BuildReplied 1 (succeeded "a"))
                        (Reconciled (Ok (unit)))
                        (PublishReplied 1 (None))
                        (Touched (list "/r/apps/p/main.sld"))
                        (Touched (list "/r/src/snail/core/base.sld"))
                        (TimerFired)
                        (TimerFired))))

(scenario "an input edited while building supersedes the attempt"
          (append started
                  (list (Touched (list "/r/apps/p/lib/util.sld"))
                        (BuildReplied 1 (succeeded "a"))
                        (Reconciled (Ok (unit)))
                        (DiscardReplied 1)
                        (TimerFired))))

(scenario "a file the build does not read does not"
          (append started
                  (list (Touched (list "/r/apps/p/notes.txt"))
                        (BuildReplied 1 (succeeded "a"))
                        (Reconciled (Ok (unit)))
                        (PublishReplied 1 (None)))))

(scenario "a public file is an input once a reply names the directory"
          (list (ResidentStarted)
                (Reconciled (Ok (unit)))
                (Touched (list "/r/apps/p/public/index.html"))
                (TimerFired)
                (Touched (list "/r/apps/p/public/index.html"))
                (BuildReplied 1 (succeeded "a"))
                (Reconciled (Ok (unit)))))

(scenario "a reply for another epoch is fatal"
          (append first-published
                  (list (Touched (list "/r/apps/p/main.sld"))
                        (TimerFired)
                        (BuildReplied 1 failed))))

(scenario "a publication that fails releases the attempt and reports it"
          (append started
                  (list (BuildReplied 1 (succeeded "a"))
                        (Reconciled (Ok (unit)))
                        (PublishReplied 1 (Some "cannot rename build/server")))))

(scenario "a failed build reports its diagnostics and keeps what was published"
          (append first-published
                  (list (Touched (list "/r/apps/p/main.sld"))
                        (TimerFired)
                        (BuildReplied 2 failed)
                        (Reconciled (Ok (unit))))))

(scenario "a disk that cannot be read discards the candidate until it can"
          (append started
                  (list (BuildReplied 1 (succeeded "a"))
                        (Reconciled (Err "cannot reconcile /r/apps/p"))
                        (DiscardReplied 1)
                        (Uncertain (Some "still failing"))
                        (Uncertain (None))
                        (TimerFired))))

(scenario "a disk that cannot be read at start-up waits for it"
          (list (ResidentStarted)
                (RequestBuild)
                (Reconciled (Err "cannot reconcile /r/apps/p"))
                (Uncertain (Some "still failing"))
                (Uncertain (None))
                (TimerFired)))

(scenario "closing with an attempt in flight abandons it, and nothing after"
          (append started
                  (list (Close) (BuildReplied 1 (succeeded "a")) (StartRun "app") (Close))))

(scenario "closing while publishing releases"
          (append started (list (BuildReplied 1 (succeeded "a")) (Reconciled (Ok (unit))) (Close))))

(scenario "the resident's exit is fatal"
          (append started
                  (list (ResidentExited "status 1: snail: out of memory")
                        (ResidentExited "again"))))

(scenario "the resident's exit before the first reconciliation stays what failed"
          (list (ResidentStarted) (ResidentExited "SIGKILL") (Reconciled (Ok (unit))) (TimerFired)))

(scenario "run targets follow what is wanted and what is published"
          (append first-published
                  (list (StartRun "app")
                        (StartRun "app")
                        (Touched (list "/r/apps/p/main.sld"))
                        (TimerFired)
                        (BuildReplied 2 (succeeded "b"))
                        (Reconciled (Ok (unit)))
                        (PublishReplied 2 (None))
                        (Touched (list "/r/apps/p/main.sld"))
                        (TimerFired)
                        (BuildReplied 3 (succeeded "b"))
                        (Reconciled (Ok (unit)))
                        (PublishReplied 3 (None))
                        (RestartRun "app")
                        (StopRun "app")
                        (StartRun "nope")
                        (StartRun "app")
                        (Touched (list "/r/apps/p/project.datum"))
                        (TimerFired)
                        (BuildReplied 4 without-runs)
                        (Reconciled (Ok (unit)))
                        (PublishReplied 4 (None))
                        (StartRun "app")
                        (StopRun "app"))))

(scenario "generations stay while recent or while a run runs from one"
          (concatenate
           (list started
                 (list (BuildReplied 1 (built-in "g1" "a"))
                       (Reconciled (Ok (unit)))
                       (PublishReplied 1 (None))
                       (StartRun "app"))
                 (rebuilt 2 (built-in "g2" "a"))
                 (rebuilt 3 (built-in "g3" "a"))
                 (list (StopRun "app") (StartRun "app"))
                 (rebuilt 4 (built-in "g4" "b"))
                 (rebuilt 5 (built-in "g5" "b")))))
