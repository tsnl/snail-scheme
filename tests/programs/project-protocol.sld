;; Both hosts share complete typed snapshots. Malformed required fields
;; refuse the whole message, rather than resetting unrelated client state.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (snail shell project protocol))

(: accepted? (All (T) (requires (Copy T)) (-> (Option T) Bool)))
(define (accepted? value)
  (match value ((Some _) #t) ((None) #f)))

(: parse (-> String Json))
(define (parse text)
  (match (string->json text) ((Some json) json) ((None) (panic "invalid test JSON"))))

(: state ServerState)
(define state
  (ServerState "server-λ" 9
               (Build "failed" 3 (list (Report "error" "unknown λ" (Some (Point "/p/a.sld" 2 4)))))
               (list (Run "main" (Some 2)
                          (Some (Attempt 2 (Some 501) "running" (None) "" "" "hello λ\n" ""))
                          #t #t))))

(match (read-event (json->string (state->json state)))
  ((Some received)
   (write-line (show (string=? (json->string (state->json state))
                               (json->string (state->json received))))))
  ((None) (write-line "bad round trip")))
(write-line (show (accepted? (read-event "{\"instance\":\"s\",\"files\":0}"))))
(write-line
 (show
  (accepted? (json->project
              (parse "{\"name\":\"p\",\"directory\":\"/p\",\"files\":[1],\"directories\":[]}")))))
(write-line (show (accepted? (json->file (parse "{\"text\":\"draft\"}")))))
(write-line
 (show (accepted? (json->build (parse "{\"phase\":\"mystery\",\"id\":1,\"diagnostics\":[]}")))))
(write-line (show (accepted? (json->point (parse "{\"file\":\"/p/a\",\"line\":0,\"column\":1}")))))
(write-line
 (show
  (accepted?
   (json->run
    (parse
     "{\"target\":\"main\",\"desired\":null,\"attempt\":{},\"wanted\":true,\"available\":true}")))))
(write-line
 (show (accepted? (json->search (parse "{\"hits\":[],\"skipped\":-1,\"limited\":false}")))))
