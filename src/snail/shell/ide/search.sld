;; Search saved project files on the service or the exact current draft here.
;; A draft result carries its text, never an invented saved-file revision.
(define-library (snail shell ide search)
  (export Draft Source SavedProject CurrentDraft
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

    (record Draft
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

    (define (same-draft? (first Draft) (second Draft)) (→ Bool)
      (and (string=? (● first path) (● second path))
           (string=? (● first text) (● second text))))

    ;; ---- Searching ----

    (define (run (source Source) (text String)) (→ (Result Results Failure)) (! tasks fetch)
      (match (parse-query text)
        ((Err message) (Err (new Failure (status 400) (message message))))
        ((Ok query)
         (match source
           ((SavedProject)
            (match (search-reply
                    (api "GET" (string-append "/api/search?q=" (url-component text)) (Nil) ""))
              ((Ok results) (Ok (SavedResults results)))
              ((Err failure) (Err failure))))
           ((CurrentDraft draft) (Ok (search-draft draft query)))))))

    (define (search-draft (draft Draft) (query Query)) (→ Results) (! tasks)
      (let* ((text (● draft text))
             (end (min 4000000 (string-length text)))
             (hits (scan query text end 201)))
        (DraftResults draft (take hits 200)
                      (or (> (length hits) 200) (< end (string-length text))))))))
