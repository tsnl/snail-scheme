;; A dialogue book stays with the application. Its cursor alone is saved.
;; A page contains spoken lines and, after its last line, a set of replies.
(define-library (snail shell game dialogue)
  (export Dialogue
          Passage
          Reply
          Cursor
          open-dialogue
          spoken
          replies
          continue-dialogue
          answer-dialogue)
  (import
   (snail core base)
   (snail shell wire))
  (begin
    (record Reply
      ((text String)
       (next String)))
    (record Passage
      ((id String)
       (lines (List String))
       (choices (List Reply))))
    (record Dialogue
      ((start String)
       (pages (List Passage))))
    (record Cursor
      ((page String)
       (line I64))
      (deriving Serialize Deserialize))
    (define (page-at (book Dialogue) (id String)) (→ (Option Passage))
      (find (lambda (p) (string=? id (● p id))) (● book pages)))
    (define (enter-page (book Dialogue) (id String)) (→ (Option Cursor))
      (match (page-at book id)
        ((Some p) (if (and (null? (● p lines)) (null? (● p choices))) (None)
                      (Some (new Cursor (page id) (line 0)))))
        ((None) (None))))
    (define (open-dialogue (book Dialogue)) (→ (Option Cursor)) (enter-page book (● book start)))
    (define (spoken (book Dialogue) (at Cursor)) (→ String)
      (match (page-at book (● at page))
        ((Some p)
         (let ((n (● at line)))
           (if (and (>= n 0) (< n (length (● p lines)))) (list-ref (● p lines) n) "")))
        (_ "")))
    (define (replies (book Dialogue) (at Cursor)) (→ (List Reply))
      (match (page-at book (● at page))
        ((Some p) (if (>= (+ 1 (● at line)) (length (● p lines))) (● p choices) (Nil)))
        (_ (Nil))))
    (define (continue-dialogue (book Dialogue) (at Cursor)) (→ (Option Cursor))
      (match (page-at book (● at page))
        ((Some p) (let ((n (+ 1 (● at line))))
                    (cond ((< n (length (● p lines))) (Some (new Cursor (page (● p id)) (line n))))
                          ((null? (● p choices)) (None)) (else (Some at)))))
        (_ (None))))
    (define (answer-dialogue (book Dialogue) (at Cursor) (index I64)) (→ (Option Cursor))
      (let ((options (replies book at)))
        (if (and (>= index 0) (< index (length options)))
            (enter-page book (● (list-ref options index) next))
            (Some at))))))
