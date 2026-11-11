;; The reload client: the part of a page that `snail dev` adds
;; ((snail shell project bundle)). It compares the manifest of the build
;; the page runs with the one each of the server's events carries, and
;; decides what the page does: fetch a style sheet again, relink the
;; program from the first module that changed or links a file that did,
;; reload the page, or show a notice. It runs as WebAssembly; the page
;; (host/browser/reload.mjs) passes it the
;; page's manifest and each event, a character at a time, and
;; host/browser/reload-client.mjs performs the `page` effect's commands.
(import
 (snail core base)
 (snail shell datum)
 (snail shell read)
 (snail shell write))

;; ---- Page commands ----

;; A command is a name with string arguments, sent a character at a time,
;; and a number.
(effect page
  ((argument-character (dyn (Fn Char → Unit)))
   (argument-end (dyn (Fn → Unit)))
   (command (dyn (Fn I32 → I32))))
  (default
    ((argument-character host-argument-character)
     (argument-end host-argument-end)
     (command host-command))))

(extern host-argument-character "snail.page" "argument-character" (impl (Fn Char → Unit)))
(extern host-argument-end "snail.page" "argument-end" (impl (Fn → Unit)))
(extern host-command "snail.page" "command" (impl (Fn I32 → I32)))

(define (page-command (name String) (arguments (List String)) (number I32)) (→ Unit) (! page)
  (for-each send-argument (Cons name arguments))
  (command number)
  (unit))

(define (send-argument (text String)) (→ Unit) (! page)
  (let loop ((index 0))
    (when (< index (string-length text))
      (argument-character (string-ref text index))
      (loop (+ index 1))))
  (argument-end))

;; The commands, as host/browser/reload-client.mjs names them. A notice is
;; lasting, a failure, or brief.
(define lasting (→ I32) 0)

(define failure (→ I32) 1)

(define brief (→ I32) 2)

(define (notice! (text String) (kind I32)) (→ Unit) (! page)
  (page-command "notice" (list text) kind))

(define (hide!) (→ Unit) (! page)
  (page-command "hide" (Nil) 0))

;; Fetches a style sheet again, with its digest, from `base`, the build it
;; now belongs to.
(define (restyle! (file String) (digest String) (base String)) (→ Unit) (! page)
  (page-command "restyle" (list file digest base) 0))

;; Relinks the program from `module`, by the modules.json under `base`,
;; with a fresh state when `fresh`; the page reports how it went.
(define (relink! (module String) (base String) (fresh Bool)) (→ Unit) (! page)
  (page-command "relink" (list module (string-append base "modules.json")) (if fresh 1 0)))

;; Stores every application's save, then reloads the page.
(define (reload-page!) (→ Unit) (! page)
  (page-command "reload" (Nil) 0))

;; Shows a failure with a button that calls `reload_start_over`.
(define (offer-fresh-start! (text String)) (→ Unit) (! page)
  (page-command "offer-fresh-start" (list text) 0))

;; ---- Manifests ----

;; What a build serves: the base its files are served under, each file with
;; a digest, and each module, in program order, with the digest of its
;; bytes.
(struct Manifest
  ((base String)
   (files (List (Pair String String)))
   (modules (List (Pair String String)))))

(enum Event
  (Building ((manifest Manifest)))
  (Built ((milliseconds String) (manifest Manifest)))
  (Failed ((message String) (manifest Manifest))))

;; `(base BASE) (files (NAME DIGEST) ...) (modules (NAME DIGEST) ...)`.
(define (parse-manifest (data (List Any))) (→ Manifest)
  (match data
    ((Cons base (Cons files (Cons modules (Nil))))
     (Manifest (base-of base) (string-pairs files) (string-pairs modules)))
    (_ (panic "reload: a manifest is (base ...) (files ...) (modules ...)"))))

(define (base-of (datum Any)) (→ String)
  (match (datum->list datum)
    ((Some (Cons tag (Cons base (Nil))))
     (match (Pair (try-convert tag Symbol) (try-convert base String))
       ((Pair (Ok (Symbol "base")) (Ok base)) base)
       (_ (panic "reload: expected (base BASE)"))))
    (_ (panic (string-append "reload: expected (base BASE), got " (datum->string datum))))))

(define (string-pairs (datum Any)) (→ (List (Pair String String)))
  (match (datum->list datum)
    ((Some (Cons _ entries)) (map string-pair entries))
    (_ (panic "reload: expected a list of pairs"))))

