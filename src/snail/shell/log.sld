;; The small text style of tsnl/log, with full severity labels and indented
;; continuation lines. No layout depends on the terminal's width.
(define-library (snail shell log)
  (export
   Level Error Warning Info Note
   log->string
   log-color?)
  (import
   (snail core base)
   (only (snail core io)
         environment-variable
         error-terminal?))
  (begin

    ;; ---- Text ----

    (enum Level
      (Error)
      (Warning)
      (Info)
      (Note))

    (define (log->string (level Level) (message String) (color? Bool)) (→ String)
      (string-append (if color? (string-append (level-color level) (level-marker level) "\x1b;[0m")
                         (level-marker level))
                     " "
                     (string-concatenate (map log-character (string->list message)))))

    (define (level-marker (level Level)) (→ String)
      (match level ((Error) "ERROR") ((Warning) "WARNING") ((Info) "INFO") ((Note) "…")))

    (define (level-color (level Level)) (→ String)
      (match level
        ((Error) "\x1b;[31;1m")
        ((Warning) "\x1b;[33;1m")
        ((Info) "\x1b;[34;1m")
        ((Note) "\x1b;[90m")))

    (define (log-character (char Char)) (→ String)
      (cond ((char=? char #\newline) "\n  ")
            ((or (char=? char #\return) (char=? char (integer->char 0))) "")
            (else (make-string 1 char))))

    ;; ---- Terminal policy ----

    (define (log-color?) (→ Bool)
      (match (environment-variable "NO_COLOR")
        ((Some _) #f)
        ((None) (match (environment-variable "FORCE_COLOR")
                  ((Some value) (and (not (string=? value "0")) (not (string=? value ""))))
                  ((None) (match (environment-variable "TERM")
                            ((Some "dumb") #f)
                            (_ (error-terminal?))))))))

    ))
