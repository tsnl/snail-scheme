(module
  ;; All continuation operations below are standard stack-switching opcodes.
  ;; Binaryen assembles, validates, and disassembles the actual .wasm input.
  (type $worker (func (param i64) (result i64)))
  (type $continuation (cont $worker))
  (type $box (struct (field i64)))
  (import "env" "collect" (func $collect))
  (import "env" "observe" (func $observe (param eqref)))
  (import "env" "foreign_enter" (func $foreign_enter))
  (import "env" "foreign_leave" (func $foreign_leave))
  (tag $yield (param i64) (result i64))
  (tag $other (param i64) (result i64))
  (tag $third (param i64) (result i64))
  (elem declare func $parked $done $outer_unmatched $outer_matched $callback_allowed $callback_escape $other_worker $twice $changing_worker $changing_outer $callback_unmatched)

  (global $pending (mut (ref null $continuation)) (ref.null $continuation))
  (global $payload (mut i64) (i64.const 0))
  (global $result (mut i64) (i64.const 0))

  ;; ---- Workers and suspension handlers ----

  (func $parked (type $worker) (param $input i64) (result i64)
    (local $box (ref $box))
    (local $resumed i64)
    (local.set $box (struct.new $box (i64.add (local.get $input) (i64.const 100))))
    ;; Escape the pointer so LLVM cannot replace its later load with a scalar.
    (call $observe (local.get $box))
    (local.set $resumed (suspend $yield (local.get $input)))
    ;; Collection here checks roots restored from the saved CPU context.
    (call $collect)
    (i64.add (struct.get $box 0 (local.get $box)) (local.get $resumed)))

  (func $done (type $worker) (param $input i64) (result i64)
    (i64.mul (local.get $input) (i64.const 2)))

  ;; A resume either returns its worker's result or branches to its handler
  ;; with the payload and fresh single-shot continuation. No C driver dispatch.
  (func $step (param $token (ref null $continuation)) (param $input i64) (result i32)
    (block $yielded (result i64 (ref $continuation))
      (global.set $result
        (resume $continuation (on $yield $yielded) (local.get $input) (local.get $token)))
      (return (i32.const 0)))
    (global.set $pending)
    (global.set $payload)
    (i32.const 1))

  (func $expect (param $actual i64) (param $expected i64)
    (if (i64.ne (local.get $actual) (local.get $expected)) (then (unreachable))))

  (func $expect_step (param $token (ref null $continuation)) (param $input i64)
                     (param $suspended i32) (param $expected i64)
    (if (i32.ne (call $step (local.get $token) (local.get $input)) (local.get $suspended))
      (then (unreachable)))
    (call $expect
      (if (result i64) (local.get $suspended)
        (then (global.get $payload)) (else (global.get $result)))
      (local.get $expected)))

  ;; ---- Nested delimiters and foreign boundaries ----

  (func $outer_unmatched (type $worker) (param $input i64) (result i64)
    ;; The nonmatching delimiter becomes part of the captured continuation.
    (block $unexpected (result i64 (ref $continuation))
      (return
        (i64.add (i64.const 1000)
          (resume $continuation (on $other $unexpected) (local.get $input)
            (cont.new $continuation (ref.func $parked))))))
    (unreachable))

  (func $outer_matched (type $worker) (param $input i64) (result i64)
    (call $expect_step (cont.new $continuation (ref.func $parked))
      (local.get $input) (i32.const 1) (local.get $input))
    (call $expect_step (global.get $pending) (i64.const 9) (i32.const 0)
      (i64.add (local.get $input) (i64.const 109)))
    (i64.add (global.get $result) (i64.const 2000)))

  (func $callback_allowed (type $worker) (param $input i64) (result i64)
    (local $result i64)
    (call $foreign_enter)
    (local.set $result (call $outer_matched (local.get $input)))
    (call $foreign_leave)
    (local.get $result))

  (func $callback_escape (type $worker) (param $input i64) (result i64)
    (call $foreign_enter)
    (call $parked (local.get $input)))

  (func $callback_unmatched (type $worker) (param $input i64) (result i64)
    (call $foreign_enter)
    ;; A new delimiter exists, but its tag does not match. Search must stop at
    ;; the foreign boundary before reaching an outer matching handler.
    (call $outer_unmatched (local.get $input)))

  ;; A single resume can select distinct blocks for different tags.
  (func $other_worker (type $worker) (param $input i64) (result i64)
    (suspend $other (local.get $input)))

  (func $two_handlers (param $input i64) (result i64)
    (block $got_yield (result i64 (ref $continuation))
      (block $got_other (result i64 (ref $continuation))
        (drop
          (resume $continuation (on $yield $got_yield) (on $other $got_other)
            (local.get $input) (cont.new $continuation (ref.func $other_worker))))
        (unreachable))
      (global.set $pending)
      (global.set $payload)
      (call $expect (global.get $payload) (local.get $input))
      (return (resume $continuation (i64.const 43) (global.get $pending))))
    (unreachable))

  (func $twice (type $worker) (param $input i64) (result i64)
    (suspend $yield (suspend $yield (local.get $input))))

  ;; Capture both contexts through $yield, then prove the captured inner
  ;; $other handler remains active and the newly installed outer $third wins.
  (func $changing_worker (type $worker) (param $input i64) (result i64)
    (suspend $third (suspend $other (suspend $yield (local.get $input)))))

  (func $changing_outer (type $worker) (param $input i64) (result i64)
    (block $got_other (result i64 (ref $continuation))
      (drop (resume $continuation (on $other $got_other) (local.get $input)
        (cont.new $continuation (ref.func $changing_worker))))
      (unreachable))
    (global.set $pending)
    (global.set $payload)
    (call $expect (global.get $payload) (i64.const 7))
    (i64.add (i64.const 1000)
      (resume $continuation (i64.const 9) (global.get $pending))))

  (func $preserved_handler
    (call $expect_step (cont.new $continuation (ref.func $changing_outer))
      (i64.const 5) (i32.const 1) (i64.const 5))
    (block $got_third (result i64 (ref $continuation))
      (drop (resume $continuation (on $third $got_third)
        (i64.const 7) (global.get $pending)))
      (unreachable))
    (global.set $pending)
    (global.set $payload)
    (call $expect (global.get $payload) (i64.const 9))
    (call $collect)
    (call $expect (resume $continuation (i64.const 11) (global.get $pending))
      (i64.const 1011)))

  ;; ---- Tests ----

  (func $checks (export "checks") (result i64)
    (local $a (ref null $continuation))
    (local $b (ref null $continuation))
    (local $root0 (ref $box))
    (local $root1 (ref $box))
    (local $root2 (ref $box))
    (local $root3 (ref $box))
    (local $root4 (ref $box))
    (local $root5 (ref $box))
    (local $root6 (ref $box))
    (local $root7 (ref $box))
    (local $root8 (ref $box))
    ;; More live pointers than callee-saved registers: parked OS stack spills
    ;; must remain roots while child contexts allocate and collect.
    (local.set $root0 (struct.new $box (i64.const 700)))
    (call $observe (local.get $root0))
    (local.set $root1 (struct.new $box (i64.const 701)))
    (call $observe (local.get $root1))
    (local.set $root2 (struct.new $box (i64.const 702)))
    (call $observe (local.get $root2))
    (local.set $root3 (struct.new $box (i64.const 703)))
    (call $observe (local.get $root3))
    (local.set $root4 (struct.new $box (i64.const 704)))
    (call $observe (local.get $root4))
    (local.set $root5 (struct.new $box (i64.const 705)))
    (call $observe (local.get $root5))
    (local.set $root6 (struct.new $box (i64.const 706)))
    (call $observe (local.get $root6))
    (local.set $root7 (struct.new $box (i64.const 707)))
    (call $observe (local.get $root7))
    (local.set $root8 (struct.new $box (i64.const 708)))
    (call $observe (local.get $root8))

    (call $expect_step (cont.new $continuation (ref.func $done))
      (i64.const 21) (i32.const 0) (i64.const 42))
    (call $expect_step (cont.new $continuation (ref.func $parked))
      (i64.const 10) (i32.const 1) (i64.const 10))
    (local.set $a (global.get $pending))
    (call $expect_step (cont.new $continuation (ref.func $parked))
      (i64.const 20) (i32.const 1) (i64.const 20))
    (local.set $b (global.get $pending))
    (global.set $pending (ref.null $continuation))
    (call $collect)
    (call $expect_step (local.get $b) (i64.const 3) (i32.const 0) (i64.const 123))
    (call $collect)
    (call $expect_step (local.get $a) (i64.const 7) (i32.const 0) (i64.const 117))
    (call $expect_step (cont.new $continuation (ref.func $outer_unmatched))
      (i64.const 5) (i32.const 1) (i64.const 5))
    (call $collect)
    (call $expect_step (global.get $pending) (i64.const 7) (i32.const 0) (i64.const 1112))
    (call $expect_step (cont.new $continuation (ref.func $outer_matched))
      (i64.const 6) (i32.const 0) (i64.const 2115))
    (call $expect_step (cont.new $continuation (ref.func $callback_allowed))
      (i64.const 8) (i32.const 0) (i64.const 2117))
    (call $expect (call $two_handlers (i64.const 31)) (i64.const 43))
    (call $expect_step (cont.new $continuation (ref.func $twice))
      (i64.const 10) (i32.const 1) (i64.const 10))
    (call $expect_step (global.get $pending)
      (i64.const 12) (i32.const 1) (i64.const 12))
    (call $expect_step (global.get $pending)
      (i64.const 14) (i32.const 0) (i64.const 14))
    (call $preserved_handler)
    (call $expect (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (struct.get $box 0 (local.get $root0))
      (struct.get $box 0 (local.get $root1)))
      (struct.get $box 0 (local.get $root2)))
      (struct.get $box 0 (local.get $root3)))
      (struct.get $box 0 (local.get $root4)))
      (struct.get $box 0 (local.get $root5)))
      (struct.get $box 0 (local.get $root6)))
      (struct.get $box 0 (local.get $root7)))
      (struct.get $box 0 (local.get $root8))) (i64.const 6336))
    (i64.const 42))

  (func $null_new (export "null_new")
    (drop (cont.new $continuation (ref.null $worker))))

  (func $null_resume (export "null_resume")
    (drop (call $step (ref.null $continuation) (i64.const 0))))

  (func $unhandled (export "unhandled")
    (drop (resume $continuation (i64.const 0)
      (cont.new $continuation (ref.func $parked)))))

  (func $double_resume (export "double_resume")
    (local $old (ref $continuation))
    (local.set $old (cont.new $continuation (ref.func $parked)))
    (drop (call $step (local.get $old) (i64.const 1)))
    (drop (call $step (local.get $old) (i64.const 2))))

  (func $foreign_unmatched (export "foreign_unmatched")
    (drop (call $step (cont.new $continuation (ref.func $callback_unmatched)) (i64.const 1))))

  (func $foreign_escape (export "foreign_escape")
    (drop (call $step (cont.new $continuation (ref.func $callback_escape)) (i64.const 1))))
)