(define (string-pair (datum Any)) (→ (Pair String String))
  (match (datum->list datum)
    ((Some (Cons name (Cons value (Nil))))
     (match (Pair (try-convert name String) (try-convert value String))
       ((Pair (Ok name) (Ok value)) (Pair name value))
       (_ (panic "reload: expected string NAME and VALUE"))))
    (_ (panic (string-append "reload: expected (NAME VALUE), got " (datum->string datum))))))

;; `(building MANIFEST)`, `(built MILLISECONDS MANIFEST)` or
;; `(failed MESSAGE MANIFEST)`.

(define (parse-event (text String)) (→ Event)
  (match (read-datums text)
    ((Ok (Cons event (Nil)))
     (match (datum->list event)
       ((Some (Cons tag rest))
        (match-any tag
                   ((Symbol (Symbol name)) (event-body name rest))
                   (else (panic "reload: an event tag must be a symbol"))))
       (_ (panic (string-append "reload: an unknown event " text)))))
    (_ (panic (string-append "reload: an unreadable event " text)))))

(define (event-body (name String) (rest (List Any))) (→ Event)
  (if (string=? name "building") (Building (parse-manifest rest))
      (match rest
        ((Cons value manifest)
         (cond ((string=? name "built")
                (Built (datum->display-string value) (parse-manifest manifest)))
               ((string=? name "failed")
                (match-any value
                           ((String message) (Failed message (parse-manifest manifest)))
                           (else (panic "reload: expected a failure message"))))
               (else (panic (string-append "reload: unknown event " name)))))
        (_ (panic "reload: expected event payload")))))

(define (parse-page-manifest (text String)) (→ Manifest)
  (match (read-datums text)
    ((Ok data) (parse-manifest data))
    ((Err message) (panic (string-append "reload: " message)))))

(define (same-manifest? (a Manifest) (b Manifest)) (→ Bool)
  (and (same-pairs? (::files a) (::files b))
       (same-pairs? (::modules a) (::modules b))))

(define (same-pairs? (a (List (Pair String String))) (b (List (Pair String String)))) (→ Bool)
  (and (= (length a) (length b))
       (every? (lambda (pair)
                 (and (string=? (::first (::first pair)) (::first (::second pair)))
                      (string=? (::second (::first pair)) (::second (::second pair)))))
               (zip a b))))

(define (event-manifest (event Event)) (→ Manifest)
  (match event
    ((Building manifest) manifest)
    ((Built _ manifest) manifest)
    ((Failed _ manifest) manifest)))

;; ---- Changes ----

;; The files whose digests differ, including files only one side has.
(define (changed-files (old Manifest) (new Manifest)) (→ (List String))
  (delete-duplicates string=?
                     (append (differing (::files old) (::files new))
                             (differing (::files new) (::files old)))))

