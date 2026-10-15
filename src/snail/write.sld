;; Typed datum output. Scheme owns graph inspection, syntax and continuations;
;; Rust receives only each Unicode scalar and the explicit output-port ID.
(define-library (snail write)
  (export write display write-datum display-datum)
  (import (snail strict) (snail io) (snail datum) (snail number) (snail bytes))
  (begin

    (define-syntax cond
      (syntax-rules (else)
        ((_ (else body ...)) (begin body ...))
        ((_ (test body ...) rest ...) (if test (begin body ...) (cond rest ...)))))

    ;; ---- Query-local storage identities and graph analysis ----

    ;; Membership means visited; active distinguishes a back edge from sharing.
    ;; A label starts at -1 and is assigned just before its first definition.
    ;; The table retains ordinary traced values, never unrooted native pointers.
    ;; Linear identity lookup keeps the existing mutable storage contract: two
    ;; datum-pair/vector views of the same storage must share one graph entry.
    (define-data OutputNode
      (output-node (value Datum output-node-value) (active (Ref Bool) output-node-active)
                   (repeated (Ref Bool) output-node-repeated) (label (Ref I64) output-node-label)))
    (define-data OutputGraph
      (output-graph (nodes (Ref (List OutputNode)) output-graph-nodes)
                    (cyclic (Ref Bool) output-graph-cyclic) (next-label (Ref I64) output-graph-next-label)))
    (define-data OutputScan
      (scan-done) (scan-value (value Datum) (pending OutputScan))
      (scan-elements (values (Vector Datum)) (index I64) (pending OutputScan))
      (scan-leave (node OutputNode) (pending OutputScan)))
    (: mutable-output? (-> Datum Bool))
    (define (mutable-output? value)
      (let ((kind (datum-kind value))) (or (= kind 3) (= kind 6) (= kind 7) (= kind 8))))
    ;; A nonempty result starts with the matching entry; an empty list is absent.
    (: find-output-node (-> Datum (List OutputNode) (List OutputNode)))
    (define (find-output-node value nodes)
      (if (or (null? nodes) (datum-eq? value (output-node-value (car nodes)))) nodes
          (find-output-node value (cdr nodes))))
    (: inspect-output-graph (-> Datum OutputGraph))
    (define (inspect-output-graph value)
      (let ((graph (output-graph (ref '()) (ref #f) (ref 0))))
        (scan-output-value value (scan-done) graph) graph))
    (: continue-output-scan (-> OutputScan OutputGraph Unit))
    (define (continue-output-scan work graph)
      (match work
        ((scan-done) (unit))
        ((scan-value value pending) (scan-output-value value pending graph))
        ((scan-elements values index pending) (scan-output-elements values index pending graph))
        ((scan-leave node pending)
         (ref-set! (output-node-active node) #f) (continue-output-scan pending graph))))
    (: record-output-repeat! (-> OutputNode OutputGraph Unit))
    (define (record-output-repeat! node graph)
      (ref-set! (output-node-repeated node) #t)
      (when (ref-get (output-node-active node)) (ref-set! (output-graph-cyclic graph) #t)))
    (: scan-output-value (-> Datum OutputScan OutputGraph Unit))
    (define (scan-output-value value pending graph)
      (if (not (mutable-output? value)) (continue-output-scan pending graph)
          (let ((found (find-output-node value (ref-get (output-graph-nodes graph)))))
            (if (null? found)
                (let ((node (output-node value (ref #t) (ref #f) (ref -1))))
                  (ref-set! (output-graph-nodes graph) (cons node (ref-get (output-graph-nodes graph))))
                  (scan-output-children value (scan-leave node pending) graph))
                (begin (record-output-repeat! (car found) graph) (continue-output-scan pending graph))))))
    (: scan-output-children (-> Datum OutputScan OutputGraph Unit))
    (define (scan-output-children value pending graph)
      (let ((kind (datum-kind value)))
        (if (= kind 6)
            (scan-output-value (datum-car value) (scan-value (datum-cdr value) pending) graph)
            (if (= kind 7) (scan-output-elements (datum-vector-values value) 0 pending graph)
                (continue-output-scan pending graph)))))
    (: scan-output-elements (-> (Vector Datum) I64 OutputScan OutputGraph Unit))
    (define (scan-output-elements values index pending graph)
      (if (= index (vector-length values)) (continue-output-scan pending graph)
          (scan-output-value (vector-ref values index) (scan-elements values (+ index 1) pending) graph)))

    ;; ---- First-output order assigns labels only when a cycle exists ----

    ;; Ordinary acyclic sharing expands at each occurrence. If any cycle exists,
    ;; all repeated mutable objects use #n= and #n#, including strings and bytes.
    ;; The scan visits each unique object's children once; rendering cannot call
    ;; user code or mutate that graph between inspection and its final lookup.
    (: labelled-output? (-> Datum OutputGraph Bool))
    (define (labelled-output? value graph)
      (and (ref-get (output-graph-cyclic graph)) (mutable-output? value)
           (ref-get (output-node-repeated (car (find-output-node value (ref-get (output-graph-nodes graph))))))))
    (: claim-output-label! (-> OutputNode OutputGraph I64))
    (define (claim-output-label! node graph)
      (let ((label (ref-get (output-graph-next-label graph))))
        (ref-set! (output-node-label node) label)
        (ref-set! (output-graph-next-label graph) (+ label 1)) label))
    ;; Return true after a reference; false after a definition or unlabelled value.
    ;; Assigning before any child is what makes a later cycle edge terminate.
    (: write-output-label? (-> Datum OutputPort OutputGraph Bool))
    (define (write-output-label? value port graph)
      (if (not (labelled-output? value graph)) #f
          (let* ((node (car (find-output-node value (ref-get (output-graph-nodes graph)))))
                 (old (ref-get (output-node-label node))) (reference? (>= old 0))
                 (label (if reference? old (claim-output-label! node graph))))
            (write-char #\# port) (write-i64 label port)
            (write-char (if reference? #\# #\=) port) reference?)))

    ;; ---- Explicit continuations keep nested output off the machine stack ----

    (define-data OutputWork
      (output-done) (output-tail (value Datum) (pending OutputWork))
      (output-elements (values (Vector Datum)) (index I64) (pending OutputWork))
      (output-close (pending OutputWork)))
    (: write-datum (-> Datum OutputPort Unit))
    (define (write-datum value port)
      (emit-output-value value #f port (inspect-output-graph value) (output-done)))
    (: display-datum (-> Datum OutputPort Unit))
    (define (display-datum value port)
      (emit-output-value value #t port (inspect-output-graph value) (output-done)))
    (: continue-output (-> OutputWork Bool OutputPort OutputGraph Unit))
    (define (continue-output work display? port graph)
      (match work
        ((output-done) (unit))
        ((output-tail value pending) (emit-output-tail value display? port graph pending))
        ((output-elements values index pending) (emit-output-elements values index display? port graph pending))
        ((output-close pending) (write-char #\) port) (continue-output pending display? port graph))))
    (: emit-output-value (-> Datum Bool OutputPort OutputGraph OutputWork Unit))
    (define (emit-output-value value display? port graph pending)
      (if (write-output-label? value port graph) (continue-output pending display? port graph)
          (emit-output-body value display? port graph pending)))
    (: emit-output-body (-> Datum Bool OutputPort OutputGraph OutputWork Unit))
    (define (emit-output-body value display? port graph pending)
      (cond
       ((datum-pair? value)
        (write-char #\( port)
        (emit-output-value (datum-car value) display? port graph
                           (output-tail (datum-cdr value) (output-close pending))))
       ((= (datum-kind value) 7)
        (write-string "#(" port)
        (emit-output-elements (datum-vector-values value) 0 display? port graph (output-close pending)))
       (else (write-output-atom value display? port) (continue-output pending display? port graph))))
    (: emit-output-tail (-> Datum Bool OutputPort OutputGraph OutputWork Unit))
    (define (emit-output-tail value display? port graph pending)
      (cond
       ((datum-null? value) (continue-output pending display? port graph))
       ((and (datum-pair? value) (not (labelled-output? value graph)))
        (write-char #\space port)
        (emit-output-value (datum-car value) display? port graph (output-tail (datum-cdr value) pending)))
       ;; Both a labelled definition and a reference must retain the pair boundary.
       (else (write-string " . " port) (emit-output-value value display? port graph pending))))
    (: emit-output-elements (-> (Vector Datum) I64 Bool OutputPort OutputGraph OutputWork Unit))
    (define (emit-output-elements values index display? port graph pending)
      (if (= index (vector-length values)) (continue-output pending display? port graph)
          (begin
            (when (> index 0) (write-char #\space port))
            (emit-output-value (vector-ref values index) display? port graph
                               (output-elements values (+ index 1) pending)))))

    ;; ---- Reader-compatible atomic spelling and recursive display ----

    ;; This exhaustive dispatch keeps every atomic Datum representation visible.
    (: write-output-atom (-> Datum Bool OutputPort Unit))
    (define (write-output-atom value display? port)
      (let ((kind (datum-kind value)))
        (cond
         ((= kind 0) (write-string "()" port))
         ((= kind 1) (write-string (if (datum-boolean-value value) "#t" "#f") port))
         ((= kind 2) (write-output-character (datum-character-value value) display? port))
         ((= kind 3) (if display? (write-string (datum-string-value value) port)
                         (write-delimited-text (datum-string-value value) #\" port)))
         ((= kind 4) (write-output-symbol (datum-symbol-value value) display? port))
         ((= kind 5) (write-string (number->string (datum-number-value value)) port))
         ((= kind 8) (write-output-bytes (datum-bytevector-values value) port))
         (else (datum-fail "write: expected an atomic datum")))))
    (: control-character? (-> Char Bool))
    (define (control-character? character)
      (let ((code (char->integer character))) (or (< code 32) (and (>= code 127) (<= code 159)))))
    (: write-hex-digits (-> I64 OutputPort Unit))
    (define (write-hex-digits value port)
      (unless (< value 16) (write-hex-digits (quotient value 16) port))
      (write-char (string-ref "0123456789abcdef" (remainder value 16)) port))
    (: write-output-character (-> Char Bool OutputPort Unit))
    (define (write-output-character character display? port)
      (if display? (write-char character port)
          (begin
            (write-string "#\\" port)
            (cond
             ((char=? character #\space) (write-string "space" port))
             ((char=? character #\newline) (write-string "newline" port))
             ((char=? character #\tab) (write-string "tab" port))
             ((char=? character #\return) (write-string "return" port))
             ((control-character? character) (write-char #\x port) (write-hex-digits (char->integer character) port))
             (else (write-char character port))))))
    (: write-delimited-text (-> String Char OutputPort Unit))
    (define (write-delimited-text text delimiter port)
      (write-char delimiter port)
      (let loop ((index 0))
        (if (= index (string-length text)) (write-char delimiter port)
            (begin (write-escaped-character (string-ref text index) delimiter port) (loop (+ index 1))))))
    (: write-escaped-character (-> Char Char OutputPort Unit))
    (define (write-escaped-character character delimiter port)
      (cond
       ((or (char=? character delimiter) (char=? character #\\))
        (write-char #\\ port) (write-char character port))
       ((char=? character #\newline) (write-string "\\n" port))
       ((char=? character #\return) (write-string "\\r" port))
       ((char=? character #\tab) (write-string "\\t" port))
       ((control-character? character)
        (write-string "\\x" port) (write-hex-digits (char->integer character) port) (write-char #\; port))
       (else (write-char character port))))
    (: bare-output-symbol? (-> String Bool))
    (define (bare-output-symbol? text)
      (and (identifier? text)
           (match (string->number text)
             ((not-a-number) #t) ((parsed-number value) #f) ((number-error message) #f))))
    (: write-output-symbol (-> Symbol Bool OutputPort Unit))
    (define (write-output-symbol value display? port)
      (let ((text (symbol->string value)))
        (if (or display? (bare-output-symbol? text)) (write-string text port)
            (write-delimited-text text #\| port))))
    (: write-output-bytes (-> Bytevector OutputPort Unit))
    (define (write-output-bytes bytes port)
      (write-string "#u8(" port)
      (let loop ((index 0))
        (if (= index (bytevector-length bytes)) (write-char #\) port)
            (begin
              (when (> index 0) (write-char #\space port))
              (write-i64 (bytevector-u8-ref bytes index) port) (loop (+ index 1))))))

    ;; ---- Default output is an ordinary call to the stable stdout port ----

    (define-overload write (-> Datum OutputPort Unit) write-datum)
    (define-overload write (-> Datum Unit) (lambda (value) (write-datum value (current-output-port))))
    (define-overload display (-> Datum OutputPort Unit) display-datum)
    (define-overload display (-> Datum Unit) (lambda (value) (display-datum value (current-output-port)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-write)
    (begin
      (: test-output-graph (-> Bool))
      (define (test-output-graph)
        (let* ((pair (datum-cons (datum-null) (datum-null)))
               (shared (datum-vector (vector pair pair))) (ordinary (inspect-output-graph shared)))
          (datum-set-car! pair shared)
          (let ((cyclic (inspect-output-graph shared)))
            (and (not (ref-get (output-graph-cyclic ordinary)))
                 (ref-get (output-graph-cyclic cyclic))
                 (labelled-output? pair cyclic) (labelled-output? shared cyclic)
                 (datum-eq? (datum-car pair) shared)))))
      (: test-write (-> I64))
      (define (test-write) (if (test-output-graph) 42 0))))))
