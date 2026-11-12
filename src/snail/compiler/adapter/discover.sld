;; Target discovery beside the old compiler's, for as long as both exist:
;; what `discover-targets` answers for a program beside what the old
;; `discover-artifacts` does, as the old planner reads it, each target once
;; at its first use, by target and place. tests/compare-compiler.sld runs
;; it, compiled, over the suites' programs. The old discovery is a whole
;; old expansion, which makes the checks `expand` leaves to later passes,
;; so a program the old discovery refuses for one of those is discovered
;; by the new one; the comparison names it apart, for the caller to check
;; against what the new compile reports. A program that reaches a
;; generated library is not compared: the old
;; discovery stops at the first producer whose output was not supplied,
;; and runs none. Few suite programs ask for a target, so the cases below
;; are compared too, each written in a directory of its own.
(define-library (snail compiler adapter discover)
  (export
   discovery-comparison
   DiscoveryCase
   discovery-cases
   discovery-case-comparison)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler expand targets)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler integrate discover)
   (only (snail compiler adapter outline) feedback-text)
   (only (snail compiler adapter read) feedback->old feedback-difference)
   (prefix (only (snail shell compiler read)
                 diagnostics->list
                 diagnostics->string
                 Stop
                 Failed
                 Requested
                 compiling)
           old:)
   (prefix (only (snail shell compiler expand) ArtifactUse discover-artifacts) old:)
   (prefix (only (snail shell compiler inputs) no-inputs) old:))
  (begin

    ;; ---- Programs ----

    ;; What discovering the program at `path` finds: a kind, and what it
    ;; says. Producers' outputs are read from `generated`.
    (: discovery-comparison (impl (Fn (List String) String String -> (Pair String String) ! fs)))
    (define (discovery-comparison directories generated path)
      (match (load-program directories generated path)
        ((Err feedback)
         (Pair "not compared" (string-append "it does not load: " (feedback-text feedback))))
        ((Ok (Unproduced _)) (Pair "not compared" "it reaches a generated library"))
        ((Ok (Complete _))
         (outcomes (discover-targets directories generated path)
                   (old:compiling
                    (lambda () (old:discover-artifacts directories old:no-inputs path)))))))

    (: outcomes
       (impl (Fn (Result (List TargetRequest) (List Feedback))
                 (Result (List old:ArtifactUse) old:Stop)
                 ->
                 (Pair String String))))
    (define (outcomes new old)
      (match (Pair new old)
        ((Pair (Ok requests) (Ok uses)) (requests-comparison requests (first-uses uses)))
        ((Pair (Err feedback) (Err (old:Failed diagnostics)))
         (match (feedback-difference (map feedback->old feedback)
                                     (old:diagnostics->list diagnostics))
           ((Some difference) (Pair "fail differently" difference))
           ((None) (Pair "fail alike" ""))))
        ((Pair (Ok _) (Err (old:Failed diagnostics)))
         (Pair "only the old fails" (old:diagnostics->string diagnostics)))
        ((Pair (Err feedback) (Ok _)) (Pair "only the new fails" (feedback-text feedback)))
        ((Pair _ (Err (old:Requested _)))
         (Pair "not compared" "the old discovery asks for an input"))))

    ;; Each use the old discovery records, once for each target, at its
    ;; first, as the old planner keeps them.
    (: first-uses (impl (Fn (List old:ArtifactUse) -> (List old:ArtifactUse))))
    (define (first-uses uses)
      (delete-duplicates (lambda (use other) (string=? (::name use) (::name other))) uses))

    ;; ---- Cases ----

    ;; A program, at `main`, and the files beside it, which ask for
    ;; targets.
    (struct DiscoveryCase
      ((main String)
       (files (List (Pair String String)))))

    ;; A library's targets come before its importers', each library's in
    ;; the order written; a target asked for again is asked for where it
    ;; was first, in a statement, nested in another request's empty list,
    ;; a let, a method or a macro's use; a macro no use expands asks for
    ;; nothing.
    (: discovery-cases (List DiscoveryCase))
    (define discovery-cases
      (list (DiscoveryCase
             "order.sld"
             (list (Pair "sample/site.sld"
                         (string-append
                          "(define-library (sample site) (import (snail core forms)) (export page asks)\n"
                          "  (begin (define page (artifact-files \"site\" 1 2 3))\n"
                          "         (define-syntax asks (syntax-rules () ((_ t) (artifact-files t 1 2 3))))\n"
                          "         (define-syntax unused\n"
                          "           (syntax-rules () ((_) (artifact-files \"never\" 1 2 3))))))"))
                   (Pair "sample/docs.sld"
                         (string-append
                          "(define-library (sample docs) (import (snail core forms) (sample site))\n"
                          "  (export manual)\n"
                          "  (begin (define manual (asks \"docs\")) (define again (asks \"site\"))))"))
                   (Pair "order.sld"
                         (string-append "(import (snail core forms) (sample docs) (sample site))\n"
                                        "(asks \"admin\")\n"
                                        "(asks \"docs\")"))))
            (DiscoveryCase
             "written.sld"
             (list (Pair "written.sld"
                         (string-append "(import (snail core forms))\n"
                                        "(define (f) (artifact-files \"late\" 1 2 3))\n"
                                        "(artifact-files \"statement\" 1 2 3)\n"
                                        "(define g (artifact-files \"early\" 1 2 3))\n"
                                        "(artifact-files \"late\" 1 2 3)\n"
                                        "(artifact-files \"last\" 1 2 3)"))))
            (DiscoveryCase
             "nested.sld"
             (list (Pair "sample/nest.sld"
                         (string-append
                          "(define-library (sample nest) (import (snail core forms)) (export Show show)\n"
                          "  (begin (typeclass (Show T) (: show (impl (Fn T -> I64))))\n"
                          "         (instance (Show I64) (define (show x) (artifact-files \"method\" 1 2 3)))\n"
                          "         (define (outer)\n"
                          "           (artifact-files \"outer\" 1 2 (artifact-files \"inner\" 1 2 3)))\n"
                          "         (define (later) (let ((x (artifact-files \"bound\" 1 2 3))) (artifact-files \"body\" 1 2 3)))))"))
                   (Pair "nested.sld"
                         "(import (snail core forms) (sample nest))\n(artifact-files \"inner\" 1 2 3)")))
            (DiscoveryCase
             "bundle.sld"
             (list (Pair "sample/bundled.sld"
                         (string-append
                          "(define-library (sample bundled) (import (snail core base) (snail shell artifact))\n"
                          "  (export first)\n"
                          "  (begin (define (first) (artifact-bundle \"one\"))))"))
                   (Pair "bundle.sld"
                         (string-append
                          "(import (snail core base) (snail shell artifact) (sample bundled))\n"
                          "(artifact-bundle \"two\")\n"
                          "(artifact-bundle \"one\")"))))))

    ;; The case written in `directory`, which has a `sample` directory,
    ;; discovered by both compilers, its libraries found there and in
    ;; `directories`.
    (: discovery-case-comparison
       (impl (Fn String (List String) String DiscoveryCase -> (Pair String String) ! fs)))
    (define (discovery-case-comparison directory directories generated discovery-case)
      (for-each
       (lambda (file) (write-file (string-append directory "/" (::first file)) (::second file)))
       (::files discovery-case))
      (discovery-comparison (Cons directory directories)
                            generated
                            (string-append directory "/" (::main discovery-case))))

    ;; ---- Targets ----

    (: requests-comparison
       (impl (Fn (List TargetRequest) (List old:ArtifactUse) -> (Pair String String))))
    (define (requests-comparison requests uses)
      (let ((new (string-join (map request-text requests) "; "))
            (old (string-join (map use-text uses) "; ")))
        (if (string=? new old)
            (Pair "discover alike" new)
            (Pair "discoveries differ" (string-append "new: " new "; old: " old)))))

    (: request-text (impl (Fn TargetRequest -> String)))
    (define (request-text request)
      (let ((loc (::loc request)))
        (place-text (::target request) (::file loc) (::line loc) (::column loc))))

    (: use-text (impl (Fn old:ArtifactUse -> String)))
    (define (use-text use)
      (let ((loc (::loc use)))
        (place-text (::name use) (::file loc) (::line loc) (::column loc))))

    (: place-text (impl (Fn String String I64 I64 -> String)))
    (define (place-text target file line column)
      (string-append target " at " file ":" (i64->string line) ":" (i64->string column)))

    ))
