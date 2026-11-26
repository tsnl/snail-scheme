;; A publisher serves resources.json and immutable objects beside it. The
;; application chooses which named files to acquire and owns its loading UI.
(define-library (snail shell static-resource)
  (export StaticFile
          StaticBody
          StaticResources
          StaticProgress
          resource-digest?
          fetch-catalog
          acquire-files)
  (import
   (snail core base)
   (only (snail shell compiler blob) blob-digest?)
   (snail core table)
   (snail shell fetch)
   (snail shell json)
   (snail shell json read))
  (begin

    ;; ---- The published catalog ----

    (record StaticFile
      ((name String)
       (digest String)
       (size I64)))

    (define (resource-digest? (text String)) (→ Bool)
      (blob-digest? text))

    (define (catalog-entry (name String) (value Json)) (→ (Result StaticFile String))
      (match (list (json-member value "sha256") (json-member value "size"))
        ((Cons (Some (JsonString digest)) (Cons (Some (JsonInteger size)) (Nil)))
         (if (and (resource-digest? digest) (>= size 0) (<= size 2147483647))
             (Ok (new StaticFile (name name) (digest digest) (size size)))
             (Err (string-append "invalid digest or byte length for " name))))
        (_ (Err (string-append "missing digest or byte length for " name)))))

    (define (catalog-files (members (List (Pair String Json))))
      (→ (Result (List StaticFile) String))
      (let loop ((left members) (files (Nil)) (names (empty-table)) (sizes (empty-table)))
        (match left
          ((Nil) (Ok (reverse files)))
          ((Cons (Pair name value) rest)
           (match (catalog-entry name value)
             ((Err why) (Err why))
             ((Ok file)
              (cond ((table-contains? names name) (Err (string-append "duplicate resource " name)))
                    ((match (table-ref sizes (● file digest))
                       ((Some size) (not (= size (● file size)))) ((None) #f))
                     (Err (string-append "conflicting byte lengths for " name)))
                    (else (loop rest (Cons file files) (table-set names name #t)
                                (table-set sizes (● file digest) (● file size)))))))))))

    (define (fetch-catalog (fetch Fetch) (url String)) (→ (Result (List StaticFile) String))
      (match ((● fetch request) "GET" url (Nil) "")
        ((Err why) (Err why))
        ((Ok reply)
         (if (and (>= (● reply status) 200) (< (● reply status) 300))
             (match (string->json (● reply body))
               ((Some (JsonObject members)) (catalog-files members))
               (_ (Err (string-append "invalid static resource catalog at " url))))
             (Err (string-append "HTTP " (show (● reply status)) " fetching " url))))))

    ;; ---- Acquiring files ----

    (record StaticBody
      ((bytes Bytes)
       (cached Bool)))

    ;; read receives the catalog URL, a file, and the count of decoded body
    ;; bytes received so far. Its result has passed the size and digest checks.
    (record StaticResources
      ((read (Fn String StaticFile (Fn I64 → Unit) → (Result StaticBody String)))))

    (record StaticProgress
      ((downloaded I64)
       (cached I64)
       (total I64)))

    ;; Keep request order. Two names for one digest share both its transfer and
    ;; its byte array. Large catalogs can contain thousands of such aliases.
    (define (distinct-files (files (List StaticFile))) (→ (List StaticFile))
      (let loop ((left files) (seen (empty-table)) (kept (Nil)))
        (match left
          ((Nil) (reverse kept))
          ((Cons file rest)
           (let ((digest (● file digest)))
             (if (table-contains? seen digest) (loop rest seen kept)
                 (loop rest (table-set seen digest #t) (Cons file kept))))))))

    (define (named-bytes (files (List StaticFile)) (objects (Table Bytes))) (→ (Table Bytes))
      (fold-left (lambda (by-name f)
                   (match (table-ref objects (● f digest))
                     ((Some bytes) (table-set by-name (● f name) bytes))
                     ((None) (panic "acquired object missing"))))
                 (empty-table) files))

    (define (acquire-files (store StaticResources) (catalog String) (files (List StaticFile))
                           (progress (Fn StaticProgress → Unit)))
      (→ (Result (Table Bytes) String))
      (let* ((unique (distinct-files files))
             (total (fold-left (lambda (n f) (+ n (● f size))) 0 unique))
             (report (lambda (net local)
                       (progress
                        (new StaticProgress (downloaded net) (cached local) (total total))))))
        (report 0 0)
        (let loop ((left unique) (objects (empty-table)) (net 0) (local 0))
          (match left
            ((Nil) (Ok (named-bytes files objects)))
            ((Cons file rest)
             (match ((● store read) catalog file (lambda (n) (report (+ net n) local)))
               ((Err why) (Err (string-append (● file name) ": " why)))
               ((Ok body)
                (let ((n (+ net (if (● body cached) 0 (● file size))))
                      (c (+ local (if (● body cached) (● file size) 0))))
                  (report n c)
                  (loop rest (table-set objects (● file digest) (● body bytes)) n c)))))))))))
