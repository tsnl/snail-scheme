(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell fetch)
 (snail shell text search)
 (prefix (snail shell ide search) search-))

(define (run (text String) (query String)) (→ Unit) (! tasks fetch output-port)
  (match (search-run (search-CurrentDraft (search-Draft "draft.sld" text)) query)
    ((Ok (search-DraftResults draft hits limited))
     (for-each (lambda (hit)
                 (write-line
                  (string-append (show (● hit line)) ":" (show (● hit column))
                                 " " (● hit snippet)))) hits)
     (write-line (string-append (show (length hits)) " " (show limited))))
    (_ (panic "draft search failed"))))

(define main
  (lambda ()
    (dispatch-local
     (once (lambda ()
             (handle fetch
                 ((request
                   (lambda (method url headers body) (panic "draft search must not use HTTP")))
                  (stream-open (lambda (url kinds) (panic "stream")))
                  (stream-next (lambda (stream) (panic "stream")))
                  (stream-close (lambda (stream) (panic "stream"))))
               (run "😀 a.*Z\r\nÉb a.*z\rEND" "A.*z")
               (match (search-run (search-CurrentDraft (search-Draft "large" (make-string 205 #\x)))
                                  "x")
                 ((Ok (search-DraftResults _ hits limited))
                  (write-line (string-append (show (length hits)) " " (show limited))))
                 (_ (panic "bounded search")))
               (match (search-run (search-CurrentDraft (search-Draft "draft" "anything"))
                                  "bad\nquery")
                 ((Err _) (write-line "multiline query rejected"))
                 (_ (panic "query accepted")))))))
    (unit)))
