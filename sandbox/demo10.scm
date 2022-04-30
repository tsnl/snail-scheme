;;; import/ss-clr is an import backend that specifies exactly which symbols to require/expose after every occurrence of 'only' and 'except' are resolved.
;;; These are resolved in the front-end by the expander, which recursively parses and expands libraries.
;;; Each library may have multiple import statements (we do not coalesce), but on each, we check if definitions are in conflict.

(import/ss-clr 
  (scheme base)
  (+ * / % ...))
