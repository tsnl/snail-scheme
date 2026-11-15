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

(define (root) (→ String) "/r")

(define (project) (→ String) "/r/apps/p")

(define (description) (→ Description)
  (new Description (entries (list "main.sld"))
       (publics (list "public"))
       (browsers (Nil))
       (runs
        (list (new Run-definition (name "app") (build "server") (arguments (list "--port")))))))

(define (candidate (digest String)) (→ Candidate)
  (new Candidate (description (description))
       (generations (list
                     (new Generation
                       (name "server")
                       (directory (string-append "/r/apps/p/build/s-" digest))
                       (digest digest)
                       (files (Nil))
                       (linked (Nil)))))
       (milliseconds 0)))

(define (succeeded (digest String)) (→ Reply)
  (new Reply
    (description (Some (description)))
    (candidate (Some (candidate digest)))
    (diagnostics (Nil))))

;; A build into generation `name`, whose files have the digest given, as a
;; build of an unchanged program does into a new generation.
(define (built-in (name String) (digest String)) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (Some (new Candidate (description (description))
                             (generations (list (new Generation (name "server")
                                                     (directory
                                                      (string-append "/r/apps/p/build/" name))
                                                     (digest digest)
                                                     (files (Nil))
                                                     (linked (Nil)))))
                             (milliseconds 0))))
       (diagnostics (Nil))))

;; An edit, and the attempt it starts built and published as `epoch`.
(define (rebuilt (epoch I64) (reply Reply)) (→ (List Event))
  (list (Touched (list "/r/apps/p/main.sld"))
        (Timer-fired)
        (Build-replied epoch reply)
        (Reconciled (Ok (unit)))
        (Publish-replied epoch (None))))

(define (failed) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (None))
       (diagnostics (list (new Diagnostic
                            (message "unbound identifier x")
                            (source (Some (new Source-point
                                            (file "/r/apps/p/main.sld")
                                            (line 1)
                                            (column 2)))))))))

;; A publication whose description has no run targets.
(define (without-runs) (→ Reply)
  (let ((bare (new Description
                (entries (list "main.sld"))
                (publics (Nil))
                (browsers (Nil))
                (runs (Nil)))))
    (new Reply (description (Some bare))
         (candidate (Some
                     (new Candidate
                       (description bare)
                       (generations (list (new Generation
                                            (name "server")
                                            (directory "/r/apps/p/build/s-x")
                                            (digest "x")
                                            (files (Nil))
                                            (linked (Nil)))))
                       (milliseconds 0))))
         (diagnostics (Nil)))))

;; A build whose program links the file at `path`.
(define (linking (path String)) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (Some (new Candidate (description (description))
                             (generations (list (new Generation
                                                  (name "server")
                                                  (directory "/r/apps/p/build/s-l")
                                                  (digest "l")
                                                  (files (Nil))
                                                  (linked (list path)))))
                             (milliseconds 0))))
       (diagnostics (Nil))))

;; ---- Printing ----

(define (event->string (event Event)) (→ String)
  (match event
    ((Resident-started) "resident started")
    ((Resident-exited message) (string-append "resident exited: " message))
    ((Touched paths) (string-append "touched " (string-join paths " ")))
    ((Uncertain error)
     (match error
       ((Some message) (string-append "uncertain: " message))
       ((None) "uncertain")))
    ((Reconciled result)
     (match result
       ((Ok _) "reconciled")
       ((Err message) (string-append "reconcile failed: " message))))
    ((Build-replied epoch reply)
     (string-append "built " (show epoch) (match (● reply candidate)
                                            ((Some _) " a candidate")
                                            ((None) " nothing"))))
    ((Publish-replied epoch error)
     (string-append "published " (show epoch) (match error
                                                ((Some message) (string-append ": " message))
                                                ((None) ""))))
    ((Discard-replied epoch) (string-append "discarded " (show epoch)))
    ((Timer-fired) "timer")
    ((Request-build) "build requested")
    ((Start-run name) (string-append "start " name))
    ((Stop-run name) (string-append "stop " name))
    ((Restart-run name) (string-append "restart " name))
    ((Close) "close")))

