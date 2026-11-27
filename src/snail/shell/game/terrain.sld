;; A metre-space ground mesh. Each cell indexes its own triangles, so contact
;; uses the same plane the renderer draws, including the bevel on a kerb.
(define-library (snail shell game terrain)
  (export Terrain
          read-terrain
          ground-height
          ground-slope
          SolidColumn nearby-columns
          nearby-solids
          fold-solid-spans
          collect-footprint)
  (import
   (snail core base)
   (snail shell little-endian)
   (snail shell game physics))
  (begin

    (record Terrain
      ((data Bytes)
       (west I64)
       (north I64)
       (cols I64)
       (rows I64)
       (cell I64)
       (index I64)
       (steps I64)
       (span-size I64)
       (triangles I64)
       (lines I64)
       (spans I64)))

    (define (entry (b Bytes) (base I64) (i I64)) (→ I64) (u32 b (+ base (* 4 i))))

    ;; A final sentinel bounds the last row. Every ground cell must contain
    ;; at least one triangle. An obstacle scanline may be empty.
    (define (check-index (b Bytes) (at I64) (rows I64) (end I64) (nonempty Bool)) (→ Unit)
      (unless (and (= (entry b at 0) 0) (= (entry b at rows) end)) (panic "invalid terrain index"))
      (let loop ((i 0))
        (when (< i rows)
          (let ((delta (- (entry b at (+ i 1)) (entry b at i))))
            (when (< delta (if nonempty 1 0)) (panic "unordered terrain index")))
          (loop (+ i 1)))))

    (define (check-triangles (b Bytes) (base I64) (count I64) (limit I64)) (→ Unit)
      (let loop ((i 0))
        (when (< i count)
          (let* ((at (+ base (* 18 i))) (x (u16 b at)) (z (u16 b (+ at 2)))
                 (u (u16 b (+ at 6)))
                 (v (u16 b (+ at 8)))
                 (s (u16 b (+ at 12)))
                 (t (u16 b (+ at 14))))
            (unless (and (<= (max (max x u) s) limit) (<= (max (max z v) t) limit)
                         (not (= (* (- u x) (- t z)) (* (- v z) (- s x)))))
              (panic "invalid ground triangle")))
          (loop (+ i 1)))))

    (define (check-spans (g Terrain) (line I64)) (→ Unit)
      (let* ((b (● g data))
             (end (entry b (● g lines) (+ line 1)))
             (width (* (● g steps) (* (● g cols) (● g cell)))))
        (let loop ((i (entry b (● g lines) line)) (prior 0))
          (when (< i end)
            (let* ((at (+ (● g spans) (* (● g span-size) i))) (a (u16 b at)) (z (u16 b (+ at 2))))
              (unless (and (<= prior a) (< a z) (<= z width)) (panic "invalid obstacle span"))
              (loop (+ i 1) z))))))

    ;; GRD1: origin, grid dimensions, cell size and triangle count; offsets,
    ;; nine 16-bit centimetre coordinates per triangle, then scanline spans.
    (define (read-terrain (b Bytes)) (→ Terrain)
      (unless (and (>= (array-length b) 28) (or (= (u32 b 0) 826561095)
                                                (and (= (u32 b 0) 843338311)
                                                     (>= (array-length b) 32))))
        (panic "invalid terrain header"))
      (let* ((cols (u32 b 12)) (rows (u32 b 16)) (side (u32 b 20)) (n (u32 b 24))
             (v2 (= (u32 b 0) 843338311)) (index (if v2 32 28))
             (steps (if v2 (u32 b 28) 1)) (stride (if v2 6 4)))
        (unless (and (> steps 0) (<= steps 16) (> cols 0) (<= cols 65535) (> rows 0) (<= rows 65535)
                     (> side 0) (<= side 655) (<= (* steps (* cols side)) 65535))
          (panic "invalid terrain dimensions"))
        (let* ((cells (* cols rows))
               (depth (* steps (* rows side)))
               (tris (+ index (* 4 (+ 1 cells))))
               (lines (+ tris (* n 18))) (spans (+ lines (* 4 (+ 1 depth))))
               (remaining (- (array-length b) spans)))
          (unless (and (>= remaining 0) (= (modulo remaining stride) 0))
            (panic "truncated terrain"))
          (check-index b index cells n #t)
          (check-index b lines depth (quotient remaining stride) #f)
          (check-triangles b tris n (* side 100))
          (let ((g (new Terrain (data b) (west (i32-le b 4)) (north (i32-le b 8))
                        (cols cols)
                        (rows rows)
                        (cell side) (index index) (steps steps) (span-size stride)
                        (triangles tris)
                        (lines lines)
                        (spans spans))))
            (for-each (lambda (j) (check-spans g j)) (iota depth)) g))))

    ;; Barycentric coordinates in the horizontal plane. Return the least
    ;; weight alongside the height: it is nonnegative inside the triangle.
    (define (plane (b Bytes) (i I64) (x F64) (z F64)) (→ (Pair F64 F64))
      (let* ((ax (i64->f64 (u16 b i))) (az (i64->f64 (u16 b (+ i 2))))
             (bx (- (i64->f64 (u16 b (+ i 6))) ax)) (bz (- (i64->f64 (u16 b (+ i 8))) az))
             (cx (- (i64->f64 (u16 b (+ i 12))) ax)) (cz (- (i64->f64 (u16 b (+ i 14))) az))
             (det (- (* bx cz) (* bz cx)))
             (u (/ (- (* (- x ax) cz) (* (- z az) cx)) det))
             (v (/ (- (* bx (- z az)) (* bz (- x ax))) det)) (w (- (- 1.0 u) v)))
        (new Pair (first (min w (min u v)))
             (second (* 0.01
                        (+ (+ (* w (i64->f64 (i16 b (+ i 4)))) (* u (i64->f64 (i16 b (+ i 10)))))
                           (* v (i64->f64 (i16 b (+ i 16))))))))))

    (define (cell-height (g Terrain) (cell I64) (x F64) (z F64)) (→ F64)
      (let* ((b (● g data)) (last (entry b (● g index) (+ cell 1))))
        (let loop ((i (entry b (● g index) cell)) (nearest -1e30) (height 0.0))
          (if (= i last) height
              (let ((at (plane b (+ (● g triangles) (* i 18)) x z)))
                (cond ((>= (● at first) -0.0000001) (● at second))
                      ((> (● at first) nearest) (loop (+ i 1) (● at first) (● at second)))
                      (else (loop (+ i 1) nearest height))))))))

    (define (ground-height (g Terrain) (p XZ)) (→ F64)
      (let* ((s (i64->f64 (● g cell)))
             (x (max 0.0 (min (* s (i64->f64 (● g cols))) (- (● p x) (i64->f64 (● g west))))))
             (z (max 0.0 (min (* s (i64->f64 (● g rows))) (- (● p z) (i64->f64 (● g north))))))
             (i (min (- (● g cols) 1) (f64->i64 (/ x s))))
             (j (min (- (● g rows) 1) (f64->i64 (/ z s)))))
        (cell-height g (+ i (* j (● g cols))) (* 100.0 (- x (* (i64->f64 i) s)))
                     (* 100.0 (- z (* (i64->f64 j) s))))))

    (define (ground-slope (g Terrain) (p XZ) (axis XZ) (span F64)) (→ F64)
      (/ (- (ground-height g (offset p axis (* 0.5 span)))
            (ground-height g (offset p axis (* -0.5 span)))) span))

    ;; GRD2 adds the number of collision strips per metre and a signed top
    ;; height to each span. GRD1 obstacles extend vertically. Road surfaces
    ;; and sidewalks belong solely to the ground mesh and never block a sweep.
    (record SolidColumn
      ((base Footprint)
       (top F64)))
    (define (scan (g Terrain) (row I64) (low F64) (high F64) (acc A)
                  (visit (Fn A F64 F64 F64 F64 F64 → A))) (→ A) (∀ (A))
                  (let* ((b (● g data)) (end (entry b (● g lines) (+ row 1)))
                         (step (/ 1.0 (i64->f64 (● g steps)))) (west (i64->f64 (● g west)))
                         (z (+ (i64->f64 (● g north)) (* step (i64->f64 row)))))
                    (let loop ((i (entry b (● g lines) row)) (out acc))
                      (if (= i end) out
                          (let* ((at (+ (● g spans) (* i (● g span-size))))
                                 (x (+ west (* step (i64->f64 (u16 b at)))))
                                 (right (+ west (* step (i64->f64 (u16 b (+ at 2))))))
                                 (top (if (= (● g span-size) 6)
                                          (* 0.01 (i64->f64 (i16 b (+ at 4))))
                                          1e20)))
                            (cond ((> x high) out) ((< right low) (loop (+ i 1) out))
                                  (else (loop (+ i 1) (visit out x right z (+ z step) top)))))))))
    (define (fold-columns (g Terrain) (p XZ) (reach F64) (initial A)
                          (visit (Fn A F64 F64 F64 F64 F64 → A))) (→ A) (∀ (A))
                          (let* ((steps (i64->f64 (● g steps)))
                                 (z (- (● p z) (i64->f64 (● g north))))
                                 (last (min (* (● g steps) (* (● g rows) (● g cell)))
                                            (+ 1 (f64->i64 (floor (* steps (+ z reach))))))))
                            (let loop ((j (max 0 (f64->i64 (floor (* steps (- z reach))))))
                                       (out initial))
                              (if (>= j last) out
                                  (loop (+ j 1)
                                        (scan g
                                              j
                                              (- (● p x) reach)
                                              (+ (● p x) reach)
                                              out
                                              visit))))))
    (define (fold-solid-spans (g Terrain) (p XZ) (reach F64) (initial A)
                              (visit (Fn A F64 F64 F64 F64 → A))) (→ A) (∀ (A))
                              (fold-columns g
                                            p
                                            reach
                                            initial
                                            (lambda (out x r z end top) (visit out x r z end))))
    (define (nearby-columns (g Terrain) (p XZ) (reach F64)) (→ (List SolidColumn))
      (fold-columns g p reach (Nil) (lambda (out x r z end top)
                                      (Cons (new SolidColumn
                                              (base (new Footprint
                                                      (west x)
                                                      (east r)
                                                      (north z)
                                                      (south end)))
                                              (top top))
                                            out))))

    (define (collect-footprint (walls (List Footprint))
                               (west F64)
                               (east F64)
                               (north F64)
                               (south F64))
      (→ (List Footprint))
      (Cons (new Footprint (west west) (east east) (north north) (south south)) walls))

    (define (nearby-solids (g Terrain) (p XZ) (reach F64)) (→ (List Footprint))
      (fold-solid-spans g p reach (Nil) collect-footprint))))
