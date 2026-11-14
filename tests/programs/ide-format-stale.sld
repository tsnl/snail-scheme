(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ui)
 (snail shell ide application))

(record Race
  ((injected Bool)))

;; A DOM edit can precede its input message. Change the live field after
;; formatting was scheduled but before its command runs. Neither replacement
;; nor scroll restoration may act on the obsolete field snapshot.
(define (replace-field (changed-path Bool)) (→ Unit) (! dom)
  (match (new Pair (first (element-by-id "text-0")) (second (element-by-id "editor-0")))
    ((Pair (Some field) (Some scroller))
     (set-string-property field (if changed-path "snailPath" "value")
                          (if changed-path "other.sld" "newer"))
     (set-number-property scroller "scrollTop" 88.0))
    (_ (panic "missing editor")))
  (unit))

(define (race-update (changed-path Bool)
                     (race Race)
                     (model Ide)
                     (message Msg))
  (→ (Pair Ide (List (Fn → Msg ! tasks dom fetch))))
  (! mut dom)
  (let ((next (ui-update model message)))
    ;; The first result applies the named command and queues formatting.
    ;; Change the DOM before that queued task gets its next scheduler turn.
    (when (and (match message ((Finished _) #t) (_ #f)) (not (● race injected)))
      (set! (● race injected) #t)
      (replace-field changed-path))
    next))

(define (report-editor) (→ Unit) (! dom output-port)
  (match (new Pair (first (element-by-id "text-0")) (second (element-by-id "editor-0")))
    ((Pair (Some field) (Some scroller))
     (write-line (string-property field "value"))
     (write-line (show (number-property scroller "scrollTop"))))
    (_ (panic "missing editor"))))

(define (run (changed-path Bool)) (→ Unit) (! mut host output-port tasks)
  (handle fetch
      ((request (lambda (method url headers body)
                  (Ok (new Reply
                        (status 200)
                        (body "{\"text\":\"(a   b)\",\"revision\":\"first\"}")))))
       (stream-open (lambda (url kinds) (panic "stream")))
       (stream-next (lambda (stream) (panic "stream")))
       (stream-close (lambda (stream) (panic "stream"))))
    (let ((loaded (● (with-memory-dom (Nil)
                                      (lambda ()
                                        (run-ui (initial)
                                                (list (Open "main.sld"))
                                                (lambda (model message) (ui-update model message))
                                                (lambda (model) (view model))
                                                (lambda (model) (window model))
                                                (lambda (model) (unit))
                                                (lambda (model) (unit))))) first))
          (race (new Race (injected #f))))
      (with-memory-dom (Nil)
                       (lambda ()
                         (run-ui loaded
                                 (list (DispatchCommand "format-buffer"))
                                 (lambda (model message)
                                   (race-update changed-path race model message))
                                 (lambda (model) (view model))
                                 (lambda (model) (window model))
                                 (lambda (model) (unit))
                                 (lambda (model) (unit)))
                         (report-editor)))
      (unless (● race injected) (panic "the formatting race was not exercised"))
      (unit))))

(define (main) (→ Unit) (! host mut output-port tasks)
  (dispatch (lambda () (run #f) (run #t)))
  (unit))
