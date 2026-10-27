;; A producer that imports, through another library, the library it
;; generates. It is compiled while (sample knot) loads, so the import is a
;; cycle, reported as one rather than nesting producers without end.
(import
 (snail-core base)
 (snail-core io)
 (sample knot))

(display knot)
