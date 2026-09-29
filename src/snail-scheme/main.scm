(import
  (scheme base)
  (snail-scheme common)
  (snail-scheme cli))

(define (main argv)
  (let*
    ((args (parse-cli-args (car argv) (cdr argv))))
    (begin
      (display-error args)
      (display-error "\n")
      (display-error "Hello, world\n"))))
