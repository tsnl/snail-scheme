;; Loading beside the old compiler, for as long as both exist. The old
;; compiler loads a library as its expander reaches the library's import,
;; so its loading is judged against `expand-program`, in two ways.
;;
;; - The cases below, which each stop loading at one problem: the first
;;   problem the old expander reports is the loader's. tests/compiler.scm
;;   runs them.
;; - The order of a program's libraries beside the order the old expansion
;;   records them in, which tests/compare-compiler.sld runs, compiled, over
;;   the suites' programs.
;;
;; The comparisons read and write files, as the old functions they call do.
(define-library (snail compiler adapter load)
  (export
   LoadCase
   load-cases
   load-case-comparison
   OrderComparison
   SameOrder
   KnownOrder
   OtherOrder
   UncomparedOrder
   order-comparison)
  (import
   (snail core base)
   (snail core io)
   (snail compiler source)
   (snail compiler outline language)
   (snail compiler outline names)
   (snail compiler integrate walk)
   (snail compiler integrate load)
   (snail compiler adapter outline)
   (prefix (only (snail shell compiler read)
                 Loc
                 diagnostics->string
                 compile
                 compile-error
                 Stop
                 Failed
                 Requested
                 compiling)
           old:)
   (prefix (only (snail shell compiler expand)
                 ExpandedProgram
                 expand-program
                 empty-expansion)
           old:)
   (prefix (only (snail shell compiler inputs)
                 no-inputs)
           old:))
  (begin

    ;; ---- The old expansion ----

    ;; What the old expander makes of the program at `path`. It runs no
    ;; producer program, and says so.
    (: old-expansion
       (impl (Fn (List String) String -> (Result old:ExpandedProgram old:Stop) ! fs)))
    (define (old-expansion directories path)
      (old:compiling (lambda ()
                       (old:expand-program directories
                                           (lambda (loading forms) (no-producer path))
                                           old:no-inputs
                                           path
                                           old:empty-expansion))))

    (: no-producer (All (T) (impl (Fn String -> T ! old:compile))))
    (define (no-producer path)
      (old:compile-error (old:Loc path 0 0) "the comparison runs no producer"))

    ;; ---- Problems ----

    ;; A program, at `main` in a directory, that the files beside it make
    ;; fail to load. The files are named from the directory, which has a
    ;; `sample` directory; a program without text is not there.
    (struct LoadCase
      ((main String)
       (text (Option String))
       (files (List (Pair String String)))))

    (: load-cases (List LoadCase))
    (define load-cases
      (list (LoadCase "absent.sld" (None) (list))
            (LoadCase "missing.sld" (Some "(import (prefix (sample absent) p:))") (list))
            (LoadCase "holder.sld"
                      (Some "(import (sample holder))")
                      (list (Pair "sample/holder.sld"
                                  "(define-library (sample holder)\n  (import (rename (sample gone) (x y))))")))
            (LoadCase "self.sld"
                      (Some "(import (sample self))")
                      (list (Pair "sample/self.sld"
                                  "(define-library (sample self)\n  (import (only (sample self) x)))")))
            (LoadCase "ring.sld"
                      (Some "(import (sample ring-a))")
                      (list (Pair "sample/ring-a.sld"
                                  "(define-library (sample ring-a) (import (sample ring-b)))")
                            (Pair "sample/ring-b.sld"
                                  "(define-library (sample ring-b) (import (except (sample ring-a) y)))")))
            (LoadCase "loop.sld"
                      (Some "(import (sample leaf) (sample loop))")
                      (list (Pair "sample/leaf.sld" "(define-library (sample leaf))")
                            (Pair "sample/loop.sld"
                                  "(define-library (sample loop) (import (sample leaf) (sample loop)))")))
            (LoadCase "keyed.sld"
                      (Some "(generating \"other\" \"sample.keyed\")\n(import (sample keyed))")
                      (list))))

    ;; The case written in `directory`, loaded, beside the old expansion.
    (: load-case-comparison (impl (Fn String LoadCase -> Comparison ! fs)))
    (define (load-case-comparison directory load-case)
      (let ((main (string-append directory "/" (::main load-case))))
        (for-each (lambda (file)
                    (write-file (string-append directory "/" (::first file)) (::second file)))
                  (::files load-case))
        (match (::text load-case)
          ((Some text) (write-file main text))
          ((None) (unit)))
        (match (Pair (load-program (list directory) main) (old-expansion (list directory) main))
          ((Pair (Err feedback) (Err stop)) (stop-comparison feedback stop))
          ((Pair (Err feedback) (Ok _)) (only-new-stops feedback))
          ((Pair (Ok _) (Err stop)) (only-old-stops stop))
          ((Pair (Ok _) (Ok _)) (Uncompared "neither stops")))))

    ;; ---- Order ----

    ;; How the libraries of a program that loads completely come beside
    ;; those the old expansion records, in order: the same, the same but
    ;; for differences explained, or otherwise.
    (enum OrderComparison
      (SameOrder)
      (KnownOrder
       ((note String)))
      (OtherOrder
       ((difference String)))
      (UncomparedOrder
       ((reason String))))

    (: order-comparison (impl (Fn (List String) String -> OrderComparison ! fs)))
    (define (order-comparison directories path)
      (match (load-program directories path)
        ((Err feedback)
         (UncomparedOrder (string-append "it does not load: " (feedback-text feedback))))
        ((Ok loaded)
         (match (::waiting loaded)
           ((Cons _ _) (UncomparedOrder "it reaches a generated library"))
           ((Nil)
            (expanded-order (map file-key (::files loaded)) (old-expansion directories path)))))))

    (: expanded-order
       (impl (Fn (List String) (Result old:ExpandedProgram old:Stop) -> OrderComparison)))
    (define (expanded-order new old)
      (match old
        ((Ok expanded)
         (orders-comparison new (reverse (map ::first (::libraries (::program expanded))))))
        ((Err (old:Failed diagnostics))
         (UncomparedOrder (string-append "the old compiler does not expand it: "
                                         (old:diagnostics->string diagnostics))))
        ((Err (old:Requested _)) (UncomparedOrder "the old compiler asks for an input"))))

    ;; A file by the old compiler's name for its library, the program's
    ;; being `main`.
    (: file-key (impl (Fn Outlined -> String)))
    (define (file-key outlined)
      (match (::outline outlined)
        ((Written (Defined name _ _ _ _)) (library-key name))
        ((Written (Program _ _ _ _)) "main")
        ((Generated name _ _ _) (library-key name))))

    ;; Two differences are known. The old expansion records no run for the
    ;; primitive library, whose body declares and defines nothing, so it
    ;; never lists it. And a `deriving` clause loads (snail shell wire) and
    ;; what it imports, which this loader does not load yet, so the old
    ;; expansion may list them earlier than an import of them, before the
    ;; library that derives, or list them when nothing imports them.
    (: orders-comparison (impl (Fn (List String) (List String) -> OrderComparison)))
    (define (orders-comparison new old)
      (let ((shared (filter (lambda (key) (member? key new)) old))
            (extra (filter (lambda (key) (not (member? key new))) old))
            (kept (without "snail.core.primitive" new)))
        (cond ((same-keys? new old) (SameOrder))
              ((not (or (null? extra) (member? "snail.shell.wire" old))) (other-order new old))
              ((same-keys? kept shared) (KnownOrder (known-note new extra #f)))
              ((same-keys? (without "snail.shell.wire" kept) (without "snail.shell.wire" shared))
               (KnownOrder (known-note new extra #t)))
              (else (other-order new old)))))

    (: other-order (impl (Fn (List String) (List String) -> OrderComparison)))
    (define (other-order new old)
      (OtherOrder (string-append "new: " (string-join new " ") "; old: " (string-join old " "))))

    (: without (impl (Fn String (List String) -> (List String))))
    (define (without key keys)
      (filter (lambda (other) (not (string=? other key))) keys))

    (: known-note (impl (Fn (List String) (List String) Bool -> String)))
    (define (known-note new extra moved)
      (string-join
       (concatenate
        (list (if (member? "snail.core.primitive" new) (list "the primitive library") (Nil))
              (if moved (list "snail.shell.wire loaded early by a deriving clause") (Nil))
              (if (null? extra)
                  (Nil)
                  (list (string-append "a deriving clause's " (string-join extra " "))))))
       ", "))

    (: same-keys? (impl (Fn (List String) (List String) -> Bool)))
    (define (same-keys? keys others)
      (and (= (length keys) (length others))
           (every? (lambda (pair) (string=? (::first pair) (::second pair))) (zip keys others))))

    ))
