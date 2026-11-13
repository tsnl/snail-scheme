(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ide application))

(define (check (ok Bool) (label String)) (→ Unit) (! output-port)
  (if ok (write-line label) (panic label)))

(define (buffer (session Session)) (→ Buffer) (! mut host)
  (match (buffer-at (● session ide) "notes.txt")
    ((Some buffer) buffer)
    ((None) (panic "missing buffer"))))

;; A separate scheduler lets the test cancel queued producers while keeping
;; the session alive to observe abandonment. One turn runs only work that was
;; ready on entry, so a save can be canceled before its HTTP request starts.
(define (step (scheduler Scheduler) (session Session) (message (Option Msg)))
  (→ Unit) (! mut host completion dom fetch)
  (dispatch-in scheduler (once (lambda () (drop (update-session session message)))))
  (tasks-turn scheduler 0)
  (unit))

(define (queue-save (scheduler Scheduler) (session Session))
  (→ Unit) (! mut host completion dom fetch)
  (step scheduler session (Some (DispatchCommand "save-buffer")))
  (tasks-turn scheduler 0)
  (step scheduler session (None)))

(struct RequestState
  ((started Bool)
   (finished Bool)))

(define (main) (→ Unit) (! host mut output-port completion tasks)

  (handle fetch
      ((request (lambda (method url headers body)
                  (if (string=? method "PUT") (panic "canceled save ran")
                      (Ok (Reply 200 "{\"text\":\"disk\",\"revision\":\"initial\"}")))))
       (stream-open (lambda (url kinds) (panic "unexpected stream")))
       (stream-next (lambda (stream) (panic "unexpected stream")))
       (stream-close (lambda (stream) (unit))))
    (drop
     (with-memory-dom
      (Nil)
      (lambda ()
        (let ((scheduler (make-scheduler)) (session (begin-session (initial))))
          (step scheduler session (Some (Open "notes.txt")))
          (tasks-turn scheduler 0)
          (step scheduler session (None))
          (step scheduler session (Some (Typed 0 "draft")))
          (queue-save scheduler session)
          (check (● (buffer session) saving) "save is pending")
          (tasks-close! scheduler)
          (drop (update-session session (None)))
          (check (not (● (buffer session) saving)) "abandonment clears saving")
          (check (string=? (● (buffer session) text) "draft") "abandonment preserves draft")
          (check (not (string=? (● (buffer session) failure) "")) "abandonment reports failure")
          (let ((replacement (make-scheduler)) (alias session))
            (queue-save replacement session)
            (check (● (buffer session) saving) "a later save can start")
            (close-session! alias)
            (close-session! session)
            (tasks-close! replacement)))))))
  ;; Canceling reception withdraws UI authority, not the producer's work.
  ;; A pending request still completes and drops its unobserved result.
  (let ((gate (make-mailbox)) (request-state (RequestState #f #f)))
    (handle fetch
        ((request (lambda (method url headers body)
                    (set! (● request-state started) #t)
                    (mailbox-receive gate)
                    (set! (● request-state finished) #t)
                    (Ok (Reply 200 "{\"text\":\"late\",\"revision\":\"late\"}"))))
         (stream-open (lambda (url kinds) (panic "unexpected stream")))
         (stream-next (lambda (stream) (panic "unexpected stream")))
         (stream-close (lambda (stream) (unit))))
      (drop
       (with-memory-dom
        (Nil)
        (lambda ()
          (let ((session (update-session (begin-session (initial)) (Some (Open "notes.txt")))))
            (yield)
            (check (● request-state started) "request started")
            (close-session! session)
            (mailbox-post gate (unit))
            (yield)
            (check (● request-state finished) "dropped receiver leaves producer running")))))))
  (unit))
