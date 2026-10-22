;; The development loop as the IDE's worker (src/ide/toolchain.mjs) runs it:
;;
;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
;;
;; the loop of bootstrap/develop.sld, with its files in the worker. A browser
;; has no file system, so every file the loop and its compiler open goes
;; through a handler of (lofi io)'s `fs` effect to the `files` effect, which
;; the worker implements over the files it holds: the standard library, the
;; project as the editor has it, and what builds write.
(import
 (lofi base)
 (lofi io)
 (lofi develop))

;; ---- Files ----

;; (lofi io)'s file operations, except that text is written a character at
;; a time, since the worker cannot read a Lofi string. Bytes are read and
;; written one at a time, as (lofi io) does.
(effect files
  ((file-path-begin (-> Unit))
   (file-path-character (-> Char Unit))
   (file-exists (-> I32))
   (file-open-input (-> I32))
   (file-open-output (-> I32))
   (file-read (-> I32 I32))
   (file-read-byte (-> I32 I32))
   (file-write (-> I32 Char Unit))
   (file-write-byte (-> I32 I32 Unit))
   (file-close (-> I32 Unit)))
  (host "snail.files"
        ((file-path-begin "path-begin")
         (file-path-character "path-character")
         (file-exists "exists")
         (file-open-input "open-input")
         (file-open-output "open-output")
         (file-read "read")
         (file-read-byte "read-byte")
         (file-write "write")
         (file-write-byte "write-byte")
         (file-close "close"))))

(: with-files (-> (-> Unit ! mut fs console develop) Unit ! mut files console develop))
(define (with-files body)
  (handle fs
      ((path-begin (lambda () (file-path-begin)))
       (path-character (lambda (c) (file-path-character c)))
       (path-exists (lambda () (file-exists)))
       (open-input (lambda () (file-open-input)))
       (open-output (lambda () (file-open-output)))
       (port-read (lambda (port) (file-read port)))
       (port-read-byte (lambda (port) (file-read-byte port)))
       (port-write (lambda (port text) (write-text port text)))
       (port-write-byte (lambda (port byte) (file-write-byte port byte)))
       (port-close (lambda (port) (file-close port))))
    (body)))

(: write-text (-> I32 String Unit ! files))
(define (write-text port text)
  (let next ((index 0))
    (when (< index (string-length text))
      (file-write port (string-ref text index))
      (next (+ index 1)))))

;; ---- Events ----

(: loop (Ref (Option Loop)))
(define loop (ref (None)))

(: input (Ref (List Char)))
(define input (ref (Nil)))

(: develop-character (-> I32 Unit ! mut))
(define (develop-character code)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

(: develop-event (-> I32 Unit ! mut files console develop))
(define (develop-event kind)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    (match (ref-get loop)
      ((Some current) (with-files (lambda () (deliver-event! current kind text))))
      ((None) (unit)))))

(expose develop-character "develop_character")
(expose develop-event "develop_event")

(match (command-line)
  ((Cons _ arguments)
   (let ((started (new-loop arguments)))
     (ref-set! loop (Some started))
     (with-files (lambda () (start-loop! started)))))
  ((Nil) (panic "usage: develop ROOT RUNTIME CLIENT REQUEST ...")))
