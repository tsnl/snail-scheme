(import
 (lofi base)
 (control protocol))

(effect Message
  ((message ctl (-> String I64 String))))

(effect Other
  ((other ctl (-> I64))))

(effect Tag
  ((tag fun (-> I64))))

(effect Mixed
  ((fast fun (-> I64))
   (slow ctl (-> I64))))

(effect Test
  ((pause (-> I32 Unit)))
  (host "lofi.control.test"
        ((pause "pause"))))

(effect Relay
  ((relay ctl (-> (-> I64 I64 ! Relay) I64))))

(: early (-> I64))
(define (early)
  (handle Choice
      ((choose (lambda (resume) 42)))
    (+ 100 (choose))))

(: once (-> I64))
(define (once)
  (handle Choice
      ((choose (lambda (resume) (+ 1 (resume 20)))))
    (+ 21 (choose))))

(: repeated (-> I64))
(define (repeated)
  (handle Choice
      ((choose (lambda (resume) (+ 1 (resume 0)))))
    (choose)
    (choose)
    10))

(: later-abort (-> I64 ! mut))
(define (later-abort)
  (let ((calls (ref 0)))
    (handle Choice
        ((choose (lambda (resume)
                   (ref-set! calls (+ 1 (ref-get calls)))
                   (if (= (ref-get calls) 1) (+ 2 (resume 0)) 40))))
      (choose)
      (choose)
      (panic "the abandoned suffix ran"))))

(: abort-then-forward (-> I64 ! Other mut))
(define (abort-then-forward)
  (let ((calls (ref 0)))
    (handle Choice
        ((choose (lambda (resume)
                   (ref-set! calls (+ 1 (ref-get calls)))
                   (if (= (ref-get calls) 1)
                       (let ((answer (resume 0))) (+ answer (other)))
                       40))))
      (choose)
      (choose)
      (panic "the abandoned suffix ran"))))

(: surviving-clause (-> I64 ! mut))
(define (surviving-clause)
  (handle Other
      ((other (lambda (resume) (+ 100 (resume 3)))))
    (abort-then-forward)))

(: surviving-clause-abort (-> I64 ! mut))
(define (surviving-clause-abort)
  (handle Other
      ((other (lambda (resume) 77)))
    (abort-then-forward)))

(: no-operation (-> I64))
(define (no-operation)
  (handle Choice
      ((choose (lambda (resume) (panic "unused handler"))))
    42))

(: library-operation (-> I64))
(define (library-operation)
  (handle Choice
      ((choose (lambda (resume) (resume 21))))
    (choose-twice)))

(: twice (-> I64))
(define (twice)
  (handle Choice
      ((choose (lambda (resume) (resume 1) (resume 2))))
    (choose)))

(: forwarding (-> I64))
(define (forwarding)
  (handle Choice
      ((choose (lambda (resume) (+ 1000 (resume 20)))))
    (handle Choice
        ((choose (lambda (resume) (+ 10 (resume (+ 1 (choose)))))))
      (+ 2 (choose)))))

(: forwarding-abort (-> I64))
(define (forwarding-abort)
  (handle Choice
      ((choose (lambda (resume) 77)))
    (handle Choice
        ((choose (lambda (resume) (resume (choose)))))
      (+ 2 (choose)))))

(: forwarding-after-resume (-> I64))
(define (forwarding-after-resume)
  (handle Choice
      ((choose (lambda (resume) (+ 1000 (resume 20)))))
    (handle Choice
        ((choose (lambda (resume)
                   (let ((answer (resume 2))) (+ answer (choose))))))
      (choose))))

(: nested (-> I64))
(define (nested)
  (handle Choice
      ((choose (lambda (resume) (+ 100 (resume 3)))))
    (handle Other
        ((other (lambda (resume) (+ 5 (resume 7)))))
      (+ (choose) (other)))))

(: nested-abort (-> I64))
(define (nested-abort)
  (handle Choice
      ((choose (lambda (resume) 77)))
    (handle Other
        ((other (lambda (resume) (resume 7))))
      (+ (choose) (other)))))

(: descendant-resume (-> I64))
(define (descendant-resume)
  (handle Choice
      ((choose (lambda (resume)
                 (handle Other
                     ((other (lambda (inner-resume) (resume 7))))
                   (other)))))
    (+ 35 (choose))))

;; A closure passed into an enclosing control clause is still live, but its
;; captured outer answer is already owned by that enclosing clause. This
;; prototype rejects the crossing instead of treating it as scoped resume.
(: crossing-resume (-> I64))
(define (crossing-resume)
  (handle Relay
      ((relay (lambda (continuation resume) 99)))
    (handle Relay
        ((relay (lambda (continuation resume) (continuation 1))))
      (handle Choice
          ((choose (lambda (resume) (relay resume))))
        (choose)
        (relay (lambda (n) n))
        10))))

