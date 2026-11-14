;; `snail dev`'s service in Snail Scheme: one project's editor, builds and run
;; targets behind one local port. (snail shell development)'s pure `step`
;; decides; this library carries out what it decides, with tasks that each
;; wait on one thing:
;;
;; - the owner, which holds the service and everything the step leaves to
;;   its host, and receives every message;
;; - the disk task, which holds the latest inventory of the project's
;;   inputs, takes another when asked, hinted or each second, and reports
;;   what changed;
;; - the resident builder, `snail resident PROJECT`, in a child process,
;;   with a task writing its requests, one reading its replies and one its
;;   standard error and exit;
;; - a supervisor for each run target, which owns that target's process;
;; - a task for each HTTP connection, which serves the editor's API, and
;;   for an event stream, writes what the owner sends it; and one for each
;;   connection to the applications' origin, which serves each browser
;;   target's builds ((snail shell project bundle)).
;;
;; No cell holds state: each task threads its own through its loop. It is
;; #567 steps B3 to B5, which replaced a service in JavaScript.
(define-library (snail shell project service)
  (export
   Setup
   develop)
  (import
   (snail shell project web-app)
   (snail core base)
   (only (snail core forms) host)
   (except (snail core io) write)
   (snail shell task)
   (snail shell socket)
   (rename (snail shell process)
           (Command ProcessCommand))
   (snail shell http)
   (snail shell http exchange)
   (snail shell json)
   (snail shell json read)
   (only (snail shell text) string-downcase)
   (snail shell utf8)
   (snail shell watch)
   (snail shell development)
   (snail shell project bundle)
   (snail shell project files)
   (prefix (snail shell gitignore) ignore-)
   (prefix (snail shell project protocol) protocol-)
   (prefix (snail shell project search) search-))
  (begin

    ;; ---- Setup ----

    ;; What the service runs with: the repository's root; the command
    ;; line's program and the runtime it links programs with, which the
    ;; resident runs as; Node, which runs them; the editor's published bundle; the
    ;; reload client's program, which browser targets' pages load; the
    ;; project, absolute; and the port to listen on, 0 for any.
    (record Setup
      ((root String)
       (cli String)
       (runtime String)
       (node String)
       (editor String)
       (client String)
       (project String)
       (port I32)))

    (define (runner (setup Setup)) (→ String)
      (string-append (● setup root) "/host/native/run-snail.mjs"))

    ;; ---- Messages ----

    ;; What the owner receives. `Step` is an event for the pure step;
    ;; `Ask` one an HTTP handler waits on, answered on its reply mailbox;
    ;; the rest are the host's own: the debounce timer, the resident, run
    ;; supervisors and event streams.
    (enum Message
      (Step ((event Event)))
      (Ask
       ((event Event)
        (reply (Mailbox Answer))))
      (Status ((reply (Mailbox Answer))))
      (EditorAssets ((reply (Mailbox (List EditorBundle)))))
      (EditorBuilt ((result (Result EditorBundle String))))
      (Applications ((reply (Mailbox (List Application)))))
      (Fired ((serial I64)))
      (Built
       ((epoch I64)
        (reply Reply)
        (targets Json)))
      (ResidentGone ((message String)))
      (Overdue)
      (RunChanged
       ((name String)
        (status protocol-Run)))
      (RunStopped)
      (Joined
       ((id I64)
        (watching (Option String))
        (connection Connection)
        (frames (Mailbox (Option Bytes)))
        (reply (Mailbox Answer))))
      (Written
       ((id I64)
        (count I64)))
      (Connected
       ((id I64)
        (connection Connection)))
      (Disconnected ((id I64))))

    ;; The owner's answer to a handler, as the response it sends.
    (record Answer
      ((status I32)
       (body Json)))

    ;; What the disk task is asked: to reconcile for the step, to scan
    ;; because something may have changed, as after a save or a hint,
    ;; whether to go on, for the 1 s timer, for the regular files it found,
    ;; or to stop.
    (enum Scan
      (Reconciling)
      (Prompted)
      (Ticked ((reply (Mailbox Bool))))
      (Listing ((reply (Mailbox (Result Inventory String)))))
      (Stopping))

    ;; What a run target's supervisor is asked: to run a request, or none;
    ;; or to finish, once its process has ended. The rest come from its
    ;; process, by the serial of the request it runs.
    (enum Supervision
      (Want ((request (Option RunRequest))))
      (Output
       ((serial I64)
        (stream Stream)
        (bytes Bytes)))
      (Ended
       ((serial I64)
        (exit (Result Exit ProcessError))))
      (Late ((serial I64)))
      (Finish))

    ;; ---- The owner's state ----

    ;; A browser target as the applications' origin serves it: its name and
    ;; the builds of it retained, newest first.
    (record Application
      ((name String)
       (builds (List BuildDirectory))))

    ;; An event stream, by its connection's number: the browser target a
    ;; page's stream hears of builds of, or none for an editor's; and how
    ;; many bytes the owner sent it that its writer has not written yet.
    (record Client
      ((id I64)
       (watching (Option String))
       (connection Connection)
       (frames (Mailbox (Option Bytes)))
       (pending I64)))

    (record Supervised
      ((name String)
       (inbox (Mailbox Supervision))
       (status protocol-Run)))

    ;; Everything the step leaves to its host. `targets` is the latest
    ;; reply's candidate, by epoch, and `published` the targets of the one
    ;; published, as the status shows them. `frames` is the last complete
    ;; editor snapshot sent. The owner holds its instance and file counter.
    ;; `connections` are the ones whose handlers have not finished, by
    ;; number, and `clients` those of them that are event streams; `told`
    ;; is the event last sent to each browser target's pages.
    ;; `stopping` holds the commands after Shutdown, run once `waiting`, the
    ;; resident, the supervisors and the handlers still running, reaches
    ;; zero.
    (record Host
      ((setup Setup)
       (owner (Mailbox Message))
       (disk (Mailbox Scan))
       (requests (Mailbox (Option String)))
       (resident Process)
       (resident-alive Bool)
       (listener Listener)
       (applications Listener)
       (service Service)
       (snapshot Snapshot)
       (serial I64)
       (reservation (Option (Pair I64 String)))
       (targets (Option (Pair I64 Json)))
       (published Json)
       (runs (List Supervised))
       (clients (List Client))
       (told (List (Pair String String)))
       (connections (List (Pair I64 Connection)))
       (frames String)
       (instance String)
       (files I64)
       (editors (List EditorBundle))
       (editor-process (Option Process))
       (editor-again Bool)
       (editor-problem String)
       (stopping (Option (List Command)))
       (waiting I64)
       (done Bool)))

    ;; ---- Starting ----

    ;; Dispatches the task that starts the service; the scheduler runs it
    ;; once the program's main returns. The service ends when the owner has
    ;; shut everything down, and fails the program if the step went fatal.

    (define (develop (setup Setup))
      (→ Unit)
      (! mut tcp process fs modes hints output-port signals clock host tasks)
      (dispatch-local (lambda () (start setup))))

    ;; Listens, starts the resident, announces the editor's URL and the
    ;; applications', and dispatches every other task.

    (define (start (setup Setup))
      (→ Unit)
      (! mut tasks tcp process fs modes hints output-port signals clock host)
      (let* ((listener (listening setup))
             (applications (applications-listening (● setup port)))
             (setup (Setup-port-set setup (● listener port)))
             (resident (resident-process setup))
             (owner (make-mailbox))
             (disk (make-mailbox))
             (requests (make-mailbox)))
        (dispatch-local (lambda () (scan-disk setup owner disk)))
        (dispatch-local (lambda () (tick disk)))
        (dispatch-local (lambda () (write-requests resident requests)))
        (dispatch-local (lambda () (read-replies resident owner (Nil))))
        (dispatch-local (lambda () (await-resident resident owner (Nil))))
        (dispatch-local (lambda () (accept-connections setup listener owner disk)))
        (dispatch-local (lambda () (accept-applications setup applications owner)))
        (dispatch-local (lambda () (mailbox-post owner (Step (wait-for-signal)))))
        (mailbox-post owner (Step (ResidentStarted)))
        (write-line (string-append "editing " (● setup project) " at " (origin setup) "/"))
        (write-line (string-append "serving its browser targets at "
                                   (listener-origin applications)
                                   "/NAME/"))
        (own (new-host setup owner disk requests resident listener applications))))

    (define (wait-for-signal) (→ Event) (! tasks signals)
      (termination)
      (Close))

    (define (listening (setup Setup)) (→ Listener) (! tasks tcp)
      (match (listen-locally (● setup port))
        ((Ok listener) listener)
        ((Err error)
         (panic (string-append "cannot listen on port "
                               (show (● setup port))
                               ": "
                               (● error code))))))

    (define (origin (setup Setup)) (→ String)
      (string-append "http://127.0.0.1:" (show (● setup port))))

    ;; The applications' origin is apart from the editor's, so no page of
    ;; the project can reach the editor's API. It takes the port after the
    ;; editor's when the editor's was asked for, or any port when that one
    ;; is taken or none was.

    (define (applications-listening (port I32)) (→ Listener) (! tasks tcp)
      (match (if (= port 0)
                 (Err (new SocketError (code "unasked")))
                 (listen-locally (+ port 1)))
        ((Ok listener) listener)
        ((Err _)
         (match (listen-locally 0)
           ((Ok listener) listener)
           ((Err error)
            (panic (string-append "cannot listen for the applications: "
                                  (● error code))))))))

    ;; The service listens on the loopback address alone.

    (define (listen-locally (port I32)) (→ (Result Listener SocketError)) (! tasks tcp)
      (match (endpoint "127.0.0.1" port)
        ((Ok local) (listen local))
        ((Err error) (Err error))))

    (define (listener-host (listener Listener)) (→ String)
      (string-append "127.0.0.1:" (show (● listener port))))

    (define (listener-origin (listener Listener)) (→ String)
      (string-append "http://" (listener-host listener)))

    (define (new-host (setup Setup)
                      (owner (Mailbox Message))
                      (disk (Mailbox Scan))
                      (requests (Mailbox (Option String)))
                      (resident Process)
                      (listener Listener)
                      (applications Listener))
      (→ Host)
      (! clock fs)
      (new Host (setup setup)
           (owner owner)
           (disk disk)
           (requests requests)
           (resident resident)
           (resident-alive #t)
           (listener listener)
           (applications applications)
           (service (new-service (● setup root) (● setup project)))
           (snapshot (new Snapshot
                       (phase (Starting))
                       (id 0)
                       (diagnostics (Nil))
                       (publications (Nil))
                       (runs (Nil))))
           (serial 0)
           (reservation (None))
           (targets (None))
           (published (JsonNull))
           (runs (Nil))
           (clients (Nil))
           (told (Nil))
           (connections (Nil))
           (frames "")
           (instance (string-append (show (● resident id)) ":" (show (monotonic-nanoseconds))))
           (files 0)
           (editors (list (match (editor-bundle setup)
                            ((Ok bundle) bundle) ((Err message) (panic message)))))
           (editor-process (None))
           (editor-again #f)
           (editor-problem "")
           (stopping (None))
           (waiting 0)
           (done #f)))

    ;; ---- The owner ----

    (define (own (host Host)) (→ Unit) (! mut tasks tcp process fs host)
      (let ((host (receive host (mailbox-receive (● host owner)))))
        (if (● host done) (finish host) (own host))))

    ;; A fatal service fails the program, with the diagnostic that ended it.

    (define (finish (host Host)) (→ Unit)
      (match (● (● host snapshot) phase)
        ((Fatal) (panic (first-message (● host snapshot))))
        (_ (unit))))

    (define (first-message (snapshot Snapshot)) (→ String)
      (match (● snapshot diagnostics)
        ((Cons diagnostic _) (● diagnostic message))
        ((Nil) "the service failed")))

    (define (receive (host Host) (message Message)) (→ Host) (! mut tasks tcp process fs host)
      (match message
        ((Step event) (stepped (touched-editor (touched-files host event) event) event))
        ((Ask event reply) (asked host event reply))
        ((Status reply)
         (mailbox-post reply (new Answer (status 200) (body (status->json host))))
         host)
        ((EditorAssets reply) (mailbox-post reply (● host editors)) host)
        ((EditorBuilt result) (editor-built host result))
        ((Applications reply) (mailbox-post reply (served-applications host)) host)
        ((Fired serial) (if (= serial (● host serial)) (stepped host (TimerFired)) host))
        ((Built epoch reply targets)
         (stepped (Host-targets-set host (Some (new Pair (first epoch) (second targets))))
                  (BuildReplied epoch reply)))
        ((ResidentGone message) (resident-gone host message))
        ((Overdue) (overdue host))
        ((RunChanged name status) (broadcast-changes (run-changed host name status)))
        ((RunStopped) (stopped-one host))
        ((Joined id watching connection frames reply)
         (joined host id watching connection frames reply))
        ((Written id count) (written host id count))
        ((Connected id connection) (connected host id connection))
        ((Disconnected id) (disconnected host id))))

    (define (stepped (host Host) (event Event)) (→ Host) (! mut tasks tcp process fs host)
      (let ((result (step (● host service) event)))
        (perform-all (Host-service-set host (● result first)) (● result second))))

    ;; A handler's event, answered once its commands ran: the step's
    ;; refusal, or what the request asked for.

    (define (asked (host Host) (event Event) (reply (Mailbox Answer)))
      (→ Host)
      (! mut tasks tcp process fs host)
      (let* ((result (step (● host service) event))
             (host
              (perform-all (Host-service-set host (● result first)) (● result second))))
        (mailbox-post reply (answer-for host event (refusal-of (● result second))))
        host))

    (define (refusal-of (commands (List Command))) (→ (Option Refusal))
      (match commands
        ((Nil) (None))
        ((Cons (Refuse refusal) _) (Some refusal))
        ((Cons _ rest) (refusal-of rest))))

    (define (answer-for (host Host) (event Event) (refusal (Option Refusal))) (→ Answer)
      (match refusal
        ((Some (UnknownRunTarget name))
         (new Answer
           (status 404)
           (body (protocol-message->json (string-append "unknown accepted run target: " name)))))
        ((Some (ServiceClosed))
         (new Answer (status 503) (body (protocol-message->json "project development is closing"))))
        ((None)
         (match event
           ((RequestBuild)
            (new Answer
              (status 202)
              (body (protocol-build->json (editor-status (● host snapshot))))))
           (_ (new Answer (status 204) (body (JsonNull))))))))

    ;; ---- Carrying out commands ----

    ;; Each command in order. The commands after Shutdown wait until the
    ;; resident and every run's process have stopped.

    (define (perform-all (host Host) (commands (List Command)))
      (→ Host)
      (! mut tasks tcp process fs host)
      (match commands
        ((Nil) host)
        ((Cons (Shutdown) rest) (shut-down host rest))
        ((Cons command rest) (perform-all (perform host command) rest))))

    (define (perform (host Host) (command Command)) (→ Host) (! mut tcp process fs host tasks)
      (match command
        ((Build epoch) (build host epoch))
        ((Reconcile) (mailbox-post (● host disk) (Reconciling)) host)
        ((Publish epoch) (request host (epoch-request "publish" epoch (Nil))))
        ((Discard epoch) (request host (epoch-request "discard" epoch (Nil))))
        ((Abandon epoch) (give-up host epoch #t))
        ((Release epoch) (give-up host epoch #f))
        ((Arm) (arm host))
        ((Launch name wanted) (launch host name wanted))
        ((Refuse _) host)
        ((Notify snapshot) (notify host snapshot))
        ((Reclaim directories)
         (for-each (lambda (directory)
                     (remove-tree directory)
                     (unit))
                   directories)
         host)
        ((Shutdown) host)
        ((Closed) (Host-done-set host #t))))

    (define (request (host Host) (line String)) (→ Host) (! mut)
      (mailbox-post (● host requests) (Some line))
      host)

    (define (epoch-request (kind String) (epoch I64) (rest (List (Pair String Json)))) (→ String)
      (json->string (JsonObject (append (list (new Pair (first "kind") (second (JsonString kind)))
                                              (new Pair
                                                (first "epoch")
                                                (second (JsonInteger epoch))))
                                        rest))))

    ;; An attempt's build directory, reserved under build/ before the
    ;; resident makes generations beside it, named for it.

    (define (build (host Host) (epoch I64)) (→ Host) (! mut fs)
      (match (reserve (string-append (● (● host setup) project) "/build") 0)
        ((Ok directory)
         (request (Host-reservation-set host (Some (new Pair (first epoch) (second directory))))
                  (epoch-request "build"
                                 epoch
                                 (list (new Pair (first "prefix")
                                            (second (JsonString
                                                     (string-append (base-name directory)
                                                                    "-"))))))))
        ((Err message)
         (mailbox-post (● host owner) (Step (ResidentExited message)))
         host)))

    ;; A name no entry of build/ has, nor begins, so the generations the
    ;; resident names with it are this attempt's alone, even beside what an
    ;; earlier service left there.

    (define (reserve (build String) (number I64)) (→ (Result String String)) (! fs)
      (match (make-directories build)
        ((Err error) (Err (string-append "cannot make " build ": " (show error))))
        ((Ok _)
         (match (list-directory build)
           ((Err error) (Err (string-append "cannot list " build ": " (show error))))
           ((Ok names) (reserve-unused build names number))))))

    (define (reserve-unused (build String) (names (List String)) (number I64))
      (→ (Result String String))
      (! fs)
      (let* ((name (string-append ".snail-attempt-" (show number)))
             (taken? (any? (lambda (entry)
                             (or (string=? entry name)
                                 (starts-with? entry (string-append name "-"))))
                           names)))
        (if taken?
            (reserve-unused build names (+ number 1))
            (match (make-directory (string-append build "/" name))
              ((Ok _) (Ok (string-append build "/" name)))
              ((Err (AlreadyExists)) (reserve-unused build names (+ number 1)))
              ((Err error) (Err (string-append "cannot reserve " name ": " (show error))))))))

    (define (base-name (path String)) (→ String)
      (let loop ((index (string-length path)))
        (cond ((= index 0) path)
              ((char=? (string-ref path (- index 1)) #\/)
               (substring path index (string-length path)))
              (else (loop (- index 1))))))

    ;; Gives up an attempt's directory, and when the attempt still owns
    ;; them, the generations the resident named for it.

    (define (give-up (host Host) (epoch I64) (generations? Bool)) (→ Host) (! fs)
      (match (● host reservation)
        ((Some (Pair reserved directory))
         (if (= reserved epoch)
             (begin
               (when generations? (remove-generations directory))
               (remove-tree directory)
               (Host-reservation-set host (None)))
             host))
        ((None) host)))

    (define (remove-generations (directory String)) (→ Unit) (! fs)
      (let ((build (substring directory 0 (- (string-length directory)
                                             (+ (string-length (base-name directory)) 1))))
            (prefix (string-append (base-name directory) "-")))
        (match (list-directory build)
          ((Ok names)
           (for-each (lambda (name)
                       (when (starts-with? name prefix)
                         (remove-tree (string-append build "/" name))
                         (unit)))
                     names))
          ((Err _) (unit)))))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Arming replaces the timer armed before: the owner ignores a firing
    ;; whose serial is not the latest.

    (define (arm (host Host)) (→ Host) (! mut host tasks)
      (let ((serial (+ (● host serial) 1)) (owner (● host owner)))
        (dispatch-local (lambda ()
                          (sleep 40)
                          (mailbox-post owner (Fired serial))))
        (Host-serial-set host serial)))

    ;; ---- Run targets ----

    ;; A launch goes to the target's supervisor, started the first time
    ;; the target is launched.

    (define (launch (host Host) (name String) (wanted (Option RunRequest)))
      (→ Host)
      (! mut process host tasks)
      (match (find (lambda (run) (string=? (● run name) name)) (● host runs))
        ((Some run) (mailbox-post (● run inbox) (Want wanted)) host)
        ((None)
         (let ((inbox (make-mailbox)) (setup (● host setup)) (owner (● host owner)))
           (dispatch-local (lambda () (supervise (new-supervisor setup owner inbox name))))
           (mailbox-post inbox (Want wanted))
           (Host-runs-set host
                          (append (● host runs)
                                  (list (new Supervised
                                          (name name)
                                          (inbox inbox)
                                          (status (idle-run name))))))))))

    (define (run-changed (host Host) (name String) (status protocol-Run)) (→ Host)
      (Host-runs-set host
                     (map (lambda (run)
                            (if (string=? (● run name) name)
                                (Supervised-status-set run status)
                                run))
                          (● host runs))))

    ;; ---- Status ----

    ;; A snapshot to every event stream, as the frames that changed. A
    ;; fatal one closes the service.

    (define (notify (host Host) (snapshot Snapshot)) (→ Host) (! mut tcp fs host)
      (let ((host (told-pages
                   (broadcast-changes (Host-snapshot-set (published host snapshot) snapshot)))))
        (match (● snapshot phase)
          ((Fatal) (mailbox-post (● host owner) (Step (Close))) host)
          (_ host))))

    ;; The published targets, once the snapshot names the build whose
    ;; candidate the owner kept; a browser target's has the URL it is
    ;; served at.

    (define (published (host Host) (snapshot Snapshot)) (→ Host)
      (match (new Pair (first (● snapshot publications)) (second (● host targets)))
        ((Pair (Cons build _) (Some (Pair epoch targets)))
         (if (= (● build id) epoch)
             (Host-published-set host
                                 (JsonObject
                                  (list (new Pair (first "id") (second (JsonInteger epoch)))
                                        (new Pair (first "targets")
                                             (second (with-urls host build targets))))))
             host))
        (_ host)))

    (define (with-urls (host Host) (build Published) (targets Json)) (→ Json)
      (let ((browsers (● (● (● build candidate) description) browsers)))
        (match targets
          ((JsonArray items)
           (JsonArray (map (lambda (target) (with-url host browsers target)) items)))
          (other other))))

    (define (with-url (host Host) (browsers (List String)) (target Json)) (→ Json)
      (let ((name (json-text target "name")))
        (match target
          ((JsonObject members)
           (if (member? name browsers)
               (JsonObject
                (append members
                        (list (new Pair
                                (first "url")
                                (second (JsonString (application-url host name)))))))
               target))
          (other other))))

    (define (application-url (host Host) (name String)) (→ String)
      (string-append (listener-origin (● host applications)) "/" name "/"))

    ;; The browser targets of the publication, each with its builds the
    ;; service retains, newest first. A target the latest description no
    ;; longer has is not served.

    (define (served-applications (host Host)) (→ (List Application))
      (let ((publications (● (● host snapshot) publications)))
        (match publications
          ((Cons latest _)
           (map (lambda (name) (new Application (name name) (builds (builds-of publications name))))
                (● (● (● latest candidate) description) browsers)))
          ((Nil) (Nil)))))

    (define (builds-of (publications (List Published)) (name String)) (→ (List BuildDirectory))
      (concatenate (map (lambda (published)
                          (map (lambda (generation)
                                 (new BuildDirectory (epoch (● published id))
                                      (directory (● generation directory))
                                      (files (● generation files))
                                      (milliseconds (● (● published candidate) milliseconds))))
                               (filter
                                (lambda (generation) (string=? (● generation name) name))
                                (● (● published candidate) generations))))
                        publications)))

    (define (editor-status (snapshot Snapshot)) (→ protocol-Build)
      (new protocol-Build (phase (phase-name (● snapshot phase))) (id (● snapshot id))
           (diagnostics (map diagnostic-report (● snapshot diagnostics)))))

    (define (editor-state (host Host)) (→ protocol-ServerState)
      (new protocol-ServerState (instance (● host instance)) (files (● host files))
           (build (editor-status (● host snapshot))) (runs (run-states host))
           (editor (editor-base (list-ref (● host editors) 0)))
           (editor-problem (● host editor-problem))))

    ;; All a client can observe in one snapshot: the attempt, the published
    ;; targets, the resident's process and the run targets.

    (define (status->json (host Host)) (→ Json)
      (match (protocol-build->json (editor-status (● host snapshot)))
        ((JsonObject members)
         (JsonObject (append members
                             (list (new Pair (first "published") (second (● host published)))
                                   (new Pair (first "compiler")
                                        (second (if (● host resident-alive)
                                                    (JsonObject (list (new Pair (first "worker")
                                                                           (second (JsonInteger
                                                                                    (i32->i64
                                                                                     (● (● host
                                                                                           resident)
                                                                                        id)))))))
                                                    (JsonNull))))
                                   (new Pair (first "runs") (second (runs->json host)))))))
        (other other)))

    (define (phase-name (phase Phase)) (→ String)
      (match phase
        ((Starting) "starting")
        ((Building) "building")
        ((Succeeded) "succeeded")
        ((Failed) "failed")
        ((Superseded) "superseded")
        ((Fatal) "fatal")))

    (define (diagnostic-report (diagnostic Diagnostic)) (→ protocol-Report)
      (new protocol-Report (severity "error") (message (● diagnostic message))
           (source (match (● diagnostic source)
                     ((Some point) (Some (new protocol-Point (file (● point file))
                                              (line (● point line))
                                              (column (● point column)))))
                     ((None) (None))))))

    (define (runs->json (host Host)) (→ Json)
      (JsonArray (map protocol-run->json (run-states host))))

    ;; One typed snapshot combines the step's intention and each supervisor's
    ;; latest observation. Neither task constructs fragments of wire JSON.

    (define (run-states (host Host)) (→ (List protocol-Run))
      (map (lambda (run)
             (protocol-Run-available-set
              (protocol-Run-wanted-set (run-status host (● run name))
                                       (● run wanted))
              (● run available)))
           (● (● host snapshot) runs)))

    (define (run-status (host Host) (name String)) (→ protocol-Run)
      (match (find (lambda (run) (string=? (● run name) name)) (● host runs))
        ((Some run) (● run status))
        ((None) (idle-run name))))

    (define (idle-run (name String)) (→ protocol-Run)
      (new protocol-Run (target name) (desired (None)) (attempt (None)) (wanted #f) (available #f)))

    ;; ---- Event streams ----

    ;; A complete snapshot replaces the separate build, process and file
    ;; events. Suppress duplicates; a new connection always gets current state.

    (define (broadcast-changes (host Host)) (→ Host) (! mut tcp host)
      (let ((text (protocol-state->event (editor-state host))))
        (if (string=? text (● host frames)) host
            (broadcast (Host-frames-set host text) text))))

    ;; A change under the project tells each editor to list its files again.

    (define (touched-files (host Host) (event Event)) (→ Host) (! mut tcp host)
      (match event
        ((Touched paths)
         (let ((project (● (● host setup) project)))
           (if (any? (lambda (path) (or (string=? path project)
                                        (starts-with? path (string-append project "/"))))
                     paths)
               (broadcast-changes (Host-files-set host (+ (● host files) 1)))
               host)))
        (_ host)))

    ;; Each client gets the frame, unless 16 KiB it was sent before are
    ;; still unwritten, as Node's stream refuses more: then it is dropped,
    ;; and reconnecting gets it the current status.

    (define (broadcast (host Host) (text String)) (→ Host) (! mut tcp host)
      (Host-clients-set host
                        (sent-to (● host clients)
                                 (lambda (client) (not (option-some? (● client watching))))
                                 (string->utf8 text))))

    ;; Each client `chosen` picks gets the frame; the rest are left as they
    ;; are.

    (define (sent-to (clients (List Client)) (chosen (Fn Client → Bool ! mut)) (bytes Bytes))
      (→ (List Client))
      (! mut tcp host)
      (match clients
        ((Nil) (Nil))
        ((Cons client rest)
         (cond ((not (chosen client)) (Cons client (sent-to rest chosen bytes)))
               ((>= (● client pending) 16384)
                (close-connection (● client connection))
                (mailbox-post (● client frames) (None))
                (sent-to rest chosen bytes))
               (else
                (mailbox-post (● client frames) (Some bytes))
                (Cons (Client-pending-set client (+ (● client pending) (vector-length bytes)))
                      (sent-to rest chosen bytes)))))))

    ;; A new event stream gets the status, the runs and a prompt to list
    ;; files, unless there are 64 already or the service is closing.

    (define (joined (host Host)
                    (id I64)
                    (watching (Option String))
                    (connection Connection)
                    (frames (Mailbox (Option Bytes)))
                    (reply (Mailbox Answer)))
      (→ Host)
      (! mut tcp fs host)
      (cond ((option-some? (● host stopping))
             (mailbox-post reply
                           (new Answer
                             (status 503)
                             (body (protocol-message->json "project development is closing"))))
             host)
            ((>= (length (● host clients)) 64)
             (mailbox-post reply
                           (new Answer
                             (status 429)
                             (body (protocol-message->json "too many event connections"))))
             host)
            (else
             (mailbox-post reply (new Answer (status 200) (body (JsonNull))))
             (Host-clients-set host
                               (append (sent-to (list (new Client
                                                        (id id)
                                                        (watching watching)
                                                        (connection connection)
                                                        (frames frames)
                                                        (pending 0)))
                                                (lambda (client) #t)
                                                (string->utf8 (match watching
                                                                ((Some name)
                                                                 (page-first-frames host name))
                                                                ((None) (first-frames host)))))
                                       (● host clients))))))

    ;; ---- Pages' event streams ----

    ;; What a browser target's pages hear of the latest attempt, with the
    ;; target's latest build: the reload client relinks a page when one is
    ;; published, and shows when one is under way or why one failed.

    (define (page-event (snapshot Snapshot) (application Application)) (→ String) (! fs)
      (bundle-event (string-append "/" (● application name) "/")
                    (match (● snapshot phase)
                      ((Succeeded) (BuildPublished))
                      ((Failed) (BuildFailed (diagnostic-text snapshot)))
                      ((Fatal) (BuildFailed (diagnostic-text snapshot)))
                      (_ (BuildUnderway)))
                    (match (● application builds)
                      ((Cons latest _) (Some latest))
                      ((Nil) (None)))))

    ;; Each diagnostic as a compiler prints it, after its place when it has
    ;; one.

    (define (diagnostic-text (snapshot Snapshot)) (→ String)
      (string-join (map (lambda (diagnostic)
                          (match (● diagnostic source)
                            ((Some point)
                             (string-append (● point file)
                                            ":"
                                            (show (● point line))
                                            ":"
                                            (show (● point column))
                                            ": "
                                            (● diagnostic message)))
                            ((None) (● diagnostic message))))
                        (● snapshot diagnostics))
                   "\n\n"))

    ;; An event as the browser's EventSource reads it. It is one line, as
    ;; the strings in it are written with their newlines escaped.

    (define (page-frame (text String)) (→ String)
      (string-append "data: " text "\n\n"))

    ;; A page's stream starts with its target's current event, so a page
    ;; that reconnects hears of the build it missed.

    (define (page-first-frames (host Host) (name String)) (→ String) (! fs)
      (let ((snapshot (● host snapshot)))
        (string-append "retry: 1000\n\n"
                       (page-frame (page-event snapshot
                                               (new Application (name name)
                                                    (builds (builds-of
                                                             (● snapshot publications)
                                                             name))))))))

    ;; Each browser target's pages hear its event when it changes.

    (define (told-pages (host Host)) (→ Host) (! mut tcp fs host)
      (fold-left (lambda (host application)
                   (let ((name (● application name))
                         (event (page-event (● host snapshot) application)))
                     (match (assoc-ref (● host told) name)
                       ((Some told) (if (string=? told event) host (told-page host name event)))
                       ((None) (told-page host name event)))))
                 host
                 (served-applications host)))

    ;; `event` to the pages of target `name`, kept as the last they heard.

    (define (told-page (host Host) (name String) (event String)) (→ Host) (! mut tcp host)
      (Host-clients-set
       (Host-told-set host
                      (Cons (new Pair (first name) (second event))
                            (filter (lambda (told) (not (string=? (● told first) name)))
                                    (● host told))))
       (sent-to (● host clients)
                (lambda (client)
                  (match (● client watching)
                    ((Some watched) (string=? watched name))
                    ((None) #f)))
                (string->utf8 (page-frame event)))))

    (define (first-frames (host Host)) (→ String)
      (string-append "retry: 1000\n\n" (protocol-state->event (editor-state host))))

    (define (option-some? (option (Option T))) (→ Bool) (∀ (T))
      (match option
        ((Some _) #t)
        ((None) #f)))

    (define (written (host Host) (id I64) (count I64)) (→ Host)
      (Host-clients-set host
                        (map (lambda (client)
                               (if (= (● client id) id)
                                   (Client-pending-set client (- (● client pending) count))
                                   client))
                             (● host clients))))

    ;; ---- Shutting down ----

    ;; No new work: the listeners and every stream close, each supervisor
    ;; stops its process, and the resident's input ends, so it finishes the
    ;; request it is answering and exits, or is killed after 2 s.

    (define (shut-down (host Host) (rest (List Command))) (→ Host) (! mut tasks tcp process fs host)
      (close-listener (● host listener))
      (close-listener (● host applications))
      (for-each (lambda (client) (mailbox-post (● client frames) (None))) (● host clients))
      (for-each (lambda (open) (close-connection (● open second)) (unit))
                (● host connections))
      (for-each (lambda (run) (mailbox-post (● run inbox) (Finish))) (● host runs))
      (mailbox-post (● host requests) (None))
      (mailbox-post (● host disk) (Stopping))
      (match (● host editor-process)
        ((Some child) (close-process child) (unit))
        ((None) (unit)))
      (let ((owner (● host owner)))
        (dispatch-local (lambda () (sleep 2000) (mailbox-post owner (Overdue)))))
      (resumed
       (Host-waiting-set (Host-connections-set (Host-stopping-set (Host-clients-set host (Nil))
                                                                  (Some rest))
                                               (Nil))
                         (+ (+ (length (● host runs)) (length (● host connections)))
                            (+ (if (● host resident-alive) 1 0)
                               (if (option-some? (● host editor-process)) 1 0))))))

    ;; A connection accepted while stopping is closed at once; its handler
    ;; still reports that it finished.

    (define (connected (host Host) (id I64) (connection Connection)) (→ Host) (! tcp)
      (match (● host stopping)
        ((Some _)
         (close-connection connection)
         (Host-waiting-set host (+ (● host waiting) 1)))
        ((None)
         (Host-connections-set host
                               (Cons (new Pair (first id) (second connection))
                                     (● host connections))))))

    ;; A finished handler's connection, and its event stream if it had one.

    (define (disconnected (host Host) (id I64)) (→ Host) (! mut tasks tcp process fs host)
      (match (● host stopping)
        ((Some _) (stopped-one host))
        ((None)
         (Host-clients-set (Host-connections-set host
                                                 (filter
                                                  (lambda (open) (not (= (● open first) id)))
                                                  (● host connections)))
                           (filter (lambda (client) (not (= (● client id) id)))
                                   (● host clients))))))

    ;; Once nothing is still stopping, the commands after Shutdown.

    (define (resumed (host Host)) (→ Host) (! mut tasks tcp process fs host)
      (match (● host stopping)
        ((Some rest)
         (if (= (● host waiting) 0)
             (perform-all (Host-stopping-set host (Some (Nil))) rest)
             host))
        ((None) host)))

    (define (stopped-one (host Host)) (→ Host) (! mut tasks tcp process fs host)
      (resumed (Host-waiting-set host (- (● host waiting) 1))))

    (define (resident-gone (host Host) (message String)) (→ Host) (! mut tasks tcp process fs host)
      (let ((host (Host-resident-alive-set host #f)))
        (match (● host stopping)
          ((Some _) (stopped-one host))
          ((None) (stepped host (ResidentExited message))))))

    (define (overdue (host Host)) (→ Host) (! process)
      (when (● host resident-alive)
        (send-signal (● host resident) (Kill))
        (unit))
      host)

    ;; ---- The disk ----

    ;; The project, the libraries and the browser host, leaving out build
    ;; output and Git's directory.

    (define (watched (setup Setup)) (→ (Pair (List String) (List String)))
      (let ((root (● setup root)) (project (● setup project)))
        (new Pair
          (first (list project (string-append root "/src") (string-append root "/host/browser")
                       (string-append root "/host/ide")))
          (second (list (string-append project "/build")
                        (string-append project "/.git")
                        (string-append root "/build") (string-append root "/host/ide/build"))))))

    (define (take-inventory (setup Setup)) (→ (Result Inventory String)) (! fs)
      (let ((roots (watched setup)))
        (inventory (● roots first) (● roots second))))

    ;; The last complete inventory, and why the latest failed, if it did.
    (record Disk
      ((taken Inventory)
       (failure (Option String))))

    ;; Takes the first inventory as what is there, then one for each scan
    ;; asked, reporting what changed since the last. Hints from a watch of
    ;; each root ask for one at once; the timer asks each second, as a
    ;; watch can miss a change. After Stopping it closes the watches,
    ;; answers the timer that it is done, and ends.

    (define (scan-disk (setup Setup) (owner (Mailbox Message)) (requests (Mailbox Scan)))
      (→ Unit)
      (! mut tasks fs hints host)
      (let* ((roots (watched setup))
             (watches (watch-roots (● roots first) (● roots second) requests)))
        (let loop ((disk
                    (rescan setup owner (new Disk (taken (empty-inventory)) (failure (None))) #f))
                   (stopping #f))
          (match (mailbox-receive requests)
            ((Stopping)
             (for-each close-watch watches)
             (loop disk #t))
            ((Ticked reply)
             (mailbox-post reply (not stopping))
             (unless stopping (loop (rescan setup owner disk #t) #f)))
            ((Listing reply)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post reply (disk-result next (● next taken)))
               (loop next stopping)))
            ((Prompted) (loop (if stopping disk (rescan setup owner disk #t)) stopping))
            ((Reconciling)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post owner (Step (Reconciled (disk-result next (unit)))))
               (loop next stopping)))))))

    ;; What the latest inventory found, unless it failed.

    (define (disk-result (disk Disk) (value T))
      (→ (Result T String))
      (∀ (T))
      (match (● disk failure)
        ((Some message) (Err message))
        ((None) (Ok value))))

    ;; A watch of each root that can be watched, each with a task that
    ;; turns its hints into scans until it closes.

    (define (watch-roots (roots (List String)) (excluded (List String)) (disk (Mailbox Scan)))
      (→ (List Watch))
      (! mut hints host tasks)
      (match roots
        ((Nil) (Nil))
        ((Cons root rest)
         (match (watch-tree root excluded)
           ((Some watch)
            (dispatch-local (lambda () (relay-hints watch disk)))
            (Cons watch (watch-roots rest excluded disk)))
           ((None) (watch-roots rest excluded disk))))))

    (define (relay-hints (watch Watch) (disk (Mailbox Scan))) (→ Unit) (! mut tasks hints host)
      (when (next-hint watch)
        (mailbox-post disk (Prompted))
        (relay-hints watch disk)))

    ;; Another inventory, reported as what changed since the last complete
    ;; one when `report?`, as it is but for the first. A failure keeps the
    ;; last, and is reported once, when it begins; the next inventory that
    ;; succeeds reports the recovery, after what changed meanwhile.

    (define (rescan (setup Setup) (owner (Mailbox Message)) (disk Disk) (report? Bool))
      (→ Disk)
      (! mut fs)
      (match (take-inventory setup)
        ((Ok next)
         (let ((changes (inventory-changes (● disk taken) next)))
           (when (and report? (not (null? changes)))
             (mailbox-post owner (Step (Touched changes))))
           (when (option-some? (● disk failure))
             (mailbox-post owner (Step (Uncertain (None)))))
           (new Disk (taken next) (failure (None)))))
        ((Err message)
         (unless (option-some? (● disk failure))
           (mailbox-post owner (Step (Uncertain (Some message)))))
         (Disk-failure-set disk (Some message)))))

    ;; A scan each second, until the disk task stops.

    (define (tick (disk (Mailbox Scan))) (→ Unit) (! mut tasks host)
      (sleep 1000)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Ticked reply))
        (when (mailbox-receive reply)
          (tick disk))))

    ;; ---- The resident ----

    (define (resident-process (setup Setup)) (→ Process) (! tasks process)
      (match (spawn (new ProcessCommand (program (● setup node))
                         (arguments (list "--no-warnings"
                                          (runner setup)
                                          (● setup cli)
                                          (● setup root)
                                          (● setup runtime)
                                          "resident"
                                          (● setup project)))
                         (directory ".")))
        ((Ok process) process)
        ((Err error)
         (panic (string-append "cannot start the resident builder: "
                               (● error code))))))

    ;; One request a line, until the input ends.

    (define (write-requests (resident Process) (requests (Mailbox (Option String))))
      (→ Unit)
      (! mut tasks process)
      (match (mailbox-receive requests)
        ((Some line)
         (match (write-all resident (string->utf8 (string-append line "\n")))
           ((Ok _) (write-requests resident requests))
           ((Err _) (unit))))
        ((None)
         (close-input resident)
         (unit))))

    (define (write-all (child Process) (bytes Bytes))
      (→ (Result Unit ProcessError))
      (! tasks process)
      (if (= (vector-length bytes) 0)
          (Ok (unit))
          (match (write-input child bytes)
            ((Ok count)
             (write-all child (subvector bytes (i32->i64 count) (vector-length bytes))))
            ((Err error) (Err error)))))

    ;; Each reply line, as the message it is. `pending` holds the bytes of a
    ;; line not yet ended, newest chunk first.

    (define (read-replies (resident Process) (owner (Mailbox Message)) (pending (List Bytes)))
      (→ Unit)
      (! mut tasks process host)
      (match (read-output resident (Stdout) 65536)
        ((Ok (Some bytes)) (read-replies resident owner (post-lines owner (Cons bytes pending))))
        (_ (unit))))

    ;; Posts each whole line in the chunks, and keeps what follows the last.

    (define (post-lines (owner (Mailbox Message)) (pending (List Bytes)))
      (→ (List Bytes))
      (! mut host)
      (let* ((bytes (vector-concatenate (reverse pending))) (end (vector-index-of bytes 10)))
        (match end
          ((Some at)
           (mailbox-post owner (reply-message (subvector bytes 0 at)))
           (post-lines owner (list (subvector bytes (+ at 1) (vector-length bytes)))))
          ((None) (list bytes)))))

    (define (vector-index-of (bytes Bytes) (code I32)) (→ (Option I64))
      (let loop ((index 0))
        (cond ((= index (vector-length bytes)) (None))
              ((= (u8->i32 (vector-ref bytes index)) code) (Some index))
              (else (loop (+ index 1))))))

    ;; A reply, by the members it has: a build's diagnostics, a
    ;; publication's error, or a discard's epoch alone. One that is not
    ;; JSON is the resident failing.

    (define (reply-message (line Bytes)) (→ Message)
      (match (match (utf8->string line)
               ((Ok text) (string->json text))
               ((Err _) (None)))
        ((Some json)
         (match (json-member json "epoch")
           ((Some (JsonInteger epoch)) (epoch-reply json epoch))
           (_ (Step (ResidentExited "the resident builder replied without an epoch")))))
        ((None)
         (Step (ResidentExited "the resident builder replied with something other than JSON")))))

    (define (epoch-reply (json Json) (epoch I64)) (→ Message)
      (cond ((option-some? (json-member json "diagnostics"))
             (Built epoch (json->reply json) (candidate-targets json)))
            ((option-some? (json-member json "error"))
             (Step (PublishReplied epoch (match (json-member json "error")
                                           ((Some (JsonString message)) (Some message))
                                           (_ (None))))))
            (else (Step (DiscardReplied epoch)))))

    ;; Reads what the resident writes to stderr, a panic's message, then
    ;; waits for it to exit, which the end of stderr means is near.

    (define (await-resident (resident Process) (owner (Mailbox Message)) (tail (List Bytes)))
      (→ Unit)
      (! mut tasks process host)
      (match (read-output resident (Stderr) 65536)
        ((Ok (Some bytes)) (await-resident resident owner (Cons bytes tail)))
        (_
         (mailbox-post owner
                       (ResidentGone (string-append "the resident builder exited with "
                                                    (exit-text (wait-exit resident))
                                                    (stderr-text tail)))))))

    (define (exit-text (exit (Result Exit ProcessError))) (→ String)
      (match exit
        ((Ok (Exited code)) (string-append "status " (show code)))
        ((Ok (Signaled name)) name)
        ((Err error) (● error code))))

    ;; The last 4096 bytes written, trimmed, after a colon.

    (define (stderr-text (tail (List Bytes))) (→ String)
      (let* ((bytes (vector-concatenate (reverse tail)))
             (start (max 0 (- (vector-length bytes) 4096)))
             (text (match (utf8->string (subvector bytes start (vector-length bytes)))
                     ((Ok text) (trimmed text))
                     ((Err _) ""))))
        (if (string=? text "") "" (string-append ": " text))))

    (define (trimmed (text String)) (→ String)
      (let loop ((start 0) (end (string-length text)))
        (cond
         ((and (< start end) (char-whitespace? (string-ref text start))) (loop (+ start 1) end))
         ((and (< start end) (char-whitespace? (string-ref text (- end 1))))
          (loop start (- end 1)))
         (else (substring text start end)))))

    ;; ---- The resident's replies ----

    (define (json->reply (json Json)) (→ Reply)
      (new Reply (description (match (json-object json "description")
                                ((Some description) (Some (json->description description)))
                                ((None) (None))))
           (candidate (match (json-object json "candidate")
                        ((Some candidate) (Some (json->candidate candidate)))
                        ((None) (None))))
           (diagnostics (map json->diagnostic (json-items json "diagnostics")))))

    (define (json->description (json Json)) (→ Description)
      (let ((builds (json-items json "builds")))
        (new Description (entries (map (lambda (build) (json-text build "entry")) builds))
             (publics (fold-right (lambda (build publics)
                                    (match (json-member build "public")
                                      ((Some (JsonString path)) (Cons path publics))
                                      (_ publics)))
                                  (Nil)
                                  builds))
             (browsers (map (lambda (build) (json-text build "name"))
                            (filter (lambda (build) (string=? (json-text build "kind") "browser"))
                                    builds)))
             (runs (map (lambda (run)
                          (new RunDefinition (name (json-text run "name"))
                               (build (json-text run "build"))
                               (arguments (map json-string-value (json-items run "args")))))
                        (json-items json "runs"))))))

    (define (json->candidate (json Json)) (→ Candidate)
      (new Candidate (description (match (json-member json "description")
                                    ((Some description) (json->description description))
                                    ((None)
                                     (new Description
                                       (entries (Nil))
                                       (publics (Nil))
                                       (browsers (Nil))
                                       (runs (Nil))))))
           (generations (map (lambda (target)
                               (new Generation (name (json-text target "name"))
                                    (directory (json-text target "directory"))
                                    (digest (json-text target "digest"))
                                    (files (match (json-member target "files")
                                             ((Some (JsonObject members))
                                              (map (lambda (member)
                                                     (new Pair (first (● member first))
                                                          (second
                                                           (json-string-value (● member second)))))
                                                   members))
                                             (_ (Nil))))
                                    (linked (map json-string-value (json-items target "linked")))))
                             (json-items json "targets")))
           (milliseconds (json-integer json "milliseconds"))))

    ;; The candidate's targets as the status shows them.

    (define (candidate-targets (json Json)) (→ Json)
      (match (json-member json "candidate")
        ((Some candidate)
         (JsonArray (map (lambda (target)
                           (JsonObject (fold-right (lambda (name kept)
                                                     (match (json-member target name)
                                                       ((Some value)
                                                        (Cons (new Pair (first name) (second value))
                                                              kept))
                                                       ((None) kept)))
                                                   (Nil)
                                                   (list "name"
                                                         "directory"
                                                         "digest"
                                                         "compiled"))))
                         (json-items candidate "targets"))))
        ((None) (JsonArray (Nil)))))

    (define (json->diagnostic (json Json)) (→ Diagnostic)
      (new Diagnostic (message (json-text json "message"))
           (source (match (json-object json "source")
                     ((Some source)
                      (Some (new SourcePoint (file (json-text source "file"))
                                 (line (json-integer source "line"))
                                 (column (json-integer source "column")))))
                     ((None) (None))))))

    ;; A member that is an object, as a null one is not.

    (define (json-object (json Json) (name String)) (→ (Option Json))
      (match (json-member json name)
        ((Some (JsonObject members)) (Some (JsonObject members)))
        (_ (None))))

    (define (json-items (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    (define (json-text (json Json) (name String)) (→ String)
      (match (json-member json name)
        ((Some value) (json-string-value value))
        ((None) "")))

    (define (json-string-value (json Json)) (→ String)
      (match json
        ((JsonString text) text)
        (_ "")))

    (define (json-integer (json Json) (name String)) (→ I64)
      (match (json-member json name)
        ((Some (JsonInteger value)) value)
        (_ 0)))

    ;; ---- Supervising a run target ----

    ;; One run target, its latest request and the process it owns. Each
    ;; request has a serial, so a request repeated is run again, and output
    ;; or an exit for an earlier process is ignored.
    (record Child
      ((serial I64)
       (request RunRequest)
       (process (Option Process))
       (stopping Bool)
       (exit (Option (Result Exit ProcessError)))
       (stdout Bytes)
       (stderr Bytes)))

    (record Supervisor
      ((setup Setup)
       (owner (Mailbox Message))
       (inbox (Mailbox Supervision))
       (name String)
       (desired (Option (Pair I64 RunRequest)))
       (serial I64)
       (child (Option Child))
       (finishing Bool)))

    (define (new-supervisor (setup Setup)
                            (owner (Mailbox Message))
                            (inbox (Mailbox Supervision))
                            (name String))
      (→ Supervisor)
      (new Supervisor
        (setup setup)
        (owner owner)
        (inbox inbox)
        (name name)
        (desired (None))
        (serial 0)
        (child (None))
        (finishing #f)))

    ;; Receives, runs what is wanted, and reports. A finishing supervisor
    ;; ends once its process has.

    (define (supervise (supervisor Supervisor)) (→ Unit) (! mut tasks process host)
      (let ((supervisor (reconcile-run (supervised supervisor
                                                   (mailbox-receive
                                                    (● supervisor inbox))))))
        (mailbox-post (● supervisor owner)
                      (RunChanged (● supervisor name) (supervisor-state supervisor)))
        (if (and (● supervisor finishing) (not (running? supervisor)))
            (mailbox-post (● supervisor owner) (RunStopped))
            (supervise supervisor))))

    (define (supervised (supervisor Supervisor) (message Supervision))
      (→ Supervisor)
      (! process)
      (match message
        ((Want wanted)
         (let ((serial (+ (● supervisor serial) 1)))
           (Supervisor-serial-set (Supervisor-desired-set supervisor
                                                          (match wanted
                                                            ((Some request)
                                                             (Some (new Pair
                                                                     (first serial)
                                                                     (second request))))
                                                            ((None) (None))))
                                  serial)))
        ((Output serial stream bytes) (child-output supervisor serial stream bytes))
        ((Ended serial exit) (child-ended supervisor serial exit))
        ((Late serial) (late supervisor serial))
        ((Finish) (Supervisor-finishing-set (Supervisor-desired-set supervisor (None)) #t))))

    (define (running? (supervisor Supervisor)) (→ Bool)
      (match (● supervisor child)
        ((Some child) (not (option-some? (● child exit))))
        ((None) #f)))

    ;; A process that is not the one wanted is stopped; once none runs,
    ;; the one wanted is launched, unless it already ran and ended.

    (define (reconcile-run (supervisor Supervisor)) (→ Supervisor) (! mut tasks process host)
      (match (new Pair (first (● supervisor child)) (second (● supervisor desired)))
        ((Pair (Some child) wanted)
         (cond ((option-some? (● child exit))
                (match wanted
                  ((Some (Pair serial request))
                   (if (= serial (● child serial))
                       supervisor
                       (start-child supervisor serial request)))
                  ((None) supervisor)))
               ((and (not (● child stopping)) (not (wants? wanted (● child serial))))
                (stop-child supervisor child))
               (else supervisor)))
        ((Pair (None) (Some (Pair serial request))) (start-child supervisor serial request))
        ((Pair (None) (None)) supervisor)))

    (define (wants? (wanted (Option (Pair I64 RunRequest))) (serial I64)) (→ Bool)
      (match wanted
        ((Some (Pair wanted-serial _)) (= wanted-serial serial))
        ((None) #f)))

    ;; SIGTERM, and SIGKILL if the process has not ended 2 s later.

    (define (stop-child (supervisor Supervisor) (child Child))
      (→ Supervisor)
      (! mut process host tasks)
      (match (● child process)
        ((Some process) (send-signal process (Terminate)) (unit))
        ((None) (unit)))
      (let ((inbox (● supervisor inbox)) (serial (● child serial)))
        (dispatch-local (lambda () (sleep 2000) (mailbox-post inbox (Late serial)))))
      (Supervisor-child-set supervisor (Some (Child-stopping-set child #t))))

    (define (late (supervisor Supervisor) (serial I64)) (→ Supervisor) (! process)
      (match (● supervisor child)
        ((Some child)
         (when (and (= (● child serial) serial) (not (option-some? (● child exit))))
           (match (● child process)
             ((Some process) (send-signal process (Kill)) (unit))
             ((None) (unit))))
         supervisor)
        ((None) supervisor)))

    ;; The run's program on Node, with its standard input closed, and a
    ;; task for each of its outputs and its exit.

    (define (start-child (supervisor Supervisor) (serial I64) (request RunRequest))
      (→ Supervisor)
      (! mut tasks process host)
      (let ((setup (● supervisor setup)) (inbox (● supervisor inbox)))
        (match (spawn (new ProcessCommand (program (● setup node))
                           (arguments (append
                                       (list "--no-warnings"
                                             (runner setup)
                                             (● request entry))
                                       (● request arguments)))
                           (directory ".")))
          ((Ok process)
           (close-input process)
           (dispatch-local (lambda () (forward-output process inbox serial (Stdout))))
           (dispatch-local (lambda () (forward-output process inbox serial (Stderr))))
           (dispatch-local
            (lambda () (mailbox-post inbox (Ended serial (wait-exit process)))))
           (Supervisor-child-set supervisor
                                 (Some (new Child (serial serial)
                                            (request request)
                                            (process (Some process))
                                            (stopping #f)
                                            (exit (None))
                                            (stdout (empty-bytes))
                                            (stderr (empty-bytes))))))
          ((Err error)
           (Supervisor-child-set supervisor
                                 (Some (new Child (serial serial)
                                            (request request)
                                            (process (None))
                                            (stopping #f)
                                            (exit (Some (Err error)))
                                            (stdout (empty-bytes))
                                            (stderr (empty-bytes)))))))))

    (define (empty-bytes) (→ Bytes)
      (make-vector 0 (i32->u8 0)))

    (define (forward-output (process Process)
                            (inbox (Mailbox Supervision))
                            (serial I64)
                            (stream Stream))
      (→ Unit)
      (! mut tasks process host)
      (match (read-output process stream 65536)
        ((Ok (Some bytes))
         (mailbox-post inbox (Output serial stream bytes))
         (forward-output process inbox serial stream))
        (_ (unit))))

    ;; Each output keeps its last 64 KiB.

    (define (child-output (supervisor Supervisor) (serial I64) (stream Stream) (bytes Bytes))
      (→ Supervisor)
      (match (● supervisor child)
        ((Some child)
         (if (= (● child serial) serial)
             (Supervisor-child-set supervisor
                                   (Some (match stream
                                           ((Stdout)
                                            (Child-stdout-set child
                                                              (output-tail (● child stdout)
                                                                           bytes)))
                                           ((Stderr)
                                            (Child-stderr-set child
                                                              (output-tail (● child stderr)
                                                                           bytes))))))
             supervisor))
        ((None) supervisor)))

    (define (output-tail (kept Bytes) (bytes Bytes)) (→ Bytes)
      (let* ((joined (vector-concatenate (list kept bytes))) (length (vector-length joined)))
        (subvector joined (max 0 (- length 65536)) length)))

    (define (child-ended (supervisor Supervisor) (serial I64) (exit (Result Exit ProcessError)))
      (→ Supervisor)
      (! process)
      (match (● supervisor child)
        ((Some child)
         (if (= (● child serial) serial)
             (begin
               (match (● child process)
                 ((Some process) (close-process process) (unit))
                 ((None) (unit)))
               (Supervisor-child-set supervisor (Some (Child-exit-set child (Some exit)))))
             supervisor))
        ((None) supervisor)))

    ;; The target's status: what is wanted, and the process it owns.

    (define (supervisor-state (supervisor Supervisor)) (→ protocol-Run)
      (new protocol-Run (target (● supervisor name))
           (desired (match (● supervisor desired)
                      ((Some (Pair _ request)) (Some (● request build)))
                      ((None) (None))))
           (attempt (match (● supervisor child)
                      ((Some child) (Some (child-state child)))
                      ((None) (None))))
           (wanted #f) (available #f)))

    (define (child-state (child Child)) (→ protocol-Attempt)
      (new protocol-Attempt
        (build (● (● child request) build))
        (pid (match (● child process)
               ((Some process) (Some (i32->i64 (● process id)))) ((None) (None))))
        (phase (child-phase child))
        (code (match (● child exit)
                ((Some (Ok (Exited code))) (Some (i32->i64 code))) (_ (None))))
        (signal (match (● child exit) ((Some (Ok (Signaled name))) name) (_ "")))
        (error (match (● child exit) ((Some (Err error)) (● error code)) (_ "")))
        (stdout (lossy-text (● child stdout))) (stderr (lossy-text (● child stderr)))))

    (define (child-phase (child Child)) (→ String)
      (match (● child exit)
        ((Some (Err _)) "failed")
        ((Some (Ok _)) "exited")
        ((None)
         (cond ((● child stopping) "stopping")
               ((option-some? (● child process)) "running")
               (else "starting")))))

    ;; Output as text, each byte that is not UTF-8 as U+FFFD.

    (define (lossy-text (bytes Bytes)) (→ String)
      (match (utf8->string bytes)
        ((Ok text) text)
        ((Err _)
         (list->string (map (lambda (byte)
                              (if (< (u8->i32 byte) 128)
                                  (i32->char (u8->i32 byte))
                                  (i32->char 65533)))
                            (vector->list bytes))))))

    ;; ---- HTTP ----

    ;; One handler task for each connection.

    (define (accept-connections (setup Setup)
                                (listener Listener)
                                (owner (Mailbox Message))
                                (disk (Mailbox Scan)))
      (→ Unit)
      (! mut tasks tcp fs modes process host)
      (let loop ((id 0))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch-local (lambda ()
                             (serve-connection setup owner disk id connection)
                             (mailbox-post owner (Disconnected id))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (define (security-headers) (→ (List Header))
      (list (new Header (name "Cache-Control") (value "no-store"))
            (new Header (name "X-Content-Type-Options") (value "nosniff"))
            (new Header (name "X-Frame-Options") (value "DENY"))))

    (define (json-response (status I32) (body Json)) (→ Response)
      (new Response (status status)
           (headers
            (Cons (new Header (name "Content-Type") (value "application/json")) (security-headers)))
           (body (if (= status 204) (empty-bytes) (string->utf8 (json->string body))))))

    (define (refused (status I32) (message String)) (→ Response)
      (json-response status (protocol-message->json message)))

    ;; A connection's one request, by the connection's number.

    (define (serve-connection (setup Setup)
                              (owner (Mailbox Message))
                              (disk (Mailbox Scan))
                              (id I64)
                              (connection Connection))
      (→ Unit)
      (! mut tasks tcp fs modes process host)
      (match (read-request connection)
        ((Ok request)
         (let ((method (● (● request head) method)))
           (match (route setup owner disk id connection request)
             ((Some response) (finish-exchange connection (Some method) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    (define (finish-exchange (connection Connection) (method (Option String)) (response Response))
      (→ Unit)
      (! tcp tasks)
      (match (ann (respond connection 2000 method response) (Result Unit (ExchangeError Unit)))
        ((Ok _) (unit))
        ((Err _) (close-connection connection) (unit))))

    (define (exchange-refusal (error (ExchangeError Unit))) (→ Response)
      (match error
        ((ProtocolFailure (Unsupported "Transfer-Encoding"))
         (refused 411 "requests must give a Content-Length, not a Transfer-Encoding"))
        ((ProtocolFailure (HeadTooLarge)) (refused 431 "the request head is too large"))
        ((ProtocolFailure (BodyTooLarge)) (refused 413 "request exceeds 8 MiB"))
        (_ (refused 400 "malformed request"))))

    ;; The response to a request, or None for an event stream, which this
    ;; task then writes until it ends.

    (define (route (setup Setup)
                   (owner (Mailbox Message))
                   (disk (Mailbox Scan))
                   (id I64)
                   (connection Connection)
                   (request Request))
      (→ (Option Response))
      (! mut tasks tcp fs modes process host)
      (let ((head (● request head)))
        (match (parse-target (● head target))
          ((Err _) (Some (refused 400 "malformed request target")))
          ((Ok target)
           (match (authorization setup head target)
             ((Some message) (Some (refused 403 message)))
             ((None) (serve-target setup owner disk id connection request target)))))))

    ;; A GET of an editor asset, the event stream, or the API.

    (define (serve-target (setup Setup)
                          (owner (Mailbox Message))
                          (disk (Mailbox Scan))
                          (id I64)
                          (connection Connection)
                          (request Request)
                          (target Target))
      (→ (Option Response))
      (! mut tasks tcp fs modes process host)
      (let ((method (● (● request head) method)) (path (● target path)))
        (cond ((not (string=? method "GET"))
               (Some (api setup owner disk request method path (● target query))))
              ((same-strings? path (list "manifest.webmanifest")) (Some (editor-manifest)))
              ((same-strings? path (list "api" "events"))
               (stream-events owner id connection (None))
               (None))
              (else
               (Some (if (match path ((Cons "api" _) #t) (_ #f))
                         (api setup owner disk request method path (● target query))
                         (editor-asset setup owner path)))))))

    (define (api (setup Setup)
                 (owner (Mailbox Message))
                 (disk (Mailbox Scan))
                 (request Request)
                 (method String)
                 (path (List String))
                 (query (List (Pair String String))))
      (→ Response)
      (! mut tasks fs modes process host)
      (match (new Pair (first method) (second path))
        ((Pair "GET" (Cons "api" (Cons "project" (Nil)))) (project-listing setup disk))
        ((Pair "GET" (Cons "api" (Cons "search" (Nil))))
         (project-search setup disk (query-value query "q")))
        ((Pair "GET" (Cons "api" (Cons "file" (Nil))))
         (file-response (read-project-text (● setup project) (query-value query "path"))))
        ((Pair "GET" (Cons "api" (Cons "status" (Nil))))
         (asking owner (lambda (reply) (Status reply))))
        ((Pair "POST" (Cons "api" (Cons "build" (Nil))))
         (commanding request owner (RequestBuild)))
        ((Pair "POST" (Cons "api" (Cons "run" (Cons action (Nil)))))
         (match (run-control action (query-value query "target"))
           ((Some event) (commanding request owner event))
           ((None) (refused 404 "unknown project endpoint"))))
        ((Pair "POST" (Cons "api" (Cons "file" (Nil))))
         (create-entry-response setup disk request (query-value query "path") #f))
        ((Pair "POST" (Cons "api" (Cons "directory" (Nil))))
         (create-entry-response setup disk request (query-value query "path") #t))
        ((Pair "PUT" (Cons "api" (Cons "file" (Nil))))
         (save setup disk request (query-value query "path")))
        (_ (refused 404 "unknown project endpoint"))))

    (define (run-control (action String) (target String)) (→ (Option Event))
      (cond ((string=? action "start") (Some (StartRun target)))
            ((string=? action "stop") (Some (StopRun target)))
            ((string=? action "restart") (Some (RestartRun target)))
            (else (None))))

    (define (query-value (query (List (Pair String String))) (name String)) (→ String)
      (match (find (lambda (pair) (string=? (● pair first) name)) query)
        ((Some pair) (● pair second))
        ((None) "")))

    ;; A command takes no body; the owner answers it once the step has.

    (define (commanding (request Request) (owner (Mailbox Message)) (event Event))
      (→ Response)
      (! mut tasks)
      (if (> (vector-length (● request body)) 0)
          (refused 400 "command takes no request body")
          (asking owner (lambda (reply) (Ask event reply)))))

    (define (asking (owner (Mailbox Message)) (message (Fn (Mailbox Answer) → Message ! mut)))
      (→ Response)
      (! mut tasks)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (message reply))
        (let ((answer (mailbox-receive reply)))
          (json-response (● answer status) (● answer body)))))

    (record ProjectEntries
      ((files (List String))
       (directories (List String))))

    ;; Both listing and search use a fresh inventory, filtered through the
    ;; same served-path boundary as file reads, then Git's visibility rules.
    ;; Ignore filtering never changes compiler inputs or explicit file access.

    (define (project-files (setup Setup) (disk (Mailbox Scan)))
      (→ (Result ProjectEntries Response))
      (! mut tasks fs process host)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Listing reply))
        (match (mailbox-receive reply)
          ((Err message) (Err (refused 500 message)))
          ((Ok taken)
           (match (project-text-paths (● setup project) (inventory-files taken))
             ((Ok files)
              (visible-entries (● setup project)
                               (new ProjectEntries
                                 (files files)
                                 (directories (project-directory-paths (● setup project)
                                                                       (inventory-directories
                                                                        taken))))))
             ((Err refusal) (Err (file-refusal refusal))))))))

    (define (visible-entries (directory String) (entries ProjectEntries))
      (→ (Result ProjectEntries Response))
      (! mut tasks process host)
      (match (ignore-read-gitignore directory)
        ((Err message) (Err (refused 500 message)))
        ((Ok (None)) (Ok entries))
        ((Ok (Some snapshot))
         (let ((visible? (lambda (path) (not (ignore-ignored? snapshot path)))))
           (Ok (new ProjectEntries (files (filter visible? (● entries files)))
                    (directories (filter visible? (● entries directories)))))))))

    (define (project-listing (setup Setup) (disk (Mailbox Scan)))
      (→ Response)
      (! mut tasks fs process host)
      (match (project-files setup disk)
        ((Err response) response)
        ((Ok files)
         (let ((project (● setup project)))
           (json-response 200
                          (protocol-project->json
                           (new protocol-Project (name (base-name project)) (directory project)
                                (files (● files files))
                                (directories (● files directories)))))))))

    (define (project-search (setup Setup) (disk (Mailbox Scan)) (text String))
      (→ Response)
      (! mut tasks fs process host)
      (match (search-parse-query text)
        ((Err message) (refused 400 message))
        ((Ok query)
         (match (project-files setup disk)
           ((Err response) response)
           ((Ok paths)
            (json-response 200
                           (search-json
                            (search-search-project (● setup project)
                                                   (● paths files)
                                                   query))))))))

    (define (search-json (results search-Results)) (→ Json)
      (protocol-search->json
       (new protocol-SearchResults
         (hits (map (lambda (hit)
                      (new protocol-Hit
                        (point (new protocol-Point (file (● hit path)) (line (● hit line))
                                    (column (● hit column))))
                        (revision (● hit revision)) (snippet (● hit snippet))))
                    (● results hits)))
         (skipped (● results skipped)) (limited (● results limited)))))

    (define (file-response (result (Result ProjectText FileRefusal))) (→ Response)
      (match result
        ((Ok text)
         (json-response 200 (protocol-file->json (new protocol-Snapshot (text (● text text))
                                                      (revision (● text revision))))))
        ((Err refusal) (file-refusal refusal))))

    (define (file-refusal (refusal FileRefusal)) (→ Response)
      (match refusal
        ((ChangedOnDisk) (refused 409 "the file changed on disk; reload it before saving"))
        ((NotServed message) (refused 400 message))
        ((DiskFailed (NotFound)) (refused 404 "no such file or directory"))
        ((DiskFailed (AlreadyExists))
         (refused 409 "a file or directory already exists at that path"))
        ((DiskFailed (PermissionDenied)) (refused 403 "permission denied"))
        ((DiskFailed error) (refused 500 (show error)))))

    (define (create-entry-response (setup Setup)
                                   (disk (Mailbox Scan))
                                   (request Request)
                                   (path String)
                                   (directory Bool))
      (→ Response)
      (! mut fs)
      (if (> (vector-length (● request body)) 0)
          (refused 400 "creation takes no request body")
          (match (if directory (create-project-directory (● setup project) path)
                     (create-project-file (● setup project) path))
            ((Err refusal) (file-refusal refusal))
            ((Ok _)
             (mailbox-post disk (Prompted))
             (json-response 201
                            (JsonObject
                             (list (new Pair (first "path") (second (JsonString path))))))))))

    ;; A save names one quoted revision and sends UTF-8 text/plain. Once it
    ;; is on disk, the disk task scans, so the build sees it within the
    ;; debounce rather than the next second.

    (define (save (setup Setup) (disk (Mailbox Scan)) (request Request) (path String))
      (→ Response)
      (! mut fs modes)
      (let ((head (● request head)))
        (match (expected-revision head)
          ((None) (refused 400 "save requires one quoted If-Match revision"))
          ((Some revision)
           (if (not (plain-text? head))
               (refused 415 "save requires UTF-8 text/plain")
               (match (utf8->string (● request body))
                 ((Err _) (refused 400 "save requires valid UTF-8"))
                 ((Ok text)
                  (let ((response (file-response
                                   (save-project-text (● setup project) path revision text))))
                    (mailbox-post disk (Prompted))
                    response))))))))

    ;; One strong opaque tag: lists, wildcards and weak tags are not this API.

    (define (expected-revision (head RequestHead)) (→ (Option String))
      (match (header-values (● head headers) "if-match")
        ((Cons value (Nil))
         (let ((length (string-length value)))
           (if (and (>= length 3)
                    (char=? (string-ref value 0) #\")
                    (char=? (string-ref value (- length 1)) #\")
                    (every? tag-char? (string->list (substring value 1 (- length 1)))))
               (Some (substring value 1 (- length 1)))
               (None))))
        (_ (None))))

    (define (tag-char? (char Char)) (→ Bool)
      (let ((code (char->i32 char)))
        (or (= code 33) (and (>= code 35) (<= code 91)) (and (>= code 93) (<= code 126)))))

    (define (plain-text? (head RequestHead)) (→ Bool)
      (match (header-values (● head headers) "content-type")
        ((Cons value (Nil))
         (let ((type (list->string (filter (lambda (char) (not (char-whitespace? char)))
                                           (string->list (string-downcase value))))))
           (or (string=? type "text/plain") (string=? type "text/plain;charset=utf-8"))))
        (_ #f)))

    ;; The host and origin must be this service's, so another page cannot
    ;; reach it; a fetch from another site is refused, except a navigation
    ;; to the editor itself; and a change must come from the project's own
    ;; page.

    (define (authorization (setup Setup) (head RequestHead) (target Target)) (→ (Option String))
      (let ((headers (● head headers)) (origin (origin setup)))
        (cond ((not (same-strings? (header-values headers "host")
                                   (list (substring origin 7 (string-length origin)))))
               (Some "unexpected host"))
              ((not (or (null? (header-values headers "origin"))
                        (same-strings? (header-values headers "origin") (list origin))))
               (Some "unexpected origin"))
              ((and (not (navigation? head target)) (cross-site? headers))
               (Some "unexpected fetch context"))
              ((and (not (string=? (● head method) "GET"))
                    (not (same-strings? (header-values headers "origin") (list origin))))
               (Some "mutation requires the project origin"))
              (else (None)))))

    ;; The target `/`, which parses as no segment or one empty one.

    (define (root-path? (path (List String))) (→ Bool)
      (match path
        ((Nil) #t)
        ((Cons "" (Nil)) #t)
        (_ #f)))

    (define (navigation? (head RequestHead) (target Target)) (→ Bool)
      (let ((headers (● head headers)))
        (and (string=? (● head method) "GET")
             (root-path? (● target path))
             (same-strings? (header-values headers "sec-fetch-mode") (list "navigate"))
             (same-strings? (header-values headers "sec-fetch-dest") (list "document")))))

    (define (cross-site? (headers (List Header))) (→ Bool)
      (match (header-values headers "sec-fetch-site")
        ((Cons site _) (not (or (string=? site "same-origin") (string=? site "none"))))
        ((Nil) #f)))

    (define (same-strings? (left (List String)) (right (List String))) (→ Bool)
      (and (= (length left) (length right))
           (every? (lambda (pair) (string=? (● pair first) (● pair second)))
                   (zip left right))))

    ;; ---- The applications' origin ----

    ;; One handler task for each connection, numbered apart from the
    ;; editor's, so the owner tracks both alike and shutdown waits for both.

    (define (accept-applications (setup Setup) (listener Listener) (owner (Mailbox Message)))
      (→ Unit)
      (! mut tasks tcp fs host)
      (let loop ((id 1099511627776))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch-local (lambda ()
                             (serve-application setup listener owner id connection)
                             (mailbox-post owner (Disconnected id))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (define (serve-application (setup Setup)
                               (listener Listener)
                               (owner (Mailbox Message))
                               (id I64)
                               (connection Connection))
      (→ Unit)
      (! mut tasks tcp fs host)
      (match (read-request connection)
        ((Ok request)
         (let ((head (● request head)))
           (match (application-response setup listener owner id connection head)
             ((Some response)
              (finish-exchange connection (Some (● head method)) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    ;; Only reads, and only for this origin's own host, so a page of another
    ;; site that rebinds a name to this address reads nothing. None for a
    ;; page's event stream, which this task then writes until it ends.

    (define (application-response (setup Setup)
                                  (listener Listener)
                                  (owner (Mailbox Message))
                                  (id I64)
                                  (connection Connection)
                                  (head RequestHead))
      (→ (Option Response))
      (! mut tasks tcp fs host)
      (let ((method (● head method)))
        (cond ((not (same-strings? (header-values (● head headers) "host")
                                   (list (listener-host listener))))
               (Some (refused 403 "unexpected host")))
              ((not (or (string=? method "GET") (string=? method "HEAD")))
               (Some (refused 405 "the applications' origin only serves files")))
              (else
               (match (parse-target (● head target))
                 ((Ok target)
                  (match (● target path)
                    ((Cons name (Cons ".snail" (Cons "events" (Nil))))
                     (stream-events owner id connection (Some name))
                     (None))
                    (path (Some (application-file setup owner path)))))
                 ((Err _) (Some (refused 400 "malformed request target"))))))))

    ;; `/` lists the browser targets, and /NAME/ serves one's builds.

    (define (application-file (setup Setup) (owner (Mailbox Message)) (path (List String)))
      (→ Response)
      (! mut tasks fs)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (Applications reply))
        (let ((applications (mailbox-receive reply)))
          (match (if (root-path? path) (Nil) path)
            ((Nil) (application-index applications))
            ((Cons name rest)
             (match (find (lambda (application) (string=? (● application name) name))
                          applications)
               ((Some application)
                (bundle-response (string-append "/" name "/")
                                 (new Reloading
                                   (host (string-append (● setup root) "/host/browser"))
                                   (program (● setup client)))
                                 (● application builds)
                                 rest))
               ((None) (refused 404 (string-append "no browser target " name)))))))))

    (define (application-index (applications (List Application))) (→ Response)
      (new Response (status 200)
           (headers (Cons (new Header (name "Content-Type") (value "text/html; charset=utf-8"))
                          (security-headers)))
           (body (string->utf8
                  (string-append
                   "<!doctype html>\n<meta charset=\"utf-8\">\n<title>Browser targets</title>\n"
                   (if (null? applications)
                       "<p>No browser target is built yet.</p>\n"
                       (string-concatenate
                        (map (lambda (application)
                               (let ((name (html-text (● application name))))
                                 (string-append "<p><a href=\"/" name "/\">" name "</a></p>\n")))
                             applications))))))))

    (define (html-text (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (cond ((char=? char #\<) "&lt;")
                    ((char=? char #\>) "&gt;")
                    ((char=? char #\&) "&amp;")
                    ((char=? char #\") "&quot;")
                    (else (make-string 1 char))))
            (string->list text))))

    ;; ---- The editor's builds ----

    ;; The IDE is a normal browser target. Keep complete successful generations
    ;; for this service's lifetime; no client leases or partially updated assets.
    (record EditorBundle
      ((id String)
       (directory String)))

    (define (editor-bundle (setup Setup)) (→ (Result EditorBundle String)) (! fs)
      (match (read-symbolic-link (● setup editor))
        ((Ok name)
         (Ok (new EditorBundle
               (id name)
               (directory (string-append (● setup root) "/host/ide/build/" name)))))
        ((Err error) (Err (string-append "cannot locate IDE build: " (show error))))))

    (define (editor-base (bundle EditorBundle)) (→ String)
      (string-append "/.snail/ide/" (● bundle id) "/"))

    (define (touched-editor (host Host) (event Event)) (→ Host) (! mut tasks process fs tcp host)
      (match (● host stopping)
        ((Some _) host)
        ((None) (editor-change host event))))

    (define (editor-change (host Host) (event Event)) (→ Host) (! mut tasks process fs tcp host)
      (match event
        ((Touched paths)
         (if (any? (lambda (path)
                     (any? (lambda (part)
                             (starts-with? path
                                           (string-append (● (● host setup) root) part)))
                           (list "/src/" "/host/ide/" "/host/browser/"))) paths)
             (match (● host editor-process)
               ((Some _) (Host-editor-again-set host #t))
               ((None) (start-editor host)))
             host))
        (_ host)))

    (define (start-editor (host Host)) (→ Host) (! mut tasks process fs tcp host)
      (let ((setup (● host setup)))
        (match (spawn (new ProcessCommand (program (● setup node))
                           (arguments (list "--no-warnings" (runner setup) (● setup cli)
                                            (● setup root) (● setup runtime)
                                            "build" "--release"
                                            (string-append (● setup root) "/host/ide") "ide"))
                           (directory (● setup root))))
          ((Err error) (broadcast-changes
                        (Host-editor-problem-set host (● error code))))
          ((Ok child)
           (close-input child)
           (dispatch-local (lambda () (await-editor setup (● host owner) child)))
           (Host-editor-process-set (Host-editor-again-set host #f) (Some child))))))

    ;; Drain both pipes while the compiler runs, so neither can block it.
    ;; The owner remains responsive and closes the child during shutdown.

    (define (await-editor (setup Setup) (owner (Mailbox Message)) (child Process))
      (→ Unit)
      (! mut tasks process fs host)
      (let ((errors (make-mailbox)))
        (dispatch-local (lambda () (mailbox-post errors (editor-output child (Stderr) ""))))
        (editor-output child (Stdout) "")
        (let ((exit (wait-exit child)) (error (mailbox-receive errors)))
          (close-process child)
          (mailbox-post owner
                        (EditorBuilt (match exit
                                       ((Ok (Exited 0)) (editor-bundle setup))
                                       (_ (Err
                                           (if (string=? error "") "IDE build failed" error)))))))))

    (define (editor-output (child Process) (stream Stream) (kept String))
      (→ String)
      (! tasks process)
      (match (read-output child stream 65536)
        ((Ok (Some bytes))
         (let* ((text (string-append kept (lossy-text bytes))) (size (string-length text)))
           (editor-output child stream (substring text (max 0 (- size 4096)) size))))
        (_ kept)))

    (define (editor-built (host Host) (result (Result EditorBundle String)))
      (→ Host)
      (! mut tasks process fs tcp host)
      (match (● host stopping)
        ((Some _) (stopped-one host))
        ((None)
         (let ((host (Host-editor-process-set host (None))))
           (if (● host editor-again) (start-editor host)
               (broadcast-changes
                (match result
                  ((Ok bundle)
                   (Host-editor-problem-set
                    (Host-editors-set host (Cons bundle (● host editors)))
                    ""))
                  ((Err message) (Host-editor-problem-set host message)))))))))

    ;; ---- The editor's assets ----

    ;; Page-relative references are pinned to one complete generation. The
    ;; manifest remains at the stable root, and recovery is keyed by project.

    (define (editor-manifest) (→ Response)
      (new Response (status 200)
           (headers (Cons (new Header (name "Content-Type") (value "application/manifest+json"))
                          (security-headers)))
           (body (string->utf8 (json->string (web-app-manifest "Snail IDE"))))))

    (define (editor-asset (setup Setup) (owner (Mailbox Message)) (path (List String)))
      (→ Response)
      (! mut tasks fs)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (EditorAssets reply))
        (let* ((bundles (mailbox-receive reply)) (latest (list-ref bundles 0)))
          (cond ((root-path? path) (editor-page setup latest))
                (else
                 (match path
                   ((Cons ".snail" (Cons "ide" (Cons id rest)))
                    (match (find (lambda (bundle) (string=? (● bundle id) id)) bundles)
                      ((Some bundle) (editor-file bundle rest))
                      ((None) (refused 404 "no such IDE generation"))))
                   ;; Stable icon links belong to the manifest. Other assets
                   ;; are named by generation, including program.wasm.
                   ((Cons name (Nil))
                    (if (member? name
                                 (list "snail-icon.svg" "snail-icon-192.png" "snail-icon-512.png"))
                        (editor-file latest path) (refused 404 "no such editor asset")))
                   (_ (refused 404 "no such editor asset"))))))))

    (define (editor-page (setup Setup) (bundle EditorBundle)) (→ Response) (! fs)
      (let ((text (stable-web-app
                   (read-file (string-append (● bundle directory) "/index.html")) "/")))
        (new Response
          (status 200)
          (headers (Cons (new Header (name "Content-Type") (value "text/html; charset=utf-8"))
                         (editor-headers)))
          (body (string->utf8
                 (insert-metadata text (list (PageBase (editor-base bundle))
                                             (PageMeta "snail-workspace"
                                                       (● setup project)))))))))

    (define (editor-file (bundle EditorBundle) (path (List String))) (→ Response) (! fs)
      (let ((response (bundle-file (● bundle directory) path)))
        (new Response (status (● response status))
             (headers (append (● response headers) (editor-headers))) (body (● response body)))))

    (define (editor-headers) (→ (List Header))
      (Cons (new Header (name "Content-Security-Policy")
                 (value
                  "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'self'; worker-src 'none'"))
            (security-headers)))

    ;; ---- Writing an event stream ----

    ;; Joins the owner's streams, then writes each frame it sends until it
    ;; sends none, or a write fails. The handler's end tells the owner the
    ;; stream has gone.

    (define (stream-events (owner (Mailbox Message))
                           (id I64)
                           (connection Connection)
                           (watching (Option String)))
      (→ Unit)
      (! mut tasks tcp host)
      (let ((frames (make-mailbox)) (reply (make-mailbox)))
        (mailbox-post owner (Joined id watching connection frames reply))
        (let ((answer (mailbox-receive reply)))
          (if (= (● answer status) 200)
              (match (encode-stream-head 200
                                         (Cons (new Header
                                                 (name "Content-Type")
                                                 (value "text/event-stream"))
                                               (security-headers)))
                ((Ok head) (when (sent? connection head) (write-frames owner id connection frames)))
                ((Err _) (unit)))
              (finish-exchange connection
                               (Some "GET")
                               (json-response (● answer status) (● answer body)))))))

    (define (write-frames (owner (Mailbox Message))
                          (id I64)
                          (connection Connection)
                          (frames (Mailbox (Option Bytes))))
      (→ Unit)
      (! mut tasks tcp host)
      (match (mailbox-receive frames)
        ((Some bytes)
         (if (sent? connection bytes)
             (begin
               (mailbox-post owner (Written id (vector-length bytes)))
               (write-frames owner id connection frames))
             (begin
               (close-connection connection)
               (unit))))
        ((None) (close-connection connection) (unit))))

    (define (sent? (connection Connection) (bytes Bytes)) (→ Bool) (! tasks tcp)
      (if (= (vector-length bytes) 0)
          #t
          (match (write connection bytes)
            ((Ok count)
             (and (> count 0)
                  (sent? connection (subvector bytes (i32->i64 count) (vector-length bytes)))))
            ((Err _) #f))))))
