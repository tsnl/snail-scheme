;; The pass `expand` beside the old expander, as far as it is built. The
;; old expander's import sets, macros and resolution are not exported,
;; so they are compared once whole libraries expand; what can be compared
;; now is the offer of (snail core forms), which the old expander builds
;; from the lists of src/snail/shell/compiler/core.sld: its keywords, its
;; builtin types but `fn`, and the effects `mut` and `host`, in that order.
(define-library (snail compiler adapter expand)
  (export
   forms-difference)
  (import
   (snail core base)
   (snail compiler expand language)
   (snail compiler expand offer)
   (snail compiler expand forms)
   (snail compiler expand scopes)
   (prefix (only (snail shell compiler core) core-keywords builtin-types) old:))
  (begin

    ;; ---- The forms library ----

    ;; The first export of the two offers that differs, if one does.
    (: forms-difference (impl (Fn -> (Option String))))
    (define (forms-difference)
      (exports-difference (::exports forms-offer) old-forms-exports))

    (: old-forms-exports (List Export))
    (define old-forms-exports
      (append (map (lambda (name) (Export name (Keyword name))) old:core-keywords)
              (append (map (lambda (entry)
                             (Export (::first entry)
                                     (TypeName (Global forms-library (::first entry) 0) #f)))
                           (filter (lambda (entry) (not (string=? (::first entry) "fn")))
                                   old:builtin-types))
                      (map (lambda (name) (Export name (EffectName (Global forms-library name 0))))
                           (list "mut" "host")))))

    (: exports-difference (impl (Fn (List Export) (List Export) -> (Option String))))
    (define (exports-difference new old)
      (match (Pair new old)
        ((Pair (Nil) (Nil)) (None))
        ((Pair (Cons export more) (Cons other rest))
         (if (and (string=? (::name export) (::name other))
                  (same-meaning? (::meaning export) (::meaning other)))
             (exports-difference more rest)
             (Some (string-append "the new offer has " (::name export) " where the old has "
                                  (::name other)
                                  " or another meaning"))))
        ((Pair (Cons export _) (Nil))
         (Some (string-append "only the new offer has " (::name export))))
        ((Pair (Nil) (Cons other _))
         (Some (string-append "only the old offer has " (::name other))))))

    ))
