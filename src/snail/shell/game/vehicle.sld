;; Rear-axle kinematic bicycle update from Atsushi Sakai's PythonRobotics,
;; PathTracking/stanley_control/stanley_control.py, State.update (MIT).
;; Copyright (c) 2016 - now Atsushi Sakai and other contributors.
;; The MIT License (MIT)
;;
;; Copyright (c) 2016 - now Atsushi Sakai and other contributors:
;; https://github.com/AtsushiSakai/PythonRobotics/contributors
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;; The game supplies pedals, dimensions, speed limits and street footprints.
(define-library (snail shell game vehicle)
  (export DriverControls
          neutral-driver
          adjust-driver!
          road-speed
          road-steering
          CarDimensions
          parked-footprint
          closing-on-car?
          signed-speed
          bicycle-step BicycleContact bicycle-contact)
  (import
   (snail core base)
   (snail shell math)
   (snail shell game physics))
  (begin
    (record CarDimensions
      ((wheelbase F64)
       (width F64)
       (length F64)))

    ;; ---- Road handling ----

    ;; Wheel travel and accelerator pressure follow the driver's keys in time.
    ;; The input device owns these values, independently of the saved cab.
    (record DriverControls
      ((wheel F64)
       (pedal F64)))
    (define (neutral-driver) (→ DriverControls) (new DriverControls (wheel 0.0) (pedal 0.0)))
    (define (approach (value F64) (target F64) (step F64)) (→ F64)
      (+ value (max (- 0.0 step) (min step (- target value)))))
    (define (adjust-driver! (c DriverControls) (steer F64) (throttle F64) (dt F64)) (→ Unit)
      (set! (● c wheel) (approach (● c wheel) (* 0.59 steer) (* dt (if (= steer 0.0) 3.6 2.9))))
      (set! (● c pedal)
            (approach (● c pedal) throttle (* dt (cond ((< (* (● c pedal) throttle) 0.0) 24.0)
                                                       ((= throttle 0.0) 8.0) (else 4.5))))))
    (define (gravity-along (grade F64)) (→ F64) (/ (* -9.81 grade) (sqrt (+ 1.0 (* grade grade)))))
    (define (road-speed (v F64) (pedal F64) (brake Bool) (grade F64) (dt F64)) (→ F64)
      (let* ((slope (gravity-along grade)) (resistance (+ 0.16 (* 0.00034 (* v v))))
             (braking (or brake (< (* pedal v) -0.012)))
             (force (if (< pedal 0.0) 2.5 (min 4.4 (/ 56.0 (max 1.0 (abs v)))))))
        (cond (braking (approach (+ v (* slope dt))
                                 0.0
                                 (* dt (+ resistance (* 9.6 (if brake 1.0 (abs pedal)))))))
              ((and (= pedal 0.0) (< (abs v) 0.12)) 0.0)
              (else (max -5.5
                         (min 31.0
                              (approach (+ v (* dt (+ slope (* pedal force))))
                                        0.0
                                        (* dt resistance))))))))
    ;; Tyres have one acceleration budget. Braking leaves less lateral grip.
    (define (road-steering (size CarDimensions)
                           (wheel F64)
                           (speed F64)
                           (acceleration F64)
                           (grade F64))
      (→ F64)
      (let* ((accel (- acceleration (gravity-along grade)))
             (grip 8.2)
             (lateral (sqrt (max 0.0 (* (* grip grip) (- 1.0 (/ (* accel accel) (* 9.6 9.6)))))))
             (limit (atan2 (* lateral (● size wheelbase)) (max 0.01 (* speed speed)))))
        (max (- 0.0 limit) (min limit wheel))))

    (define (signed-speed (b Body)) (→ F64)
      (let ((axis (forward (● b heading))) (v (● b velocity)))
        (+ (* (● v x) (● axis x)) (* (● v z) (● axis z)))))

    (define (extent (size CarDimensions) (yaw F64)) (→ XZ)
      (let ((c (* 0.5 (abs (cos yaw)))) (s (* 0.5 (abs (sin yaw)))))
        (xz (+ (* (● size width) c) (* (● size length) s))
            (+ (* (● size length) c) (* (● size width) s)))))

    (define (parked-footprint (b Body) (size CarDimensions)) (→ Footprint)
      (let ((e (extent size (● b heading))) (p (● b position)))
        (footprint (● p x) (● p z) (* 2.0 (● e x)) (* 2.0 (● e z)))))

    ;; Model two moving cars as capsules. Their rounded ends leave room to
    ;; turn past each other. Once in contact they can still move apart.
    (define (point-chassis (p XZ) (b Body) (half F64)) (→ F64)
      (let* ((at (● b position)) (dir (forward (● b heading)))
             (along (+ (* (- (● p x) (● at x)) (● dir x)) (* (- (● p z) (● at z)) (● dir z)))))
        (distance p (offset at dir (max (- 0.0 half) (min half along))))))
    (define (ends-gap (a Body) (b Body) (half F64)) (→ F64)
      (let ((p (● a position)) (axis (forward (● a heading))))
        (min (point-chassis (offset p axis half) b half)
             (point-chassis (offset p axis (- 0.0 half)) b half))))
    (define (chassis-gap (a Body) (b Body) (half F64)) (→ F64)
      (min (ends-gap a b half) (ends-gap b a half)))
    (define (closing-on-car? (before Body) (next Body) (other Body) (size CarDimensions)) (→ Bool)
      (and (< (distance (● next position) (● other position)) (+ 1.0 (● size length)))
           (let* ((half (* 0.5 (- (● size length) (● size width))))
                  (gap (chassis-gap next other half)))
             (and (< gap (● size width)) (< gap (chassis-gap before other half))))))

    ;; Compute the rear axle's Euler step in the old heading, then recover
    ;; the chassis center from the new heading. Speed is signed in reverse.
    (define (bicycle-step (b Body) (size CarDimensions) (steering F64) (next-speed F64)
                          (walls (List Footprint)) (dt F64)) (→ Body)
                          (let* ((speed (signed-speed b)) (yaw (● b heading)) (axis (forward yaw))
                                 (l (● size wheelbase))
                                 (next (+ yaw (* dt (* (/ speed l) (tan steering)))))
                                 (rear (offset (● b position) axis (* -0.5 l)))
                                 (goal (offset (offset rear axis (* dt speed))
                                               (forward next)
                                               (* 0.5 l))))
                            (if (or (<= dt 0.0) (= speed 0.0))
                                (new Body (position (● b position)) (heading yaw)
                                     (velocity (offset (xz 0.0 0.0) axis next-speed)))
                                (drive-to b size goal next next-speed walls))))

    ;; ---- Bicycle wheel contact ----

    (record BicycleContact
      ((bike Body)
       (lost XZ)))
    (define (wheel-hit (b Body) (goal Body) (axle F64) (radius F64) (walls (List Footprint)))
      (→ SweepContact)
      (let ((a (offset (● b position) (forward (● b heading)) axle))
            (z (offset (● goal position) (forward (● goal heading)) axle)))
        (first-contact a (xz (- (● z x) (● a x)) (- (● z z) (● a z))) radius walls)))
    (define (bicycle-contact (b Body) (size CarDimensions) (steer F64) (speed F64)
                             (walls (List Footprint)) (dt F64)) (→ BicycleContact)
                             (let* ((goal (bicycle-step b size steer speed (Nil) dt))
                                    (v (● goal velocity))
                                    (half (* 0.5 (● size wheelbase)))
                                    (radius (* 0.5 (● size width)))
                                    (f (wheel-hit b goal half radius walls))
                                    (r (wheel-hit b goal (negate half) radius walls))
                                    (t (min (● f time) (● r time))))
                               (if (= t 1.0) (new BicycleContact (bike goal) (lost (xz 0.0 0.0)))
                                   (let* ((at (between-bodies b goal (max 0.0 (- t 0.00001))))
                                          (blocked-x (or (and (= t (● f time)) (● f block-x))
                                                         (and (= t (● r time)) (● r block-x))))
                                          (blocked-z (or (and (= t (● f time)) (● f block-z))
                                                         (and (= t (● r time)) (● r block-z))))
                                          (slide (xz (if blocked-x 0.0 (● v x))
                                                     (if blocked-z 0.0 (● v z))))
                                          (end (offset (● at position) slide (* dt (- 1.0 t))))
                                          (axis
                                           (offset (xz 0.0 0.0) slide (if (< speed 0.0) -1.0 1.0)))
                                          (align (- (heading-to (xz 0.0 0.0) axis) (● at heading)))
                                          (yaw (if (> (distance slide (xz 0.0 0.0)) 0.6)
                                                   (+ (● at heading)
                                                      (max -0.24
                                                           (min 0.24
                                                                (atan2 (sin align) (cos align)))))
                                                   (● at heading)))
                                          (candidate
                                           (new Body (position end) (heading yaw) (velocity slide)))
                                          (second
                                           (min (● (wheel-hit at candidate half radius walls) time)
                                                (●
                                                 (wheel-hit at candidate (negate half) radius walls)
                                                 time)))
                                          (bike (if (< second 1.0)
                                                    (body (offset (● at position)
                                                                  slide
                                                                  (* (* dt (- 1.0 t)) second))
                                                          (● at heading))
                                                    candidate)))
                                     (new BicycleContact
                                       (bike bike)
                                       (lost (xz (- (● v x) (● bike velocity x))
                                                 (- (● v z) (● bike velocity z)))))))))

    ;; Expand the street by the chassis before sweeping its center. A car
    ;; that hits a solid stops just before contact and can immediately reverse.
    (define (drive-to (b Body) (size CarDimensions) (goal XZ) (yaw F64) (speed F64)
                      (walls (List Footprint))) (→ Body)
                      (let* ((p (● b position)) (e (extent size yaw))
                             (padded (map (lambda (w) (new Footprint (west (- (● w west) (● e x)))
                                                           (east (+ (● w east) (● e x)))
                                                           (north (- (● w north) (● e z)))
                                                           (south (+ (● w south) (● e z))))) walls))
                             (delta (xz (- (● goal x) (● p x)) (- (● goal z) (● p z))))
                             (t (sweep-fraction p delta 0.0 padded)))
                        (cond
                         ((< t 1.0) (body (offset p delta (max 0.0 (- t 0.00001))) (● b heading)))
                         ((not (clear? goal 0.0 padded)) (body p (● b heading)))
                         (else
                          (new Body
                            (position goal)
                            (heading yaw)
                            (velocity (offset (xz 0.0 0.0) (forward yaw) speed)))))))))
