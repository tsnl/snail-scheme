(import
 (snail core base)
 (snail core io)
 (snail shell datum)
 (snail shell read)
 (snail shell write))

(: round-trip (-> String Unit ! console))
(define (round-trip text)
  (match (read-datums text)
    ((Ok data) (for-each (lambda (datum) (write-line (datum->string datum))) data))
    ((Err message) (write-line (string-append "error: " message)))))

(round-trip "(define (f x) (+ x 1/2)) ; comment
             #| block #| nested |# |# 'quoted `(a ,b ,@c)")
(round-trip "(1 . 2) (a b . c) #(1 \"two\" #\\x) #u8(0 255) #t #false 1e2 \"line\\nbreak\"")
(round-trip "(unclosed")
(round-trip "#u8(300)")
(match (read-datum "(display \"hi\")")
  ((Ok datum) (write-line (datum->display-string datum)))
  ((Err message) (write-line message)))
(match (Pair (read-datum "(1 (2 #(3)))") (read-datum "(1 (2 #(3)))"))
  ((Pair (Ok a) (Ok b)) (display (datum=? a b)) (newline))
  (_ (write-line "unreadable")))