(: representations (-> I64))
(define (representations)
  (handle Message
      ((message (lambda (text number resume) (+ 1 (resume (string-append text (show number)))))))
    (string-length (message "a" 5))))

(: captured (-> I64 I64))
(define (captured n)
  (handle Choice
      ((choose (lambda (resume) (+ n (resume n)))))
    (+ 1 (choose))))

(: fun-only (-> I64))
(define (fun-only)
  (handle Tag
      ((tag (lambda () 1)))
    (handle Tag
        ((tag (lambda () (+ 2 (tag)))))
      (tag))))

(: mixed (-> I64))
(define (mixed)
  (handle Mixed
      ((fast (lambda () 7))
       (slow (lambda (resume) (resume 3))))
    (+ (fast) (slow))))

;; The handler sees Tag=1, while the suspended body keeps Tag=2. Both
;; foreign waits must release and reacquire the host's execution lease.
(: context (-> I64 ! Test))
(define (context)
  (handle Tag
      ((tag (lambda () 1)))
    (handle Choice
        ((choose (lambda (resume)
                   (let ((before (tag)))
                     (pause 1)
                     (+ (* 100 before) (resume 5))))))
      (handle Tag
          ((tag (lambda () 2)))
        (pause 2)
        (+ (choose) (tag))))))

(: choosing-zero (All (A e) (-> (-> A ! Choice e) A ! e)))
(define (choosing-zero action)
  (handle Choice
      ((choose (lambda (resume) (resume 0))))
    (action)))

(: polymorphic (-> I64 ! Test))
(define (polymorphic)
  (+ (choosing-zero (lambda () (+ 1 (choose))))
     (string-length (choosing-zero (lambda () (pause 3) (choose) "abc")))))

(: saved (Ref (-> I64 I64 ! mut)))
(define saved (ref (lambda (value) value)))

(: save-and-return (-> I64 ! mut))
(define (save-and-return)
  (handle Choice
      ((choose (lambda (resume) (ref-set! saved resume) 42)))
    (choose)))

(: call-saved (-> I64 ! mut))
(define (call-saved)
  ((ref-get saved) 0))

(: handler-trap (-> I64))
(define (handler-trap)
  (handle Choice
      ((choose (lambda (resume) (panic "handler trap"))))
    (choose)))

(: body-trap (-> I64))
(define (body-trap)
  (handle Choice
      ((choose (lambda (resume) (resume 1))))
    (choose)
    (handle Tag
        ((tag (lambda () 2)))
      (panic "body trap"))))

(: handler-rejection (-> I64 ! Test))
(define (handler-rejection)
  (handle Choice
      ((choose (lambda (resume) (pause 4) (resume 1))))
    (choose)))

(: body-rejection (-> I64 ! Test))
(define (body-rejection)
  (handle Choice
      ((choose (lambda (resume) (resume 1))))
    (choose)
    (pause 5)
    1))

(: handler-wasm-trap (-> I64))
(define (handler-wasm-trap)
  (handle Choice
      ((choose (lambda (resume) (quotient 1 0))))
    (choose)))

(: body-wasm-trap (-> I64))
(define (body-wasm-trap)
  (handle Choice
      ((choose (lambda (resume) (resume 0))))
    (quotient 1 (choose))))

(expose early "early")
(expose once "once")
(expose repeated "repeated")
(expose later-abort "later-abort")
(expose surviving-clause "surviving-clause")
(expose surviving-clause-abort "surviving-clause-abort")
(expose no-operation "no-operation")
(expose library-operation "library-operation")
(expose twice "twice")
(expose forwarding "forwarding")
(expose forwarding-abort "forwarding-abort")
(expose forwarding-after-resume "forwarding-after-resume")
(expose nested "nested")
(expose nested-abort "nested-abort")
(expose descendant-resume "descendant-resume")
(expose crossing-resume "crossing-resume")
(expose representations "representations")
(expose captured "captured")
(expose fun-only "fun-only")
(expose mixed "mixed")
(expose context "context")
(expose polymorphic "polymorphic")
(expose save-and-return "save-and-return")
(expose call-saved "call-saved")
(expose handler-trap "handler-trap")
(expose body-trap "body-trap")
(expose handler-rejection "handler-rejection")
(expose body-rejection "body-rejection")
(expose handler-wasm-trap "handler-wasm-trap")
(expose body-wasm-trap "body-wasm-trap")
