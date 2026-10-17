(import
 (rename (lofi core) (identifier-name source-name) (library-name owner-name))
 (lofi base)
 (rename (macro deriving-left) (schema left-schema))
 (rename (macro deriving-right) (schema right-schema)))

(if (string=? left-schema "(macro deriving-left)/Box/box/schema/box-value")
    (if (string=? right-schema "(macro deriving-right)/Box/box/schema/box-value")
        (if (string=? (source-name left-schema) "left-schema")
            (if (string=? (owner-name) "#f") 42 0)
            0)
        0)
    0)
