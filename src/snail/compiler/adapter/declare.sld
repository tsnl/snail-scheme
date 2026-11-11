;; The pass `declare` beside the old expander, as far as it is built. Its
;; types part is judged by its own tests until whole libraries are
;; declared; what can be compared now is what it knows of (snail core
;; forms), the builtin types and their arities, which the old expander
;; takes from src/snail/shell/compiler/core.sld's `builtin-types`, but for
;; `fn`, which the new front end reads as code.
(define-library (snail compiler adapter declare)
  (export
   builtins-difference)
  (import
   (snail core base)
   (snail compiler declare forms)
   (prefix (only (snail shell compiler core) builtin-types) old:))
  (begin

    ;; ---- The forms library ----

    ;; The first builtin type of the two lists that differs, by its name or
    ;; its arity, if one does.
    (: builtins-difference (impl (Fn -> (Option String))))
    (define (builtins-difference)
      (entries-difference builtin-types
                          (filter (lambda (entry) (not (string=? (::first entry) "fn")))
                                  old:builtin-types)))

    (: entries-difference
       (impl (Fn (List (Pair String I64)) (List (Pair String I64)) -> (Option String))))
    (define (entries-difference new old)
      (match (Pair new old)
        ((Pair (Nil) (Nil)) (None))
        ((Pair (Cons entry more) (Cons other rest))
         (if (and (string=? (::first entry) (::first other)) (= (::second entry) (::second other)))
             (entries-difference more rest)
             (Some (string-append "the new list has " (::first entry) " where the old has "
                                  (::first other)
                                  " or another arity"))))
        ((Pair (Cons entry _) (Nil))
         (Some (string-append "only the new list has " (::first entry))))
        ((Pair (Nil) (Cons other _))
         (Some (string-append "only the old list has " (::first other))))))

    ))
