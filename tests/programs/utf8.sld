;; UTF-8 in both directions. The expected output was produced once by
;; Node: encodings by TextEncoder, and each decode by a TextDecoder with
;; `fatal: true` and `ignoreBOM: true`, an error's offset being the length
;; of the longest prefix such a decoder accepts. Node has no Char beyond
;; U+10FFFF, so that one encoding was written by hand.
(import
 (snail-core base)
 (snail-core io)
 (snail-core utf8))

(: hex-digits (-> I32 I64 String))
(define (hex-digits value count)
  (string-generate count
                   (lambda (index)
                     (string-ref "0123456789abcdef"
                                 (i32->i64 (i32-and (i32-shift-right/logical value (i64->i32 (* 4 (- (- count 1) index)))) 15))))))

(: bytes-text (-> Bytes String))
(define (bytes-text bytes)
  (string-join (map (lambda (byte) (hex-digits (u8->i32 byte) 2)) (vector->list bytes)) " "))

(: decoded-text (-> (Result String Utf8Error) String))
(define (decoded-text result)
  (match result
    ((Ok text) (string-join (Cons "ok" (map (lambda (char) (hex-digits (char->i32 char) 6)) (string->list text))) " "))
    ((Err error) (string-append "error at " (show (Utf8Error-offset error))))))

;; Each width's first and last scalar, the surrogates around them, the
;; byte order mark, and a code beyond U+10FFFF.
(for-each (lambda (code) (write-line (string-append (hex-digits code 6) ": " (bytes-text (string->utf8 (string (i32->char code)))))))
          (list 0 65 127 128 955 2047 2048 8364 55295 55296 56320 57343 57344 65279 65535 65536 128512 1114111 1114112))
(write-line (string-append "empty: [" (bytes-text (string->utf8 "")) "]"))
(write-line (bytes-text (string->utf8 "aλ€😀z")))

;; Well-formed sequences, then every kind of ill-formed one: stray
;; continuations, leads that begin nothing, overlong forms, surrogates,
;; codes beyond U+10FFFF, bad continuations and truncation. An offset
;; counts bytes, not scalars.
(for-each (lambda (bytes) (write-line (string-append (bytes-text bytes) " -> " (decoded-text (utf8->string bytes)))))
          (list #u8()
                #u8(0 65 127)
                #u8(239 187 191 65)
                #u8(194 128 223 191)
                #u8(224 160 128 237 159 191 238 128 128 239 191 191)
                #u8(240 144 128 128 244 143 191 191)
                #u8(240 159 152 128)
                #u8(128)
                #u8(65 191)
                #u8(192 128)
                #u8(193 191)
                #u8(224 128 128)
                #u8(224 159 191)
                #u8(240 128 128 128)
                #u8(240 143 191 191)
                #u8(237 160 128)
                #u8(237 191 191)
                #u8(244 144 128 128)
                #u8(245 128 128 128)
                #u8(254)
                #u8(255)
                #u8(226 65)
                #u8(226 130 65)
                #u8(240 159 152 65)
                #u8(194)
                #u8(226 130)
                #u8(97 98 240 159 152)
                #u8(206 187 255)
                #u8(206 187 226 130 172 237 160 128)))

;; Text that is all scalars comes back unchanged.
(let ((text (string-append "plain ASCII, " "λx. x, " "€ 1 000, " "😀🐌" (string (i32->char 0) (i32->char 1114111)))))
  (write-line (show (match (utf8->string (string->utf8 text)) ((Ok decoded) (string=? decoded text)) ((Err _) #f)))))
