;; What `bind` needs to bind a library, found in what the build supplied,
;; and what a miss means. The queries over Expanded say what the library
;; asks for: the targets whose files it lists and the files it links. A
;; target the build did not supply is no failure of the program: the
;; library waits for it, as the old compiler asks its caller for an input.
;; Two links of one path that name different files, and a linked file the
;; build found no file for, are the old expander's problems, with its
;; messages and places. `bind` asks in the old expander's order, which
;; asks for a target and finds two links clashing while it expands the
;; body, and reads the linked files once the body is done.
(define-library (snail compiler bind needs)
  (export
   TargetsFound
   Supplied
   Unsupplied
   TargetFiles
   FoundLink
   targets-supplied
   found-links)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) library-key)
   (snail compiler expand links)
   (only (snail compiler expand targets) TargetRequest)
   (snail compiler bind supply)
   (snail compiler bind linked))
  (begin

    ;; ---- Targets ----

    ;; The files of a target the library asks for.
    (struct TargetFiles
      ((target String)
       (files (List TargetFile))))

    (enum TargetsFound
      (Supplied
       ((targets (List TargetFiles))))
      (Unsupplied
       ((requests (List TargetRequest)))))

    ;; The files of each target `requests` names, when the build supplied
    ;; every one; else each request it did not supply, in order.
    (: targets-supplied (impl (Fn (List TargetRequest) (Table (List TargetFile)) -> TargetsFound)))
    (define (targets-supplied requests supplied)
      (let loop ((requests requests)
                 (found (Nil))
                 (missing (Nil)))
        (match requests
          ((Nil) (if (null? missing) (Supplied (reverse found)) (Unsupplied (reverse missing))))
          ((Cons request rest)
           (match (table-ref supplied (::target request))
             ((Some files) (loop rest (Cons (TargetFiles (::target request) files) found) missing))
             ((None) (loop rest found (Cons request missing))))))))

    ;; ---- Linked files ----

    ;; A file the library links: its path as written, the digest of the
    ;; file it names, that file, and where the library first writes it.
    (struct FoundLink
      ((path (List String))
       (digest String)
       (file String)
       (loc Loc)))

    ;; Each path `links` write, once, in the order first written and at
    ;; that place, with the digest of the file it names. Two links of one
    ;; path that name different files fail first, at the second; then the
    ;; first path whose file has no digest fails, where it is first written.
    (: found-links
       (impl (Fn LibraryName (Option PrintedCopy) (List Link) (Table String)
                 -> (Result (List FoundLink) (List Feedback)))))
    (define (found-links name printed links digests)
      (result-let* ((requests (link-requests printed links)))
        (map-results (lambda (request) (found-link name request digests)) requests)))

    ;; A path a library links: the file it names, and where the library
    ;; first writes it.
    (struct LinkRequest
      ((path (List String))
       (file String)
       (loc Loc)))

    ;; Two links of one path may name different files, as a macro's
    ;; template beside another library and a use beside this one do.
    (: link-requests
       (impl (Fn (Option PrintedCopy) (List Link) -> (Result (List LinkRequest) (List Feedback)))))
    (define (link-requests printed links)
      (let loop ((links links)
                 (requests (Nil)))
        (match links
          ((Nil) (Ok (reverse requests)))
          ((Cons link rest)
           (result-let* ((more (with-request requests
                                             (LinkRequest (::path link)
                                                          (linked-file printed link)
                                                          (::written link)))))
             (loop rest more))))))

    ;; `requests`, latest first, with `request` among them once.
    (: with-request
       (impl (Fn (List LinkRequest) LinkRequest -> (Result (List LinkRequest) (List Feedback)))))
    (define (with-request requests request)
      (match (find (lambda (other) (same-link-path? (::path other) (::path request))) requests)
        ((None) (Ok (Cons request requests)))
        ((Some other)
         (if (string=? (::file other) (::file request))
             (Ok requests)
             (fail (::loc request)
                   (string-append "two files link as "
                                  (path-text (::path request))
                                  ": "
                                  (::file other)
                                  " and "
                                  (::file request)))))))

    (: found-link
       (impl (Fn LibraryName LinkRequest (Table String) -> (Result FoundLink (List Feedback)))))
    (define (found-link name request digests)
      (match (table-ref digests (::file request))
        ((Some digest) (Ok (FoundLink (::path request) digest (::file request) (::loc request))))
        ((None)
         (fail (::loc request)
               (string-append "the library "
                              (library-key name)
                              " links "
                              (path-text (::path request))
                              ", but there is no file at "
                              (::file request))))))

    ;; A linked path as the old expander's messages write it.
    (: path-text (impl (Fn (List String) -> String)))
    (define (path-text path)
      (string-join path "/"))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-needs)
    (import
     (snail stage0 testing))
    (begin
      (define (test-needs)
        (test-targets)
        (test-requests)
        (test-found))

      (define (at file column)
        (Loc file 1 column))

      (define (bytes text)
        (list->vector (map (lambda (char) (i32->u8 (i64->i32 (char->integer char))))
                           (string->list text))))

      ;; A target the build supplied is found, by name; any it did not is
      ;; asked for, in the order requested, and nothing is found.
      (define (test-targets)
        (let ((supplied (table-set empty-table "site" (list (TargetFile "a" (bytes "A")))))
              (site (TargetRequest "site" (at "a.sld" 1)))
              (docs (TargetRequest "docs" (at "a.sld" 2)))
              (api (TargetRequest "api" (at "a.sld" 3))))
          (expect (targets-supplied (list) supplied) (Supplied (list)))
          (expect (targets-supplied (list site) supplied)
                  (Supplied (list (TargetFiles "site" (list (TargetFile "a" (bytes "A")))))))
          (expect (targets-supplied (list docs site api) supplied) (Unsupplied (list docs api)))))

      ;; A path is asked for once however many links write it, at the
      ;; first; a printed copy's links name files beside its recipe. Two
      ;; links of one path that name different files are a problem.
      (define (test-requests)
        (let ((copy (Some (PrintedCopy "build/p.sld" "lib/r.sld")))
              (link (lambda (path file column) (Link path (at file column)))))
          (expect (link-requests (None)
                                 (list (link (list "x.bin") "lib/main.sld" 1)
                                       (link (list "d" "y.bin") "lib/main.sld" 2)
                                       (link (list "x.bin") "lib/main.sld" 3)))
                  (Ok (list (LinkRequest (list "x.bin") "lib/x.bin" (at "lib/main.sld" 1))
                            (LinkRequest (list "d" "y.bin") "lib/d/y.bin" (at "lib/main.sld" 2)))))
          (expect (link-requests copy
                                 (list (link (list "x.bin") "build/p.sld" 1)
                                       (link (list "y.bin") "other/m.sld" 2)))
                  (Ok (list (LinkRequest (list "x.bin") "lib/x.bin" (at "build/p.sld" 1))
                            (LinkRequest (list "y.bin") "other/y.bin" (at "other/m.sld" 2)))))
          (expect (link-requests (None)
                                 (list (link (list "x.bin") "other/m.sld" 1)
                                       (link (list "x.bin") "lib/main.sld" 2)))
                  (fail (at "lib/main.sld" 2)
                        "two files link as x.bin: other/x.bin and lib/x.bin"))))

      ;; Each path takes its file's digest; the first whose file has none
      ;; fails the library, naming it and the path. A clash is found
      ;; before a missing file, wherever each is written.
      (define (test-found)
        (let ((links (list (Link (list "a.txt") (at "lib/m.sld" 1))
                           (Link (list "d" "b.txt") (at "lib/m.sld" 2))))
              (digests (table-set empty-table "lib/a.txt" "aa")))
          (expect (found-links (list "sample" "m")
                               (None)
                               links
                               (table-set digests "lib/d/b.txt" "bb"))
                  (Ok (list (FoundLink (list "a.txt") "aa" "lib/a.txt" (at "lib/m.sld" 1))
                            (FoundLink (list "d" "b.txt") "bb" "lib/d/b.txt" (at "lib/m.sld" 2)))))
          (expect (found-links (list "sample" "m") (None) links digests)
                  (fail (at "lib/m.sld" 2)
                        "the library sample.m links d/b.txt, but there is no file at lib/d/b.txt"))
          (expect (found-links (list "sample" "m")
                               (None)
                               (append links (list (Link (list "a.txt") (at "other/n.sld" 3))))
                               digests)
                  (fail (at "other/n.sld" 3)
                        "two files link as a.txt: lib/a.txt and other/a.txt"))))))
   (else)))
