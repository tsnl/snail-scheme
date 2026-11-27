;; Passage IDs are saved with the shift; keep them stable when editing dialogue.
(define-library (apps last-mile lines)
  (export conversation)
  (import
   (snail core base)
   (snail shell game dialogue))
  (begin
    (define conversation (→ Dialogue)
      (new Dialogue
        (start "passenger")
        (pages
         (list
          (new Passage
            (id "passenger")
            (lines
             (list
              "Rosa: Jones Street, please. If we take Lombard I can show you where we shot that last reel."))
            (choices (list (new Reply (text "Which turn?") (next "directions"))
                           (new Reply (text "How did the picture turn out?") (next "picture")))))
          (new Passage
            (id "directions")
            (lines
             (list
              "Rosa: Down the bends, across Leavenworth, then left on Jones. I’ll get out at the curb."))
            (choices (Nil)))
          (new Passage
            (id "picture")
            (lines
             (list
              "Rosa: We caught the last of the light. The cab ride home took longer than the shoot."))
            (choices (Nil)))))))))
