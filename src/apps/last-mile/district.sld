;; Cab stands placed on mapped streets. Stop is the taxi position, curb is the waiting rider.
(define-library (apps last-mile district)
  (export Destination
          stop-kind-id
          StopKind
          Collect
          Deliver
          ReturnToCab
          OffDuty
          Stand
          stand-radius
          stands
          stand
          rider-name
          pickup-index
          drop-index)
  (import
   (snail core base)
   (snail shell game physics))
  (begin
    (enum StopKind (Collect) (Deliver) (ReturnToCab) (OffDuty))
    (define (stop-kind-id (k StopKind)) (→ I64)
      (match k ((Collect) 0) ((Deliver) 1) ((ReturnToCab) 2) ((OffDuty) 3)))
    (record Destination
      ((dispatch I64)
       (kind StopKind)
       (point XZ)))
    (define stand-radius (→ F64) 5.5)
    (record Stand
      ((name String)
       (street String)
       (stop XZ)
       (curb XZ)
       (heading F64)))
    (define (stop (name String) (street String) (x F64) (z F64) (cx F64) (cz F64) (h F64)) (→ Stand)
      (new Stand (name name) (street street) (stop (xz x z)) (curb (xz cx cz)) (heading h)))
    (define stands (→ (List Stand)) (list
                                     (stop "Hyde at Lombard"
                                           "Hyde Street"
                                           -146.5
                                           8.5
                                           -143.4
                                           8.5
                                           0.0)
                                     (stop "Jones Street"
                                           "Jones Street"
                                           147.0
                                           -14.2
                                           150.0
                                           -14.2
                                           0.0)
                                     (stop "Washington Square"
                                           "Stockton Street"
                                           732.0
                                           256.4
                                           735.0
                                           256.4
                                           0.0)
                                     (stop "Ferry Building"
                                           "The Embarcadero"
                                           1903.72
                                           1055.05
                                           1900.8
                                           1055.74
                                           2.9105)
                                     (stop "Fisherman’s Wharf"
                                           "Jefferson Street"
                                           221.28
                                           -639.0
                                           221.28
                                           -642.0
                                           -1.5708)
                                     (stop "Mission Dolores"
                                           "16th Street"
                                           -1425.01
                                           3994.41
                                           -1424.74
                                           3991.42
                                           -1.478)
                                     (stop "Ocean Beach"
                                           "La Playa Street"
                                           -8612.01
                                           2948.84
                                           -8609.04
                                           2949.2
                                           0.1199)
                                     (stop "Golden Gate Park"
                                           "Martin Luther King Junior Drive"
                                           -4830.26
                                           3122.78
                                           -4827.29
                                           3122.41
                                           -0.1244)
                                     (stop "Twin Peaks"
                                           "Twin Peaks Boulevard"
                                           -3396.09
                                           4876.46
                                           -3394.43
                                           4878.96
                                           0.9828)
                                     (stop "Bayview"
                                           "3rd Street"
                                           1133.02
                                           7912.82
                                           1135.76
                                           7914.05
                                           0.4229)
                                     (stop "Crocker-Amazon"
                                           "Alemany Boulevard"
                                           -3749.2
                                           9035.78
                                           -3747.45
                                           9038.22
                                           0.9478)
                                     (stop "Lake Merced"
                                           "Lake Merced Boulevard"
                                           -7124.38
                                           7484.09
                                           -7127.06
                                           7482.74
                                           -2.6718)
                                     (stop "Treasure Island"
                                           "Avenue of the Palms"
                                           4196.48
                                           -1296.49
                                           4199.29
                                           -1297.53
                                           -0.353)
                                     (stop "Yerba Buena Island"
                                           "Access road"
                                           4327.61
                                           -215.96
                                           4328.22
                                           -218.89
                                           -1.3654)
                                     (stop "Castro Theatre"
                                           "Castro Street"
                                           -2192.26
                                           4168.18
                                           -2189.26
                                           4168.37
                                           0.0624)
                                     (stop "Presidio"
                                           "Lincoln Boulevard"
                                           -3443.73
                                           -529.29
                                           -3442.12
                                           -531.82
                                           -1.0041)))
    (define (stand (id I64)) (→ Stand) (list-ref stands id))
    (define (pickup-index (ride I64))
      (→ I64)
      (list-ref (list 0 1 4 3 5 14 8 7 6 11 10 9 2 12 13 15) (modulo ride 16)))
    (define (drop-index (ride I64))
      (→ I64)
      (list-ref (list 1 2 3 5 14 8 7 6 11 10 9 2 12 13 15 4) (modulo ride 16)))
    (define (rider-name (ride I64))
      (→ String)
      (list-ref (list "Rosa" "Min" "June" "Leon" "Carmen" "Theo" "Ari" "Jo") (modulo ride 8)))))
