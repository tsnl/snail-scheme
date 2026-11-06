;; Search saved project files on the service or the exact current draft here.
;; A draft result carries its text, never an invented saved-file revision.
(define-library (snail shell ide search)
  (export Draft Draft-path Draft-text Source SavedProject CurrentDraft
          Results SavedResults DraftResults run same-draft?)
  (import
   (snail core base)
   (snail shell task)
   (snail shell fetch)
   (snail shell project client)
   (snail shell project protocol)
   (snail shell text search))
  (begin

    ;; ---- Sources and results ----

    (struct Draft
      ((path String)
       (text String)))

    (enum Source
      (SavedProject)
      (CurrentDraft ((draft Draft))))

    (enum Results
      (SavedResults ((results SearchResults)))
      (DraftResults ((draft Draft)
                     (hits (List Occurrence))
                     (limited Bool))))

    (: same-draft? (-> Draft Draft Bool))
    (define (same-draft? first second)
      (and (string=? (Draft-path first) (Draft-path second))
           (string=? (Draft-text first) (Draft-text second))))

    ;; ---- Searching ----

    (: run (-> Source String (Result Results Failure) ! tasks fetch))
    (define (run source text)
      (match (parse-query text)
        ((Err message) (Err (Failure 400 message)))
        ((Ok query)
         (match source
           ((SavedProject)
            (match (search-reply
                    (api "GET" (string-append "/api/search?q=" (url-component text)) (Nil) ""))
              ((Ok results) (Ok (SavedResults results)))
              ((Err failure) (Err failure))))
           ((CurrentDraft draft) (Ok (search-draft draft query)))))))

    (: search-draft (-> Draft Query Results ! tasks))
    (define (search-draft draft query)
      (let* ((text (Draft-text draft))
             (end (min 4000000 (string-length text)))
             (hits (scan query text end 201)))
        (DraftResults draft (take hits 200)
                      (or (> (length hits) 200) (< end (string-length text))))))))
