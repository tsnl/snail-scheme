(import (lofi base) (lofi io))

(def input (current-input-port))
(def alias (current-input-port))
(def output (current-output-port))

;; Peek, close and read through different aliases. Closing stdin must preserve
;; both the process descriptor and its buffered lookahead, including at EOF.
(def copy (-> I64)
     (lambda ()
       (begin (let first (peek-char input))
              (begin
                (close-input-port input)
                (match first
                  ((character-end)
                   (if (character-end? (read-char alias)) (ann 0 I64) (unreachable)))
                  ((character-value expected)
                   (match (read-char alias)
                     ((character-end) (unreachable))
                     ((character-value actual)
                      (if (char=? actual expected)
                          (begin (write-char actual output) (copy))
                          (unreachable))))))))))

(copy)
