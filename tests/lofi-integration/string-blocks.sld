(import
 (lofi base))

;; ---- Independent scalar oracle ----

(def pattern-character
     (lambda (index)
       (begin (let choice (remainder index (ann 5 I64)))
              (if (= choice (ann 0 I64))
                  #\null
                  (if (= choice (ann 1 I64)) #\é (if (= choice (ann 2 I64)) #\x1f600 (if (= choice (ann 3 I64)) #\x10ffff #\x301)))))))
(def pattern-string
     (lambda (length)
       (begin (let value (make-string length))
              (begin
                (begin
                  (def loop
                       (lambda (index)
                         (if (= index length)
                             (unit)
                             (begin
                               (string-set! value index (pattern-character index))
                               (loop (+ index (ann 1 I64)))
                               (unit)))))
                  (loop (ann 0 I64)))
                value))))
(def copied-range?
     (lambda (length at start end)
       (begin (let value (pattern-string length))
              (begin (let before (string-copy value))
                     (begin (let expected (string-copy value))
                            (begin
                              (begin
                                (def loop
                                     (lambda (index)
                                       (if (= index end)
                                           (unit)
                                           (begin
                                             (string-set! expected (+ at (- index start)) (string-ref before index))
                                             (loop (+ index (ann 1 I64)))
                                             (unit)))))
                                (loop start))
                              (string-copy! value at value start end)
                              (string=? value expected)))))))

;; ---- Fresh buffers, aliases and block-edge overlap ----

(def original
     (pattern-string (ann 16385 I64)))
(def alias
     original)
(def copied
     (string-copy original))
(def middle
     (substring original (ann 8191 I64) (ann 16385 I64)))
(def joined
     (string-append "[" original "]"))
(string-set! alias (ann 8192 I64) #\Z)
(if (if (string-eq? alias original)
        (if (not (string-eq? copied original))
            (if (char=? (string-ref original (ann 8192 I64)) #\Z)
                (if (char=? (string-ref copied (ann 8192 I64)) (pattern-character (ann 8192 I64)))
                    (if (char=? (string-ref middle (ann 1 I64)) (pattern-character (ann 8192 I64)))
                        (if (char=? (string-ref joined (ann 8193 I64)) (pattern-character (ann 8192 I64)))
                            (if (char=? (string-ref copied (ann 16384 I64)) (pattern-character (ann 16384 I64)))
                                (if (copied-range? (ann 0 I64) (ann 0 I64) (ann 0 I64) (ann 0 I64))
                                    (if (copied-range? (ann 1 I64) (ann 0 I64) (ann 0 I64) (ann 1 I64))
                                        (if (copied-range? (ann 8191 I64) (ann 1 I64) (ann 0 I64) (ann 8190 I64))
                                            (if (copied-range? (ann 8192 I64) (ann 0 I64) (ann 1 I64) (ann 8192 I64))
                                                (if (copied-range? (ann 8193 I64) (ann 1 I64) (ann 0 I64) (ann 8192 I64))
                                                    (if (copied-range? (ann 16384 I64) (ann 1 I64) (ann 0 I64) (ann 16383 I64))
                                                        (if (copied-range? (ann 16384 I64) (ann 0 I64) (ann 1 I64) (ann 16384 I64))
                                                            (if (copied-range? (ann 16385 I64) (ann 8190 I64) (ann 8188 I64) (ann 16381 I64))
                                                                (if (copied-range? (ann 24579 I64) (ann 8191 I64) (ann 8189 I64) (ann 16393 I64))
                                                                    (if (copied-range? (ann 24579 I64) (ann 0 I64) (ann 8190 I64) (ann 24579 I64))
                                                                        (if (copied-range? (ann 24579 I64) (ann 16387 I64) (ann 0 I64) (ann 8192 I64))
                                                                            (if (copied-range? (ann 32801 I64) (ann 123 I64) (ann 8159 I64) (ann 25000 I64))
                                                                                (if (copied-range? (ann 24576 I64) (ann 0 I64) (ann 0 I64) (ann 24576 I64)) (copied-range? (ann 24579 I64) (ann 24579 I64) (ann 24579 I64) (ann 24579 I64)) #f)
                                                                                #f)
                                                                            #f)
                                                                        #f)
                                                                    #f)
                                                                #f)
                                                            #f)
                                                        #f)
                                                    #f)
                                                #f)
                                            #f)
                                        #f)
                                    #f)
                                #f)
                            #f)
                        #f)
                    #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