(define (command->string (command Command)) (→ String)
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
        (string-append "launch " name " from build " (show (● request build)) " at "
                       (● request entry)))
       ((None) (string-append "launch " name " nothing"))))
    ((Refuse refusal)
     (match refusal
       ((Unknown-run-target name) (string-append "refuse unknown " name))
       ((Service-closed) "refuse closed")))
    ((Notify snapshot) (snapshot->string snapshot))
    ((Reclaim directories) (string-append "reclaim " (string-join directories " ")))
    ((Shutdown) "shutdown")
    ((Closed) "closed")))

(define (snapshot->string (snapshot Snapshot)) (→ String)
  (string-append "notify "
                 (phase->string (● snapshot phase))
                 " "
                 (show (● snapshot id))
                 (string-concatenate (map (lambda (diagnostic)
                                            (string-append " ["
                                                           (● diagnostic message)
                                                           "]"))
                                          (● snapshot diagnostics)))
                 (match (● snapshot publications)
                   ((Cons published _)
                    (string-append " published " (show (● published id))))
                   ((Nil) ""))
                 (string-concatenate (map run->string (● snapshot runs)))))

(define (run->string (run Run-status)) (→ String)
  (string-append " run "
                 (● run name)
                 (if (● run wanted) " wanted" "")
                 (if (● run available) " available" "")))

(define (phase->string (phase Phase)) (→ String)
  (match phase
    ((Starting) "starting")
    ((Building) "building")
    ((Succeeded) "succeeded")
    ((Failed) "failed")
    ((Superseded) "superseded")
    ((Fatal) "fatal")))

;; ---- Driving ----

(define (drive (service Service) (events (List Event))) (→ Service) (! Output-port)
  (fold-left (lambda (service event)
               (let ((stepped (step service event)))
                 (write-line (string-append "  "
                                            (event->string event)
                                            " -> "
                                            (match (● stepped second)
                                              ((Nil) "nothing")
                                              (commands
                                               (string-join (map command->string commands) "; ")))))
                 (● stepped first)))
             service
             events))

(define (scenario (name String) (events (List Event))) (→ Service) (! Output-port)
  (write-line name)
  (drive (new-service (root) (project)) events))

;; Starting up, and the first attempt replied to and published.
(define (started) (→ (List Event)) (list (Resident-started) (Reconciled (Ok (unit))) (Timer-fired)))

(define (first-published) (→ (List Event))
  (append (started)
          (list (Build-replied 1 (succeeded "a"))
                (Reconciled (Ok (unit)))
                (Publish-replied 1 (None)))))

