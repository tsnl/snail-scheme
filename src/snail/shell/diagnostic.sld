;; Source diagnostics at the command-line boundary: text for people or
;; JSON lines for tools. Neither choice changes the compiler's errors.
(define-library (snail shell diagnostic)
  (export
   ErrorFormat TextErrors JsonErrors
   diagnostics->output
   message->output
   source-diagnostic->json
   diagnostic->json
   report-diagnostics
   report-error)
  (import
   (snail core base)
   (only (snail core io) write-error exit)
   (snail shell log)
   (snail shell json)
   (only (snail shell compiler read)
         Loc
         Diagnostics
         SourceDiagnostic
         diagnostics->list
         diagnostic->string))
  (begin

    ;; ---- Rendering ----

    (enum ErrorFormat
      (TextErrors)
      (JsonErrors))

    (define (diagnostics->output (format ErrorFormat) (diagnostics Diagnostics) (color? Bool))
      (→ String)
      (string-join
       (map (lambda (diagnostic)
              (match format
                ((TextErrors) (log->string (Error) (diagnostic->string diagnostic) color?))
                ((JsonErrors) (json->string (source-diagnostic->json diagnostic)))))
            (diagnostics->list diagnostics))
       "\n"))

    (define (message->output (format ErrorFormat) (message String) (color? Bool)) (→ String)
      (match format
        ((TextErrors) (log->string (Error) message color?))
        ((JsonErrors) (json->string (diagnostic->json message (JsonNull))))))

    ;; ---- JSON ----

    ;; Keep the resident builder's schema: a location in line zero is not
    ;; a source point, so its file remains in the message instead.
    (define (source-diagnostic->json (diagnostic SourceDiagnostic)) (→ Json)
      (let ((loc (● diagnostic loc)))
        (cond ((= (string-length (● loc file)) 0)
               (diagnostic->json (● diagnostic message) (JsonNull)))
              ((and (> (● loc line) 0) (> (● loc column) 0))
               (diagnostic->json (● diagnostic message) (source->json loc)))
              (else (diagnostic->json (diagnostic->string diagnostic) (JsonNull))))))

    (define (source->json (loc Loc)) (→ Json)
      (JsonObject (list (Pair "file" (JsonString (● loc file)))
                        (Pair "line" (JsonInteger (● loc line)))
                        (Pair "column" (JsonInteger (● loc column))))))

    (define (diagnostic->json (message String) (source Json)) (→ Json)
      (JsonObject (list (Pair "severity" (JsonString "error"))
                        (Pair "message" (JsonString message))
                        (Pair "source" source))))

    ;; ---- Reporting ----

    (define (report-diagnostics (format ErrorFormat) (diagnostics Diagnostics))
      (→ A) (! mut) (∀ A)
      (write-error
       (string-append (diagnostics->output format diagnostics (output-color? format)) "\n"))
      (exit 1))

    (define (report-error (format ErrorFormat) (message String)) (→ A) (! mut) (∀ A)
      (write-error (string-append (message->output format message (output-color? format)) "\n"))
      (exit 1))

    (define (output-color? (format ErrorFormat)) (→ Bool)
      (match format ((TextErrors) (log-color?)) ((JsonErrors) #f)))

    ))
