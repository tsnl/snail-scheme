;; Both hosts share complete typed snapshots. Malformed required fields
;; refuse the whole message, rather than resetting unrelated client state.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (snail shell project protocol))

(define (accepted? (value (Option T))) (→ Bool) (∀ (T)) (⊨ (Copy T) (Drop (!) T))
  (match value ((Some _) #t) ((None) #f)))

(define (parse (text String)) (→ Json)
  (match (string->json text) ((Some json) json) ((None) (panic "invalid test JSON"))))

(define (state) (→ ServerState)
  (new ServerState (instance "server-λ") (files 9)
       (build (new Build
                (phase "failed")
                (id 3)
                (diagnostics (list (new Report
                                     (severity "error")
                                     (message "unknown λ")
                                     (source
                                      (Some (new Point (file "/p/a.sld") (line 2) (column 4)))))))))
       (runs (list (new Run (target "main") (desired (Some 2))
                        (attempt (Some (new Attempt
                                         (build 2)
                                         (pid (Some 501))
                                         (phase "running")
                                         (code (None))
                                         (signal "")
                                         (error "")
                                         (stdout "hello λ\n")
                                         (stderr ""))))
                        (wanted #t) (available #t))))
       (editor "read-only-generation/")
       (editor-problem "")))

(define (main) (→ Unit) (! output-port)

  (match (read-event (json->string (state->json (state))))
    ((Some received)
     (write-line (show (string=? (json->string (state->json (state)))
                                 (json->string (state->json received))))))
    ((None) (write-line "bad round trip")))
  (write-line (show (accepted? (read-event "{\"instance\":\"s\",\"files\":0}"))))
  (write-line
   (show
    (accepted? (json->project
                (parse
                 "{\"name\":\"p\",\"directory\":\"/p\",\"files\":[1],\"directories\":[]}")))))
  (write-line (show (accepted? (json->file (parse "{\"text\":\"draft\"}")))))
  (write-line
   (show (accepted? (json->build (parse "{\"phase\":\"mystery\",\"id\":1,\"diagnostics\":[]}")))))
  (write-line
   (show (accepted? (json->point (parse "{\"file\":\"/p/a\",\"line\":0,\"column\":1}")))))
  (write-line
   (show
    (accepted?
     (json->run
      (parse
       "{\"target\":\"main\",\"desired\":null,\"attempt\":{},\"wanted\":true,\"available\":true}")))))
  (write-line
   (show (accepted? (json->search (parse "{\"hits\":[],\"skipped\":-1,\"limited\":false}")))))
  (unit))
