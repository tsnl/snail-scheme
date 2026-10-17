(import
 (lofi base)
 (lofi bytes))

(def isolated-tail (-> I64)
     (lambda () (string-length (utf8->string #u8(128)))))

(def invalid-lead (-> I64)
     (lambda () (string-length (utf8->string #u8(255)))))

(def truncated-two (-> I64)
     (lambda () (string-length (utf8->string #u8(194)))))

(def truncated-three (-> I64)
     (lambda () (string-length (utf8->string #u8(224 160)))))

(def truncated-four (-> I64)
     (lambda () (string-length (utf8->string #u8(240 144 128)))))

(def bad-tail (-> I64)
     (lambda () (string-length (utf8->string #u8(224 65 128)))))

(def overlong-two (-> I64)
     (lambda () (string-length (utf8->string #u8(192 128)))))

(def overlong-three (-> I64)
     (lambda () (string-length (utf8->string #u8(224 159 191)))))

(def overlong-four (-> I64)
     (lambda () (string-length (utf8->string #u8(240 143 191 191)))))

(def surrogate (-> I64)
     (lambda () (string-length (utf8->string #u8(237 160 128)))))

(def too-large (-> I64)
     (lambda () (string-length (utf8->string #u8(244 144 128 128)))))

(def cut-start (-> I64)
     (lambda () (string-length (utf8->string #u8(195 169) (ann 1 I64)))))

(def cut-end (-> I64)
     (lambda () (string-length (utf8->string #u8(195 169) (ann 0 I64) (ann 1 I64)))))

(def negative-start (-> I64)
     (lambda () (string-length (utf8->string #u8() (ann -1 I64) (ann 0 I64)))))

(def past-end (-> I64)
     (lambda () (string-length (utf8->string #u8() (ann 1 I64) (ann 1 I64)))))

(def reversed (-> I64)
     (lambda () (string-length (utf8->string #u8(65) (ann 1 I64) (ann 0 I64)))))

(def encode-range (-> I64)
     (lambda () (bytevector-length (string->utf8 "A" (ann 0 I64) (ann 2 I64)))))

(def encode-negative (-> I64)
     (lambda () (bytevector-length (string->utf8 "A" (ann -1 I64) (ann 0 I64)))))
(ann 42 I64)
