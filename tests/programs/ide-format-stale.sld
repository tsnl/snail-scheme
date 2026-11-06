(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ui)
 (snail shell ide application))

;; A DOM edit can precede its input message. Change the live field after
;; formatting was scheduled but before its command runs. Neither replacement
;; nor scroll restoration may act on the obsolete field snapshot.
(: widened (-> (List (FnOnce Msg ! tasks dom fetch))
               (List (FnOnce Msg ! mut console tasks dom fetch))))
(define (widened commands)
  (match commands
    ((Nil) (Nil))
    ((Cons command rest) (Cons (once (lambda () (command))) (widened rest)))))

(: normal-update (-> Ide Msg (Pair Ide (List (FnOnce Msg ! mut console tasks dom fetch)))))
(define (normal-update model msg)
  (match (update model msg)
    ((Pair next commands) (Pair next (widened commands)))))

(: replace-field (-> Bool Msg ! dom))
(define (replace-field changed-path)
  (match (Pair (element-by-id "text-0") (element-by-id "editor-0"))
    ((Pair (Some field) (Some scroller))
     (set-string-property field (if changed-path "snailPath" "value")
                          (if changed-path "other.sld" "newer"))
     (set-number-property scroller "scrollTop" 88.0))
    (_ (panic "missing editor")))
  (Typed -1 ""))

(: race-update (-> Bool Ide Msg (Pair Ide (List (FnOnce Msg ! mut console tasks dom fetch)))))
(define (race-update changed-path model msg)
  (match (normal-update model msg)
    ((Pair next commands)
     (Pair next (match msg
                  ((InvokeCommand _)
                   (Cons (once (lambda () (replace-field changed-path))) commands))
                  (_ commands))))))

(: report-editor (-> Unit ! dom console))
(define (report-editor)
  (match (Pair (element-by-id "text-0") (element-by-id "editor-0"))
    ((Pair (Some field) (Some scroller))
     (write-line (string-property field "value"))
     (write-line (show (number-property scroller "scrollTop"))))
    (_ (panic "missing editor"))))

(: run (-> Bool Unit ! mut console tasks))
(define (run changed-path)
  (handle fetch
      ((request (lambda (method url headers body)
                  (Ok (Reply 200 "{\"text\":\"(a   b)\",\"revision\":\"first\"}"))))
       (stream-open (lambda (url kinds) (panic "stream")))
       (stream-next (lambda (stream) (panic "stream")))
       (stream-close (lambda (stream) (panic "stream"))))
    (let ((loaded (::first (with-memory-dom (Nil)
                                            (lambda ()
                                              (run-ui initial
                                                      (list (Open "main.sld"))
                                                      normal-update
                                                      view
                                                      window
                                                      (lambda (model) (unit))
                                                      (lambda (model) (unit))))))))
      (with-memory-dom (Nil)
                       (lambda ()
                         (run-ui loaded (list (InvokeCommand "format-buffer"))
                                 (lambda (model msg) (race-update changed-path model msg))
                                 view window (lambda (model) (unit)) (lambda (model) (unit)))
                         (report-editor)))
      (unit))))

(dispatch-local (once (lambda () (run #f) (run #t))))
