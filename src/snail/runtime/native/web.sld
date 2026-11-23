;; Node's fetch, as host/native/web-imports.mjs provides it: the length of
;; the file at a URL, and parts of it. A URL is sent first, a character at
;; a time and ended by `argument-end`; `start-size` and `start-part` take
;; the URL sent last, and `finish` answers each with its ticket
;; ((snail shell task)'s `through-host`), as (snail runtime native socket)
;; answers.
;;
;; An answer is -1 for a failure and 0 otherwise. The host holds what an
;; answer carries until it answers again, so the shell reads it first: a
;; number by `held-number`, and byte strings by `held-length` and
;; `held-byte`, each by its position. A failure's first byte string is its
;; code: `HTTP_NNN` for a status, `NO_RANGES` when the server answers a
;; part with the whole file, `NO_LENGTH` when it gives no length,
;; `WRONG_PART` when a part is not the range asked for, or the network's
;; own, such as "ENOTFOUND".
;;
;;   operation   number        byte strings
;;   size        the length
;;   part                      the bytes
(define-library (snail runtime native web)
  (export
   argument-character
   argument-end
   start-size
   start-part
   finish
   held-number
   held-length
   held-byte)
  (import
   (snail core base))
  (begin
    (extern argument-character "snail.runtime.native.web" "argument-character" (Fn Char → Unit))
    (extern argument-end "snail.runtime.native.web" "argument-end" (Fn → Unit))
    (extern start-size "snail.runtime.native.web" "start-size" (Fn I64 → Unit))
    (extern start-part "snail.runtime.native.web" "start-part" (Fn I64 I64 I64 → Unit))
    (extern finish "snail.runtime.native.web" "finish" (Fn I64 → I32))
    (extern held-number "snail.runtime.native.web" "held-number" (Fn → I64))
    (extern held-length "snail.runtime.native.web" "held-length" (Fn I32 → I32))
    (extern held-byte "snail.runtime.native.web" "held-byte" (Fn I32 I32 → I32))))
