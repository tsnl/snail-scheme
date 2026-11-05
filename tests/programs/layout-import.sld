;; A headerless entry also loads a layout library independently.
(import
 (snail core base)
 (snail core io)
 (sample reader-layout))
(write-line (show (twice 21)))
