;; Pair and record layouts keep the object itself as its identity. Specialized
;; fields are native Wasm payloads in that object; generic fields retain raw
;; carriers, including envelopes whose source consumption has not happened yet.
(define-library (snail-scheme wasm-fields)
  (export make-field-layouts intern-field-layout field-layout-type field-layout-codecs
          field-layout-new field-layout-read field-layout-write field-definitions)
  (import (scheme base) (scheme cxr) (snail-scheme wasm-storage) (snail-scheme wasm-representation))
  (begin

    ;; ---- Fixed physical layouts ----

    (define-record-type <field-layouts>
      (make-field-layouts-with entries) field-layouts?
      (entries layout-entries set-layout-entries!))
    (define-record-type <field-layout>
      (make-field-layout kind codecs id) field-layout?
      (kind layout-kind) (codecs field-layout-codecs) (id layout-id))
    (define (make-field-layouts) (make-field-layouts-with '()))
    (define (all-boxed? codecs)
      (or (null? codecs) (and (= (codec-id (car codecs)) 0) (all-boxed? (cdr codecs)))))

    (define (intern-field-layout kind codecs layouts)
      (unless (and (memq kind '(pair record)) (or (eq? kind 'record) (= (length codecs) 2)))
        (error "invalid fixed field layout" kind codecs))
      (if (or (not (storage-optimizations-enabled)) (and (eq? kind 'pair) (all-boxed? codecs)))
          (make-field-layout kind (map (lambda (unused) (car storage-codecs)) codecs) #f)
          (let find ((entries (layout-entries layouts)))
            (cond ((null? entries)
                   (let ((layout (make-field-layout kind codecs (+ 1 (length (layout-entries layouts))))))
                     (set-layout-entries! layouts (cons layout (layout-entries layouts))) layout))
                  ((and (eq? kind (layout-kind (car entries))) (equal? codecs (field-layout-codecs (car entries)))) (car entries))
                  (else (find (cdr entries)))))))

    (define (layout-symbol layout operation)
      (string->symbol (string-append "$" (symbol->string (layout-kind layout)) ":" operation
                                     (if (layout-id layout) (number->string (layout-id layout)) "boxed"))))
    (define (field-layout-type layout) (layout-symbol layout ""))
    (define (category layout) (if (eq? (layout-kind layout) 'pair) '$pair '$record))
    (define (typed-category layout) (if (eq? (layout-kind layout) 'pair) '$pair:typed '$record:typed))
    (define (field-offset layout) (if (eq? (layout-kind layout) 'pair) 1 2))
    (define (field-worker layout operation index)
      (string->symbol (string-append (symbol->string (layout-symbol layout operation)) ":" (number->string index))))
    (define (numbered values)
      (let loop ((values values) (index 0))
        (if (null? values) '() (cons (cons index (car values)) (loop (cdr values) (+ index 1))))))

    (define (layout-fields layout)
      (append (if (eq? (layout-kind layout) 'record) '((field (ref $record_type))) '())
              '((field i32))
              (map (lambda (codec) `(field (mut ,(representation-wasm (codec-representation codec))))) (field-layout-codecs layout))))
    (define (layout-definition layout)
      `(type ,(field-layout-type layout) (sub final ,(typed-category layout) (struct ,@(layout-fields layout)))))

    ;; Constructors receive evaluated, encoded fields. Record fields omitted by
    ;; a source constructor contain Unspecified, not a zero payload or a hidden
    ;; uninitialized state; the solver must include that value in their codecs.
    (define (field-layout-new layout values . descriptor)
      (if (layout-id layout)
          `(struct.new ,(field-layout-type layout) ,@(if (eq? (layout-kind layout) 'record) descriptor '())
                       (i32.const ,(layout-id layout)) ,@values)
          (if (eq? (layout-kind layout) 'pair) `(struct.new $pair:boxed ,@values)
              `(struct.new $record:boxed ,(car descriptor) (array.new_fixed $slots ,(length values) ,@values)))))

    ;; ---- Generic access preserves raw carriers ----

    (define (generic-get kind index object)
      (if (eq? kind 'pair) `(call ,(if (= index 0) '$pair_car '$pair_cdr) ,object)
          `(call $record_ref ,object (i32.const ,index))))
    (define (generic-set kind index object value)
      (if (eq? kind 'pair) `(call ,(if (= index 0) '$pair_set_car '$pair_set_cdr) ,object ,value)
          `(call $record_set ,object (i32.const ,index) ,value)))
    (define (physical-get layout index object)
      `(struct.get ,(field-layout-type layout) ,(+ (field-offset layout) index)
                   (ref.cast (ref ,(field-layout-type layout)) ,object)))
    (define (physical-set layout index object value)
      `(struct.set ,(field-layout-type layout) ,(+ (field-offset layout) index)
                   (ref.cast (ref ,(field-layout-type layout)) ,object) ,value))
    (define (boxed-field layout index object)
      (box-representation (physical-get layout index object)
                          (codec-representation (list-ref (field-layout-codecs layout) index))))

    ;; A generic write validates its raw carrier without normalizing envelopes.
    ;; A valid ordinary write cannot fail this representation check: all writes
    ;; and writable escapes were joined before the object was allocated.
    (define (generic-field-write layout index)
      (let ((codec (list-ref (field-layout-codecs layout) index)))
        `(block
          (if (i32.eqz (call $storage_accepts (i32.const ,(codec-id codec)) (local.get $value)))
              (then (call $fail (i32.const 8))))
          ,(physical-set layout index '(local.get $object)
                         (unbox-representation '(local.get $value) (codec-representation codec)))
          (return))))

    (define (pair-dispatch name index write? layouts)
      `(func ,name (param $object (ref $pair)) ,@(if write? '((param $value eqref)) '((result eqref)))
             (local $layout i32)
             (if (ref.test (ref $pair:boxed) (local.get $object))
                 (then ,(if write?
                            `(block (struct.set $pair:boxed ,index (ref.cast (ref $pair:boxed) (local.get $object)) (local.get $value)) (return))
                            `(return (struct.get $pair:boxed ,index (ref.cast (ref $pair:boxed) (local.get $object)))))))
             (local.set $layout (struct.get $pair:typed 0 (ref.cast (ref $pair:typed) (local.get $object))))
             ,@(map (lambda (layout)
                      `(if (i32.eq (local.get $layout) (i32.const ,(layout-id layout)))
                           (then ,(if write? (generic-field-write layout index)
                                      `(return ,(boxed-field layout index '(local.get $object))))))) layouts)
             (call $fail (i32.const 8)) unreachable))

    (define (record-field-dispatch layout write?)
      `(block ,@(map (lambda (entry)
                       `(if (i32.eq (local.get $index) (i32.const ,(car entry)))
                            (then ,(if write? (generic-field-write layout (car entry))
                                       `(return ,(boxed-field layout (car entry) '(local.get $object)))))))
                     (numbered (field-layout-codecs layout)))
              (call $fail (i32.const 3))))

    (define (record-dispatch name write? layouts)
      `(func ,name (param $object (ref $record)) (param $index i32)
             ,@(if write? '((param $value eqref)) '((result eqref))) (local $layout i32)
             (if (ref.test (ref $record:boxed) (local.get $object))
                 (then ,(if write?
                            `(block (array.set $slots (struct.get $record:boxed 1 (ref.cast (ref $record:boxed) (local.get $object)))
                                               (local.get $index) (local.get $value)) (return))
                            `(return (array.get $slots (struct.get $record:boxed 1 (ref.cast (ref $record:boxed) (local.get $object)))
                                                (local.get $index))))))
             (local.set $layout (struct.get $record:typed 1 (ref.cast (ref $record:typed) (local.get $object))))
             ,@(map (lambda (layout)
                      `(if (i32.eq (local.get $layout) (i32.const ,(layout-id layout)))
                           (then ,(record-field-dispatch layout write?)))) layouts)
             (call $fail (i32.const 8)) unreachable))

    ;; ---- Native access with a generic-factory fallback ----

    ;; The caller proves both scalar membership and canonical-single ingress
    ;; before requesting a native field read. The fallback cannot consume an
    ;; envelope: raw copies and unknown foreign results use generic access.
    ;; Managed reference codecs admit the whole category, never one layout.
    ;;
    ;; Equal-shaped Wasm types can canonicalize. The immutable layout ID keeps
    ;; Boolean/Char/i32 boxing recipes distinct even when field types coincide.
    (define (layout-matches layout)
      `(if (result i32) (ref.test (ref ,(field-layout-type layout)) (local.get $object))
           (then (i32.eq (struct.get ,(typed-category layout) ,(- (field-offset layout) 1)
                                     (ref.cast (ref ,(typed-category layout)) (local.get $object)))
                         (i32.const ,(layout-id layout)))) (else (i32.const 0))))

    (define (field-layout-read layout index object)
      (if (layout-id layout) `(call ,(field-worker layout "read" index) ,object)
          (generic-get (layout-kind layout) index object)))
    (define (field-layout-write layout index object value)
      (if (layout-id layout) `(call ,(field-worker layout "write" index) ,object ,value)
          (generic-set (layout-kind layout) index object value)))

    (define (native-reader layout entry)
      (let ((index (car entry)) (representation (codec-representation (cdr entry))))
        `(func ,(field-worker layout "read" index) (param $object (ref ,(category layout)))
               (result ,(representation-wasm representation))
               (if (result ,(representation-wasm representation)) ,(layout-matches layout)
                   (then ,(physical-get layout index '(local.get $object)))
                   (else ,(unbox-representation (generic-get (layout-kind layout) index '(local.get $object)) representation))))))

    (define (native-writer layout entry)
      (let ((index (car entry)) (representation (codec-representation (cdr entry))))
        `(func ,(field-worker layout "write" index) (param $object (ref ,(category layout)))
               (param $value ,(representation-wasm representation))
               (if ,(layout-matches layout)
                   (then ,(physical-set layout index '(local.get $object) '(local.get $value)))
                   (else ,(generic-set (layout-kind layout) index '(local.get $object)
                                       (box-representation '(local.get $value) representation)))))))

    (define (layout-workers layout)
      (let ((fields (numbered (field-layout-codecs layout))))
        (append (map (lambda (entry) (native-reader layout entry)) fields)
                (map (lambda (entry) (native-writer layout entry)) fields))))
    (define (layouts-of-kind kind layouts)
      (cond ((null? layouts) '())
            ((eq? kind (layout-kind (car layouts))) (cons (car layouts) (layouts-of-kind kind (cdr layouts))))
            (else (layouts-of-kind kind (cdr layouts)))))

    (define (field-definitions registry)
      (let* ((layouts (reverse (layout-entries registry)))
             (pairs (layouts-of-kind 'pair layouts)) (records (layouts-of-kind 'record layouts)))
        (append (map layout-definition layouts)
                (list (pair-dispatch '$pair_car 0 #f pairs) (pair-dispatch '$pair_cdr 1 #f pairs)
                      (pair-dispatch '$pair_set_car 0 #t pairs) (pair-dispatch '$pair_set_cdr 1 #t pairs)
                      (record-dispatch '$record_ref #f records) (record-dispatch '$record_set #t records))
                (apply append (map layout-workers layouts)))))

    ))
