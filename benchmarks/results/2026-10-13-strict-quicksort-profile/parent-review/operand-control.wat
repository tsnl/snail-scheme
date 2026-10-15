(module
 (type $box (struct (field i32)))
 (global $effects (export "effects") (mut i32) (i32.const 0))
 (func $branch (export "branch") (result i32)
  (block $done (result i32)
   (drop (struct.new $box
    (block (result i32)
     (global.set $effects (i32.const 7))
     (br $done (i32.const 42)))))
   (i32.const 0)))
 (func $trap (export "trap") (result (ref $box))
  (struct.new $box
   (block (result i32)
    (global.set $effects (i32.const 9))
    (unreachable))))
)