(define (main) (→ Unit) (! Output-port)
  ;; ---- Scenarios ----

  (scenario "edits coalesce into one attempt"
            (append (started)
                    (list (Build-replied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 1 (None))
                          (Touched (list "/r/apps/p/main.sld"))
                          (Touched (list "/r/src/snail/core/base.sld"))
                          (Timer-fired)
                          (Timer-fired))))
  (scenario "an input edited while building supersedes the attempt"
            (append (started)
                    (list (Touched (list "/r/apps/p/lib/util.sld"))
                          (Build-replied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (Discard-replied 1)
                          (Timer-fired))))
  (scenario "a file the build does not read does not"
            (append (started)
                    (list (Touched (list "/r/apps/p/notes.txt"))
                          (Build-replied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 1 (None)))))
  (scenario "a public file is an input once a reply names the directory"
            (list (Resident-started)
                  (Reconciled (Ok (unit)))
                  (Touched (list "/r/apps/p/public/index.html"))
                  (Timer-fired)
                  (Touched (list "/r/apps/p/public/index.html"))
                  (Build-replied 1 (succeeded "a"))
                  (Reconciled (Ok (unit)))))
  (scenario "a linked file is an input once a published program links it"
            (append (started)
                    (list (Touched (list "/r/apps/p/art.bin"))
                          (Build-replied 1 (linking "/r/apps/p/art.bin"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 1 (None))
                          (Touched (list "/r/apps/p/art.bin"))
                          (Timer-fired))))
  (scenario "a reply for another epoch is fatal"
            (append (first-published)
                    (list (Touched (list "/r/apps/p/main.sld"))
                          (Timer-fired)
                          (Build-replied 1 (failed)))))
  (scenario "a publication that fails releases the attempt and reports it"
            (append (started)
                    (list (Build-replied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 1 (Some "cannot rename build/server")))))
  (scenario "a failed build reports its diagnostics and keeps what was published"
            (append (first-published)
                    (list (Touched (list "/r/apps/p/main.sld"))
                          (Timer-fired)
                          (Build-replied 2 (failed))
                          (Reconciled (Ok (unit))))))
  (scenario "a disk that cannot be read discards the candidate until it can"
            (append (started)
                    (list (Build-replied 1 (succeeded "a"))
                          (Reconciled (Err "cannot reconcile /r/apps/p"))
                          (Discard-replied 1)
                          (Uncertain (Some "still failing"))
                          (Uncertain (None))
                          (Timer-fired))))
  (scenario "a disk that cannot be read at start-up waits for it"
            (list (Resident-started)
                  (Request-build)
                  (Reconciled (Err "cannot reconcile /r/apps/p"))
                  (Uncertain (Some "still failing"))
                  (Uncertain (None))
                  (Timer-fired)))
  (scenario "closing with an attempt in flight abandons it, and nothing after"
            (append (started)
                    (list (Close) (Build-replied 1 (succeeded "a")) (Start-run "app") (Close))))
  (scenario "closing while publishing releases"
            (append (started)
                    (list (Build-replied 1 (succeeded "a")) (Reconciled (Ok (unit))) (Close))))
  (scenario "the resident's exit is fatal"
            (append (started)
                    (list (Resident-exited "status 1: snail: out of memory")
                          (Resident-exited "again"))))
  (scenario "the resident's exit before the first reconciliation stays what failed"
            (list (Resident-started)
                  (Resident-exited "SIGKILL")
                  (Reconciled (Ok (unit)))
                  (Timer-fired)))
  (scenario "run targets follow what is wanted and what is published"
            (append (first-published)
                    (list (Start-run "app")
                          (Start-run "app")
                          (Touched (list "/r/apps/p/main.sld"))
                          (Timer-fired)
                          (Build-replied 2 (succeeded "b"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 2 (None))
                          (Touched (list "/r/apps/p/main.sld"))
                          (Timer-fired)
                          (Build-replied 3 (succeeded "b"))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 3 (None))
                          (Restart-run "app")
                          (Stop-run "app")
                          (Start-run "nope")
                          (Start-run "app")
                          (Touched (list "/r/apps/p/project.datum"))
                          (Timer-fired)
                          (Build-replied 4 (without-runs))
                          (Reconciled (Ok (unit)))
                          (Publish-replied 4 (None))
                          (Start-run "app")
                          (Stop-run "app"))))
  (scenario "generations stay while recent or while a run runs from one"
            (concatenate
             (list (started)
                   (list (Build-replied 1 (built-in "g1" "a"))
                         (Reconciled (Ok (unit)))
                         (Publish-replied 1 (None))
                         (Start-run "app"))
                   (rebuilt 2 (built-in "g2" "a"))
                   (rebuilt 3 (built-in "g3" "a"))
                   (list (Stop-run "app") (Start-run "app"))
                   (rebuilt 4 (built-in "g4" "b"))
                   (rebuilt 5 (built-in "g5" "b")))))
  (unit))