(define (differing (these (List (Pair String String))) (those (List (Pair String String))))
  (→ (List String))
  (map ::first (filter (lambda (entry) (match (assoc-ref those (::first entry))
                                         ((Some digest)
                                          (not (string=? digest (::second entry))))
                                         ((None) #t)))
                       these)))

;; The first module, in program order, whose digest differs; the modules
;; before it cannot import from it, so they stay linked. A module's bytes
;; name the digest of each file it links, so editing a linked file changes
;; the module that links it.
(define (first-changed-module (old Manifest) (new Manifest)) (→ (Option String))
  (let loop ((old (::modules old)) (new (::modules new)))
    (match new
      ((Cons (Pair name digest) rest)
       (match old
         ((Cons (Pair old-name old-digest) old-rest)
          (if (and (string=? name old-name) (string=? digest old-digest))
              (loop old-rest rest)
              (Some name)))
         ((Nil) (Some name))))
      ((Nil) (None)))))

;; A style sheet is fetched again in place; any other file changes the
;; page, which must load again. Modules and linked files are named for
;; their contents, so the build reports neither.
(define (style-sheet? (file String)) (→ Bool)
  (let ((length (string-length file)))
    (and (> length 4) (string=? (substring file (- length 4) length) ".css"))))

;; ---- Decisions ----

;; `loaded` is the manifest of what the page runs, which changes only when a
;; relink succeeds. While one is in flight, `relinking` holds its target and
;; `pending` the latest event since, which waits for it. `refused` is a
;; target whose program could not take over the state, so it is not tried
;; again until the developer starts over.
(define loaded (→ (Ref Manifest)) (ref (Manifest "" (Nil) (Nil))))

(define relinking (→ (Ref (Option Manifest))) (ref (None)))

(define pending (→ (Ref (Option Event))) (ref (None)))

(define refused (→ (Ref (Option Manifest))) (ref (None)))

(define last-time (→ (Ref String)) (ref ""))

(define (receive! (event Event)) (→ Unit) (! mut page)
  (remember-time! event)
  (match (ref-get relinking)
    ((Some _) (ref-set! pending (Some event)))
    ((None) (apply-event! event))))

(define (apply-event! (event Event)) (→ Unit) (! mut page)
  (let* ((manifest (event-manifest event)) (files (changed-files (ref-get loaded) manifest)))
    (cond ((refused? manifest) (unit))
          ((any? (lambda (file) (not (style-sheet? file))) files) (reload-page!))
          (else (for-each (lambda (file)
                            (restyle! file (digest-of manifest file) (::base manifest)))
                          (filter style-sheet? files))
                (match (first-changed-module (ref-get loaded) manifest)
                  ((Some module)
                   (ref-set! relinking (Some manifest))
                   (relink! module (::base manifest) #f))
                  ((None) (ref-set! loaded manifest) (show! event (not (null? files)))))))))

(define (refused? (manifest Manifest)) (→ Bool) (! mut)
  (match (ref-get refused)
    ((Some target) (same-manifest? target manifest))
    ((None) #f)))

(define (digest-of (manifest Manifest) (file String)) (→ String)
  (match (assoc-ref (::files manifest) file)
    ((Some digest) digest)
    ((None) "")))

(define (remember-time! (event Event)) (→ Unit) (! mut)
  (match event
    ((Built milliseconds _) (ref-set! last-time milliseconds))
    (_ (unit))))

(define (show! (event Event) (changed Bool)) (→ Unit) (! mut page)
  (match event
    ((Building _) (notice! "Building..." lasting))
    ((Built _ _) (if changed (notice! (reloaded) brief) (hide!)))
    ((Failed message _) (notice! message failure))))

(define (reloaded) (→ String) (! mut)
  (string-append "Reloaded, built in " (ref-get last-time) " ms"))

;; A relink that failed leaves the old program running; starting over with
;; the new one is the developer's choice. Either way, the event that waited
;; is applied next.
(define (relinked! (ok Bool) (message String)) (→ Unit) (! mut page)
  (match (ref-get relinking)
    ((Some target)
     (ref-set! relinking (None))
     (if ok
         (begin (ref-set! loaded target) (ref-set! refused (None)) (notice! (reloaded) brief))
         (begin (ref-set! refused (Some target))
                (offer-fresh-start!
                 (string-append
                  "The new program could not take over the running state; the old one is still running.\n\n"
                  message)))))
    ((None) (unit)))
  (apply-pending!))

(define (apply-pending!) (→ Unit) (! mut page)
  (match (ref-get pending)
    ((Some event) (ref-set! pending (None)) (receive! event))
    ((None) (unit))))

;; Relinks the refused program from its first module with a fresh state.
(define (start-over!) (→ Unit) (! mut page)
  (match (Pair (ref-get refused) (ref-get relinking))
    ((Pair (Some target) (None))
     (match (::modules target)
       ((Cons (Pair first _) _)
        (ref-set! relinking (Some target))
        (relink! first (::base target) #t))
       ((Nil) (unit))))
    (_ (unit))))

;; An uncaught error in the page, such as a trap, with the lines the
;; program last wrote to standard error. A trap during a display frame
;; stops the clock with the state from before it; the next build that
;; relinks the program resumes it.
(define (page-error! (message String) (stopped Bool)) (→ Unit) (! page)
  (notice! (if stopped
               (string-append message
                              "\n\nThe application stopped. Fix it and save: the next build resumes from the state before the trap.")
               message)
           failure))

;; ---- Entry points ----

(define input (→ (Ref (List Char))) (ref (Nil)))

(define (take-input) (→ String) (! mut)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    text))

(define (reload-character (code I32)) (→ Unit) (! mut)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

;; The page's own manifest first, then each event; the page reports each
;; relink, with its error, each uncaught error, with whether the clock
;; stopped, and the developer's choice to start over.
(define (reload-start) (→ Unit) (! mut)
  (ref-set! loaded (parse-page-manifest (take-input))))

(define (reload-event) (→ Unit) (! mut page)
  (receive! (parse-event (take-input))))

(define (reload-relinked (status I32)) (→ Unit) (! mut page)
  (relinked! (= status 0) (take-input)))

(define (reload-page-error (stopped I32)) (→ Unit) (! mut page)
  (page-error! (take-input) (not (= stopped 0))))

(define (reload-start-over) (→ Unit) (! mut page)
  (start-over!))

(expose reload-character "reload_character")
(expose reload-start "reload_start")
(expose reload-event "reload_event")
(expose reload-relinked "reload_relinked")
(expose reload-page-error "reload_page_error")
(expose reload-start-over "reload_start_over")
