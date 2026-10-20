;; The emitted wrapper keeps its provider's core identity. Its caller-supplied
;; child name denotes the new function, even though it spells begin.
(import
 (only (macro declarations) call-through-binding))
(call-through-binding begin)
