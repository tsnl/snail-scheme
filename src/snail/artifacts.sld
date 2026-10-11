;; Runtime lookup uses the installed executable, never argv[0] or the working
;; directory. The Chibi host can opt into the same layout through an explicit root.
(define-library (snail artifacts)
  (export artifact-path find-artifact)
  (import (scheme base))
  (begin
    (define (artifact-path name)
      (or (find-artifact name) (error "required artifact is missing" name))))
  (cond-expand
   (snail-scheme
    (import (only (snail-scheme core) find-artifact)))
   (else
    (import (scheme file) (scheme process-context) (only (chibi filesystem) file-regular?))
    (begin
      (define (find-artifact name)
        (unless (and (string? name) (> (string-length name) 0) (not (member name '("." "..")))
                     (let loop ((characters (string->list name)))
                       (or (null? characters)
                           (and (not (memv (char->integer (car characters)) '(0 47 92)))
                                (loop (cdr characters))))))
          (error "artifact name must be a filename" name))
        (let ((root (get-environment-variable "SNAIL_ARTIFACT_ROOT")))
          (and root (let ((path (string-append root "/" name))) (and (file-regular? path) path)))))))))
