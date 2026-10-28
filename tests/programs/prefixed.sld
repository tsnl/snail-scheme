(import
 (prefix (snail-core base) b:)
 (only (snail-core io) write-line))

;; Methods are named within their class, whatever prefix imports it.
(b:struct Pair2
          ((left b:I64)
           (right b:I64)))

(b:instance (b:Show Pair2)
            (b:define (show pair)
                      (b:string-append (b:show (Pair2-left pair))
                                       "/"
                                       (b:show (Pair2-right pair)))))

(write-line (b:show (Pair2 3 4)))
