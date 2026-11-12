;; Target discovery: the targets whose files a program asks for, which a
;; build makes before it compiles the program, as the old
;; `discover-artifacts` finds them for the build planner. The program is
;; loaded, and each library in the order loading found them is expanded,
;; handed the offers of the libraries its imports reach, as the compile
;; expands it. No library is bound, so nothing waits on a target, and
;; none is derived, since a derived instance adds no name to an offer. A
;; target asked for in a macro's template that no use expands is not
;; asked for. The planner discovers once every producer the program
;; reaches has run, so a producer's output that is not there is the
;; caller's mistake, and discovery says so.
(define-library (snail compiler integrate discover)
  (export
   discover-targets)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline imports)
   (snail compiler outline names)
   (only (snail compiler expand offer) Offered Expansion Offer)
   (snail compiler expand pass)
   (snail compiler expand targets)
   (snail compiler integrate walk)
   (snail compiler integrate load))
  (begin

    ;; ---- Discovery ----

    ;; Each target the program at `path` asks for, once, at its first
    ;; request in the order the libraries are expanded, and each library's
    ;; in the order written; or the first problem expanding one.
    (: discover-targets
       (impl
        (Fn (List String) String String -> (Result (List TargetRequest) (List Feedback)) ! fs)))
    (define (discover-targets directories generated path)
      (result-let* ((loaded (load-program directories generated path)))
        (match loaded
          ((Complete files)
           (result-let* ((requests (requests-of files (Nil) (Nil))))
             (Ok (delete-duplicates same-target? requests))))
          ((Unproduced _)
           (fail (Loc path 0 0)
                 "internal error: discovery reached a producer whose output was not supplied")))))

    (: same-target? (impl (Fn TargetRequest TargetRequest -> Bool)))
    (define (same-target? request other)
      (string=? (::target request) (::target other)))

    ;; The requests of each of `files` in turn, after `requests`, the
    ;; libraries `done` expanded, latest first.
    (: requests-of
       (impl (Fn (List LoadedFile) (List OfferingLibrary) (List TargetRequest)
                 -> (Result (List TargetRequest) (List Feedback)))))
    (define (requests-of files done requests)
      (match files
        ((Nil) (Ok requests))
        ((Cons loaded rest)
         (let ((imports (map ::library (library-imports (::library loaded)))))
           (result-let* ((expansion (expand (::library loaded) (reached-offers done imports))))
             (requests-of rest
                          (Cons (OfferingLibrary (loaded-name loaded) imports (::offer expansion))
                                done)
                          (append requests (requested-targets (::expanded expansion)))))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-discover)
    (import
     (only (chibi filesystem) create-directory*)
     (snail stage0 testing))
    (begin
      ;; Files are written under `directory`, which the runner supplies.
      (define (test-discover directory)
        (create-directory* (string-append directory "/sample"))
        (for-each
         (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
         (list (Pair "sample/site.sld"
                     (string-append "(define-library (sample site) (import (snail core forms))"
                                    " (export page asks)\n"
                                    "  (begin (define page (artifact-files \"site\" 1 2 3))\n"
                                    "         (define-syntax asks (syntax-rules () ((_ t) (artifact-files t 1 2 3))))\n"
                                    "         (define-syntax unused (syntax-rules () ((_) (artifact-files \"never\" 1 2 3))))))"))
               (Pair "sample/docs.sld"
                     (string-append
                      "(define-library (sample docs) (import (snail core forms) (sample site))"
                      " (export manual)\n"
                      "  (begin (define manual (asks \"docs\")) (define again (asks \"site\"))))"))
               (Pair "main.sld"
                     "(import (snail core forms) (sample docs) (sample site))\n(asks \"admin\")\n(asks \"docs\")")
               (Pair "broken.sld" "(import (snail core forms) (sample site))\n(bogus)")
               (Pair "sample/made.sld" "(generate-library (sample made) (import) (make))")
               (Pair "unproduced.sld" "(import (sample made))")))
        (let ((main (string-append directory "/main.sld"))
              (site (string-append directory "/sample/site.sld"))
              (docs (string-append directory "/sample/docs.sld")))
          ;; Each target once, at its first request, a library's before
          ;; those of its importers; a macro's use asks where it is used.
          (expect (discovered directory "main.sld")
                  (Ok (list (TargetRequest "site" (Loc site 2 23))
                            (TargetRequest "docs" (Loc docs 2 25))
                            (TargetRequest "admin" (Loc main 2 1)))))
          (expect (discovered directory "broken.sld")
                  (fail (Loc (string-append directory "/broken.sld") 2 2)
                        "unbound identifier bogus"))
          (expect (discovered directory "unproduced.sld")
                  (fail (Loc (string-append directory "/unproduced.sld") 0 0)
                        "internal error: discovery reached a producer whose output was not supplied"))))

      (define (discovered directory file)
        (discover-targets (list directory)
                          (string-append directory "/generated")
                          (string-append directory "/" file)))))
   (else)))
