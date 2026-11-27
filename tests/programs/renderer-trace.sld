;; Trace headers count as logical commands with any number of inline chunks.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell graphics api-trace))

(record Cursor
  ((at I64)))
(record Written
  ((lines (List String))))

(define (commands) (→ String)
  (let* ((w (new Written (lines (Nil))))
         (sink (new OutputPort (write-string (lambda (s) (set! (● w lines) (Cons s (● w lines)))))))
         (bytes (array-generate 24579 (lambda (i) (i32->u8 (i64->i32 (remainder i 251)))))))
    (write-command! sink "mesh" (JsonInteger 7) (list (array) bytes))
    (write-command! sink "draw" (JsonInteger 8) (Nil))
    (string-concatenate (reverse (● w lines)))))

(define (source (text String) (cursor Cursor)) (→ InputPort)
  (new InputPort (read-char (lambda ()
                              (let ((i (● cursor at)))
                                (if (= i (string-length text)) (None)
                                    (begin
                                      (set! (● cursor at) (+ i 1))
                                      (Some (string-ref text i)))))))))

(define (main (out OutputPort)) (→ Unit)
  (let* ((text (commands)) (cursor (new Cursor (at 0))) (in (source text cursor))
         (run (lambda ((cmd ApiCommand)) (→ Unit)
                (write-line out (● cmd op))
                (when (string=? (● cmd op) "mesh")
                  (let ((b (command-block cmd 1)))
                    (unless (and (= (array-length (command-block cmd 0)) 0)
                                 (= (array-length b) 24579)
                                 (= (u8->i32 (array-ref b 24578)) (i64->i32 (remainder 24578 251))))
                      (panic "lost inline mesh bytes")))))))
    (write-line out (show (replay-commands! in (Some 0) run)))
    (write-line out (show (● cursor at)))
    (write-line out (show (replay-commands! in (Some 1) run)))
    (write-line out (show (replay-commands! in (None) run)))
    (write-line out (show (replay-commands! in (Some 4) run)))))
