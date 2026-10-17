(import
 (lofi base))
(def convert
     (lambda (procedure value) (procedure value)))

(def negative (-> Char)
     (lambda () (integer->char (ann -1 I64))))

(def surrogate-low (-> Char)
     (lambda () (integer->char (ann 55296 I64))))

(def surrogate-high (-> Char)
     (lambda () (integer->char (ann 57343 I64))))

(def too-large (-> Char)
     (lambda () (integer->char (ann 1114112 I64))))

(def huge (-> Char)
     (lambda () (convert integer->char (ann 9223372036854775807 I64))))
(if (if (= (char->integer (integer->char (ann 0 I64))) (ann 0 I64))
        (if (= (char->integer (integer->char (ann 55295 I64))) (ann 55295 I64))
            (if (= (char->integer (integer->char (ann 57344 I64))) (ann 57344 I64))
                (if (= (char->integer (convert integer->char (ann 1114111 I64))) (ann 1114111 I64))
                    (if (char<? #\A #\é)
                        (if (char<=? #\λ #\λ)
                            (if (char>? #\😀 #\λ) (if (char>=? #\😀 #\😀) (not (char=? #\é #\λ)) #f) #f)
                            #f)
                        #f)
                    #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
