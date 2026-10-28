;; A generated library whose producer needs the library it generates, by
;; way of (sample knot-helper): an import cycle that passes through a
;; producer.
(generate-library (sample knot)
                  (import
                   (snail core base)
                   (snail shell syntax)
                   (sample knot-helper))
                  (library-syntax (list "sample" "knot")
                                  (list "knot")
                                  (list (list "snail" "core" "base"))
                                  (list (form "define"
                                              (list (SymbolSyntax "knot")
                                                    (IntegerSyntax helper))))))
