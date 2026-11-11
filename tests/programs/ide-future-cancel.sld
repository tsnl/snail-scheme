(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ide application))

(define (check (ok Bool) (label String)) (→ Unit) (! console)
  (if ok (write-line label) (panic label)))

(define (buffer (session (Borrow Session))) (→ Buffer)
  (match (buffer-at (::ide session) "notes.txt")
    ((Some buffer) buffer)
    ((None) (panic "missing buffer"))))

(define (send (session Session) (message Msg)) (→ Session) (! mut completion dom fetch)
  (update-session session (Some message)))

;; Cancel a save before it starts. The abandoned future must clear saving,
;; preserve the draft, report the uncertain outcome and permit a new save.
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
      (let ((session (send (begin-session initial) (Open "notes.txt"))))
        (yield)
        (let* ((session (update-session session (None)))
               (session (send session (Typed 0 "draft")))
               (session (send session (DispatchCommand "save-buffer"))))
          (yield)
          (let ((session (update-session session (None))))
            (with-borrow (read session)
                         (check (::saving (buffer read)) "save is pending"))
            (tasks-close!)
            (let ((session (update-session session (None))))
              (with-borrow (read session)
                           (check (not (::saving (buffer read))) "abandonment clears saving")
                           (check (string=? (::text (buffer read)) "draft")
                                  "abandonment preserves draft")
                           (check (not (string=? (::failure (buffer read)) ""))
                                  "abandonment reports failure"))
              (let ((session (send session (DispatchCommand "save-buffer"))))
                (yield)
                (let ((session (update-session session (None))))
                  (with-borrow (read session)
                               (check (::saving (buffer read)) "a later save can start"))
                  (drop session)
                  (tasks-close!)))))))))))

;; Dropping the receiver withdraws UI authority, not external work. A
;; suspended request still completes under its own task and loses its result.
(let ((gate (make-mailbox)) (started (ref #f)) (finished (ref #f)))
  (handle fetch
      ((request (lambda (method url headers body)
                  (ref-set! started #t)
                  (mailbox-receive gate)
                  (ref-set! finished #t)
                  (Ok (Reply 200 "{\"text\":\"late\",\"revision\":\"late\"}"))))
       (stream-open (lambda (url kinds) (panic "unexpected stream")))
       (stream-next (lambda (stream) (panic "unexpected stream")))
       (stream-close (lambda (stream) (unit))))
    (drop
     (with-memory-dom
      (Nil)
      (lambda ()
        (let ((session (send (begin-session initial) (Open "notes.txt"))))
          (yield)
          (check (ref-get started) "request started")
          (drop session)
          (mailbox-post gate (unit))
          (yield)
          (check (ref-get finished) "dropped receiver leaves producer running")))))))
