(import
 (prefix (snail core base) b:)
 (only (snail core io) write-line))

;; Methods are named within their class, whatever prefix imports it.
(b:record Pair2
          ((left b:I64)
           (right b:I64)))

(b:instance (b:Show (!) Pair2)
            (b:define show
                      (b:lambda (pair)
                                (b:string-append (b:show (b:● pair left))
                                                 "/"
                                                 (b:show (b:● pair right))))))

(b:define main
          (b:lambda ()
                    (write-line (b:show (b:new Pair2 (left 3) (right 4))))
                    (b:unit)))
