;; Interface of a linked command as seen by the Node/WASI platform.
;; The bodies and one-page memory are documentation stubs, not an executable.
(module
  ;; ---- WASIp1 imports consumed by the current Rust runtime ----

  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func (param $argc_out i32) (param $bytes_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func (param $argv i32) (param $bytes i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func (param $count_out i32) (param $bytes_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func (param $entries i32) (param $bytes i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func (param $clock i32) (param $precision i64) (param $time_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func (param $fd i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    (func (param $fd i32) (param $stat_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_filestat_get"
    (func (param $fd i32) (param $stat_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func (param $fd i32) (param $prestat_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_dir_name"
    (func (param $fd i32) (param $path i32) (param $length i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func (param $fd i32) (param $iovs i32) (param $count i32) (param $read_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func (param $fd i32) (param $offset i64) (param $whence i32) (param $offset_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func (param $fd i32) (param $iovs i32) (param $count i32) (param $written_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_create_directory"
    (func (param $fd i32) (param $path i32) (param $length i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_filestat_get"
    (func (param $fd i32) (param $flags i32) (param $path i32) (param $length i32)
      (param $stat_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open"
    (func (param $fd i32) (param $lookup_flags i32) (param $path i32) (param $length i32)
      (param $open_flags i32) (param $rights i64) (param $inheriting_rights i64)
      (param $fd_flags i32) (param $fd_out i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func (param $status i32)))

  ;; ---- Collector hook ----

  (import "snail.host" "register-finalizer"
    (func (param $object eqref) (param $kind i32) (param $id i32)))

  ;; ---- Command exports ----

  (memory (export "memory") 1)
  (func (export "_start") unreachable)
  (func (export "snail:drop-resource") (param $kind i32) (param $id i32) unreachable)
)
