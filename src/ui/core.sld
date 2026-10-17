;; State describes the interface; one parent-to-child pass assigns rectangles.
(define-library (ui core)
  (export Size px grow Rect rect rect-x rect-y rect-width rect-height
          Ui ui-key ui-width ui-height ui-content
          label-content button-content number-content meter-content group-content
          ui-label ui-button ui-number ui-meter ui-row ui-column ui-panel ui-scroll
          Placement placement-node placement-rect placement-children layout-ui)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) datatype match I32)
   (only (lofi base) i32->i64 i64->i32))
  (begin

    ;; ---- Declared sizes and semantic content ----

    (define Size
      (datatype ()
        (fixed
         (pixels I32 fixed-pixels))
        (weighted
         (weight I32 weighted-weight))))
    (define (min left right) (if (< left right) left right))
    (define (max left right) (if (> left right) left right))
    (define (bounded value low high) (max low (min high value)))
    (define (px value) (fixed (bounded value 0 16384)))
    (define (grow weight) (weighted (bounded weight 1 1024)))
    (define Rect
      (datatype ()
        (rect
         (x I32 rect-x)
         (y I32 rect-y)
         (width I32 rect-width)
         (height I32 rect-height))))
    (define Ui
      (datatype (Event)
        (node
         (key String ui-key)
         (width Size ui-width)
         (height Size ui-height)
         (content (Content Event) ui-content))))
    (define Content
      (datatype (Event)
        (label-content
         (text String)
         (tone I32))
        (button-content
         (text String)
         (help String)
         (enabled Bool)
         (selected Bool)
         (event Event))
        (number-content
         (text String)
         (help String)
         (value I32)
         (minimum I32)
         (maximum I32)
         (event Event))
        (meter-content
         (text String)
         (value I32)
         (maximum I32)
         (tone I32))
        (group-content
         (axis I32)
         (gap I32)
         (padding I32)
         (panel Bool)
         (extent I32)
         (children (List (Ui Event))))))
    (define (ui-label key width height text tone)
      (node key width height (label-content text (bounded tone 0 4))))
    (define (ui-button key width height text help enabled selected event)
      (node key width height (button-content text help enabled selected event)))
    ;; Number events supply a request template; the browser replaces its first
    ;; I32 payload with the submitted value and checks the endpoint has arity one.
    (define (ui-number key width height text help value minimum maximum event)
      (node key width height (number-content text help value minimum maximum event)))
    (define (ui-meter key width height text value maximum tone)
      (node key width height (meter-content text value (max 1 maximum) (bounded tone 0 4))))
    (define (ui-row key width height gap children)
      (node key width height (group-content 0 (bounded gap 0 256) 0 #f 0 children)))
    (define (ui-column key width height gap children)
      (node key width height (group-content 1 (bounded gap 0 256) 0 #f 0 children)))
    (define (ui-panel key width height padding gap children)
      (node key width height (group-content 1 (bounded gap 0 256) (bounded padding 0 256) #t 0 children)))
    (define (ui-scroll key width height extent gap children)
      (node key width height (group-content 1 (bounded gap 0 256) 0 #f (bounded extent 1 16384) children)))

    ;; ---- A parent allocates only its immediate children's declared sizes ----

    (define Placement
      (datatype (Event)
        (placement
         (node (Ui Event) placement-node)
         (rect Rect placement-rect)
         (children (List (Placement Event)) placement-children))))
    (define (axis-size node axis) (if (= axis 0) (ui-width node) (ui-height node)))
    (define (cross-size node axis) (if (= axis 0) (ui-height node) (ui-width node)))
    (define (fixed-size size) (match size ((fixed pixels) pixels) ((weighted weight) 0)))
    (define (weight-size size) (match size ((fixed pixels) 0) ((weighted weight) weight)))
    (define (fixed-total children axis gap)
      (if (null? children) 0
          (+ (fixed-size (axis-size (car children) axis))
             (if (null? (cdr children)) 0 (+ gap (fixed-total (cdr children) axis gap))))))
    (define (weight-total children axis)
      (if (null? children) 0
          (+ (weight-size (axis-size (car children) axis)) (weight-total (cdr children) axis))))
    (define (cross-extent size available)
      (match size ((fixed pixels) (min pixels available)) ((weighted weight) available)))
    (define (allocated-size size free weights)
      (match size
        ((fixed pixels) pixels)
        ((weighted weight)
         (if (= weights 0) 0
             (i64->i32 (quotient (* (i32->i64 free) (i32->i64 weight)) (i32->i64 weights)))))))
    (define (child-rect axis cursor extent cross)
      (if (= axis 0) (rect cursor 0 extent cross) (rect 0 cursor cross extent)))
    (define (place-children children axis available cross gap cursor free weights)
      (if (null? children) (empty-list)
          (let* ((node (car children)) (size (axis-size node axis))
                 (extent (allocated-size size free weights))
                 (bounds (child-rect axis cursor extent (cross-extent (cross-size node axis) cross))))
            (cons (place-node node bounds)
                  (place-children (cdr children) axis available cross gap (+ (+ cursor extent) gap)
                                  (if (> (weight-size size) 0) (- free extent) free)
                                  (- weights (weight-size size)))))))
    (define (group-placements children axis gap padding extent bounds)
      (let* ((width (max 0 (- (rect-width bounds) (* 2 padding))))
             (height (max 0 (- (max extent (rect-height bounds)) (* 2 padding))))
             (available (if (= axis 0) width height)) (cross (if (= axis 0) height width)))
        (place-children children axis available cross gap 0
                        (max 0 (- available (fixed-total children axis gap)))
                        (weight-total children axis))))
    (define (place-node node bounds)
      (placement node bounds
                 (match (ui-content node)
                   ((group-content axis gap padding panel extent children)
                    (group-placements children axis gap padding extent bounds))
                   ((label-content text tone) (empty-list))
                   ((button-content text help enabled selected event) (empty-list))
                   ((number-content text help value minimum maximum event) (empty-list))
                   ((meter-content text value maximum tone) (empty-list)))))
    ;; Root dimensions come from the host's allotted UI region. Fixed children
    ;; may overflow when space runs out; grow children get zero, never negatives.
    ;; Only ui-scroll exposes overflow. Text wraps within its assigned rectangle.
    (define (layout-ui width height node)
      (place-node node (rect 0 0 (bounded width 0 16384) (bounded height 0 16384))))))
