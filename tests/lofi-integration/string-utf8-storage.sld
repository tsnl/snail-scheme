(import
 (lofi base)
 (lofi bytes))

;; ---- Scalar boundaries survive replacement and spare capacity ----

(def expect (-> Bool Unit) (lambda (condition) (if condition (unit) (unreachable))))
(def text (string-copy "aé😀z"))
(def alias text)
(string-ref text (ann 1 I64))
(string-copy! text (ann 0 I64) "éa" (ann 0 I64) (ann 2 I64))
(expect (char=? (string-ref text (ann 1 I64)) #\a))
(string-set! text (ann 1 I64) #\x1f600)
(string-set! text (ann 2 I64) #\a)
(expect (string=? text "é😀az"))
(expect (= (bytevector-length (string->utf8 text)) (ann 8 I64)))
(expect (string-eq? text alias))

;; ---- Both overlap directions change the number of encoded bytes ----

(string-copy! text (ann 1 I64) text (ann 0 I64) (ann 3 I64))
(expect (string=? text "éé😀a"))
(string-copy! text (ann 0 I64) text (ann 1 I64) (ann 4 I64))
(expect (string=? text "é😀aa"))
(expect (char=? (string-ref text (ann 3 I64)) #\a))
(expect (char=? (string-ref text (ann 0 I64)) #\é))
(expect (char=? (string-ref text (ann 2 I64)) #\a))
(expect (char=? (string-ref text (ann 1 I64)) #\x1f600))
(string-set! text (ann 1 I64) #\null)
(expect (= (string-length text) (ann 4 I64)))
(expect (= (bytevector-length (string->utf8 text)) (ann 5 I64)))
(expect (string=? text "é\x0;aa"))

;; ---- Conversions and slices retain independent mutable contents ----

(def bytes (string->utf8 text))
(def decoded (utf8->string bytes))
(def tail (substring text (ann 2 I64) (ann 4 I64)))
(bytevector-u8-set! bytes (ann 0 I64) (ann 0 I64))
(string-set! text (ann 2 I64) #\λ)
(expect (string=? decoded "é\x0;aa"))
(expect (string=? tail "aa"))
(expect (string=? text "é\x0;λa"))
(expect (string=? (utf8->string (string->utf8 text)) text))
(ann 42 I64)
