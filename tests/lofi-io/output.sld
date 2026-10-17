(import
 (lofi base)
 (lofi io))

;; ---- Real text files and concrete callback results ----

(def format-number (-> I64 I64)
     (lambda (number)
       (call-with-output-file "number.txt"
         (lambda (port)
           (begin (write-i64 number port) (newline port) number)))))

(def unicode (-> I64)
     (lambda ()
       (call-with-output-file "λ😀.txt"
         (lambda (port)
           (begin
             (write-string "\x0;λ😀\x10ffff;" port)
             (write-char #\newline port)
             (ann 42 I64))))))

(def callback-result (-> F64)
     (lambda ()
       (call-with-output-file "result.txt" (lambda (port)
                                             (begin (write-string "answer" port) 1.25)))))

(def exists (-> Bool)
     (lambda () (file-exists? "λ😀.txt")))

(def remove (-> Unit)
     (lambda () (delete-file "λ😀.txt")))

(def close-alias (-> Unit)
     (lambda ()
       (begin (let port (open-output-file "alias.txt"))
              (begin (let alias port)
                     (begin
                       (write-string "once" alias)
                       (close-output-port port)
                       (close-output-port alias))))))

(def callback-close (-> I64)
     (lambda ()
       (call-with-output-file "self-close.txt"
         (lambda (port)
           (begin (write-string "closed" port) (close-output-port port) (ann 19 I64))))))

;; ---- Each failure runs in a fresh, terminal instance ----

(def escaped-alias (-> Unit)
     (lambda ()
       (begin (let port (call-with-output-file "escaped.txt" (lambda (port) port)))
              (begin
                (close-output-port port)
                (write-char #\x port)))))

(def missing-directory (-> Unit)
     (lambda ()
       (call-with-output-file "missing/file.txt" (lambda (port) (write-char #\x port)))))

(def nul-path (-> Bool)
     (lambda () (file-exists? "nul\x0;path")))

(def delete-absent (-> Unit)
     (lambda () (delete-file "absent.txt")))

(def callback-trap (-> Unit)
     (lambda ()
       (call-with-output-file "trap.txt" (lambda (port)
                                           (begin (write-string "buffered" port) (unreachable))))))

(def close-failure (-> Unit)
     (lambda ()
       (begin (let lofi-migration-let-1 (open-output-file "first.txt")) (let lofi-migration-let-2 (open-output-file "second.txt"))
              (let first lofi-migration-let-1)
              (let second lofi-migration-let-2)
              (begin
                (write-string "first" first)
                (write-string "second" second)
                (close-output-port first)))))

;; Declaring the scalar character parameter as I32 deliberately tests malformed
;; foreign callers. Public Scheme callers use Char and cannot create a surrogate.
(define-extern raw-begin "snail.library" "snail:io/path-begin" (-> Unit))
(define-extern raw-character "snail.library" "snail:io/path-character" (-> I32 Unit))
(define-extern raw-close "snail.library" "snail:io/close" (-> I32 Unit))

(def invalid-character (-> Unit)
     (lambda ()
       (begin (raw-begin) (raw-character (ann 55296 I32)))))

(def invalid-handle (-> Unit)
     (lambda () (raw-close (ann -1 I32))))

(def interrupted-path (-> Unit)
     (lambda ()
       (begin (raw-begin) (raw-character (ann 65 I32)) (unreachable))))
(unit)
