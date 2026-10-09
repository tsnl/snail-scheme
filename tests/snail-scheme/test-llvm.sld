(define-library (snail-scheme test-llvm)
  (export test-llvm)
  (import (scheme base) (snail-scheme vm) (snail-scheme llvm)
          (snail-scheme test-utils))
  (begin
    ;; Two calls share a continuation, closures repeat both destinations, and
    ;; the tail call's unused resume operand must not create a switch case.
    (define (shared-destinations scale)
      (make-vm-program 0 0
                       (list (make-instruction 0 'return '() #f #f)
                             (make-instruction scale 'call (list 0 (* 4 scale) 0) #f #f)
                             (make-instruction (* 2 scale) 'call (list 0 (* 4 scale) 0) #f #f)
                             (make-instruction (* 3 scale) 'close (list (* 4 scale) 0 0 0 0) 0 #f)
                             (make-instruction (* 4 scale) 'return '() #f #f)
                             (make-instruction (* 5 scale) 'close '(0 0 0 0 0) 0 #f)
                             (make-instruction (* 6 scale) 'call (list 0 (* 2 scale) 1) #f #f))
                       '() '() '()))

    (define (llvm-lines program)
      (let ((output (open-output-string)))
        (write-llvm-program program output)
        (let ((input (open-input-string (get-output-string output))))
          (let loop ((lines '()))
            (let ((line (read-line input)))
              (if (eof-object? line) (reverse lines) (loop (cons line lines))))))))

    (define (switch-cases lines)
      (cond ((null? lines) '())
            ((and (>= (string-length (car lines)) 8)
                  (string=? (substring (car lines) 0 8) "    i32 "))
             (cons (car lines) (switch-cases (cdr lines))))
            (else (switch-cases (cdr lines)))))

    (define (test-dispatch-destinations)
      (for-each
       (lambda (scale)
         (let* ((program (shared-destinations scale))
                (lines (llvm-lines program)) (target (number->string (* 4 scale))))
           (expect (switch-cases lines)
                   (list "    i32 4294967295, label %done"
                         "    i32 0, label %b0"
                         (string-append "    i32 " target ", label %b" target)))
           (expect (llvm-lines program) lines)))
       '(1 1000000))
      (expect (if (member (string-append "  %pc = phi i32 [ %start, %entry ], "
                                         "[ %next0, %b0 ], [ %next1, %b1 ], [ %next2, %b2 ], "
                                         "[ %next4, %b4 ], [ %next6, %b6 ]")
                          (llvm-lines (shared-destinations 1))) #t #f)
              #t))

    (define (test-llvm)
      (run-test test-dispatch-destinations))))
