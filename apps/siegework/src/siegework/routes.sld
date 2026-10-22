;; Routes: what each mover can cross and what each cell costs it, and the
;; cost fields that lead it to a goal. Enemies and workers walk open
;; ground, ice and opened rock; water and walls stop them. An enemy that
;; chooses to dig may also cross intact rock and walls, paying the ticks it
;; takes to dig each one. Fields over the whole map are kept in the world
;; until the terrain changes; fields over a small window around a mover,
;; for a nearby goal, are never kept.
(define-library (siegework routes)
  (export
   Mover
   Mover-period
   Mover-dig
   worker-mover
   walkable?
   enter-cost
   route-field
   window-field
   portal-cells
   portal-field)
  (import
   (lofi base)
   (siegework grid)
   (siegework terrain)
   (siegework world))
  (begin

    ;; ---- Movers ----

    ;; A mover steps once every `period` ticks and, if it digs, strikes the
    ;; rock or wall ahead for `dig` damage every two ticks. One that does
    ;; not dig has a `dig` of 0.
    (struct Mover
      ((period I64)
       (dig I64)))

    ;; A worker's fields count its steps.
    (: worker-mover Mover)
    (define worker-mover (Mover 1 0))

    (: walkable? (-> World Cell Bool))
    (define (walkable? world cell)
      (and (not (walled? world cell))
           (match (ground-at (World-land world) cell)
             ((Rock) (opened? world cell))
             ((Water) #f)
             (_ #t))))

    ;; The ticks it takes to step onto a cell, or -1 if the mover cannot:
    ;; a step, plus for a digger the time to dig through intact rock or a
    ;; wall. Planning counts rock and walls at full health.
    (: enter-cost (-> World Mover Cell I64))
    (define (enter-cost world mover cell)
      (let ((period (Mover-period mover)) (dig (Mover-dig mover)))
        (cond ((walkable? world cell) period)
              ((= dig 0) -1)
              ((walled? world cell) (+ period (dig-ticks (vector-ref (World-walls world) (cell-index cell)) dig)))
              (else (match (ground-at (World-land world) cell)
                      ((Rock) (+ period (dig-ticks rock-health dig)))
                      (_ -1))))))

    ;; A hit every two ticks until `health` is gone.
    (: dig-ticks (-> I64 I64 I64))
    (define (dig-ticks health dig)
      (* 2 (quotient (+ health (- dig 1)) dig)))

    ;; Movers with the same period and dig share their fields.
    (: mover-key (-> Mover I64))
    (define (mover-key mover)
      (+ (* 10000 (Mover-period mover)) (Mover-dig mover)))

    ;; ---- Fields ----

    ;; The field toward `goals` over the whole map, named by the cell
    ;; `goal`, from the world's routes, or computed and kept there.
    (: route-field (-> World Cell (List Cell) Mover (Pair Field World)))
    (define (route-field world goal goals mover)
      (cached world goal (mover-key mover) (lambda () (cost-field whole-map (lambda (cell) (enter-cost world mover cell)) goals))))

    ;; The newest routes are kept, at most twenty-four.
    (: cached (-> World Cell I64 (-> Field) (Pair Field World)))
    (define (cached world goal key compute)
      (match (find (lambda (route) (and (= (Route-key route) key) (cell=? (Route-goal route) goal))) (World-routes world))
        ((Some route) (Pair (Route-field route) world))
        ((None) (let ((field (compute)))
                  (Pair field (World-routes-set world (take (Cons (Route goal key field) (World-routes world)) 24)))))))

    ;; The field toward a goal near `from`, within eight cells of it.
    (: window-field (-> World Mover Cell Cell Field))
    (define (window-field world mover from goal)
      (cost-field (window from 8) (lambda (cell) (enter-cost world mover cell)) (list goal)))

    ;; ---- Portals ----

    ;; Where a worker can jump from and to: the hub's cells and the cells of
    ;; powered portals.
    (: portal-cells (-> World (List Cell)))
    (define (portal-cells world)
      (append (hub-cells (World-hub world))
              (map Building-cell (filter (lambda (b) (and (portal? b) (powered? world (Building-id b)))) (World-buildings world)))))

    ;; A worker's steps to the nearest of those cells, kept until the
    ;; network changes.
    (: portal-field (-> World (Pair Field World)))
    (define (portal-field world)
      (cached world (Hub-cell (World-hub world)) portal-key
              (lambda () (cost-field whole-map (lambda (cell) (enter-cost world worker-mover cell)) (portal-cells world)))))

    ))
