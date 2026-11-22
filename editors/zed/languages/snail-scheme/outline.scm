; A library by its name, and each definition in it, or at the top of a
; program, by the form that makes it and the name it gives.

(list
  .
  (symbol) @context
  .
  (list) @name
  (#eq? @context "define-library")) @item

(list
  .
  (symbol) @context
  .
  [
    (symbol) @name
    (list . (symbol) @name)
  ]
  (#any-of? @context
    "define" "define-syntax" "declare" "record" "capability" "enum" "type"
    "typeclass" "instance")) @item
