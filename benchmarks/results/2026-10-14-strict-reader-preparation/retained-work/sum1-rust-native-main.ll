define internal noundef ptr @_ZN4sum14main17hf4b7cf2a049245a7E() unnamed_addr #2 personality ptr @rust_eh_personality {
start:
  %0 = alloca [24 x i8], align 8
  %1 = alloca [16 x i8], align 8
  %2 = alloca [16 x i8], align 8
  %3 = alloca [384 x i8], align 1
  %4 = alloca [8 x i8], align 8
  %5 = alloca [16 x i8], align 8
  %6 = alloca [1 x i8], align 1
  %7 = alloca [16 x i8], align 8
  %8 = alloca [24 x i8], align 8
  %9 = alloca [32 x i8], align 8
  %10 = alloca [24 x i8], align 8
  %11 = alloca [32 x i8], align 8
  %12 = alloca [24 x i8], align 8
  %13 = alloca [24 x i8], align 8
  %14 = alloca [24 x i8], align 8
  %15 = alloca [24 x i8], align 8
  %args2.i = alloca [48 x i8], align 8
  %args.i = alloca [16 x i8], align 8
  %seconds.i = alloca [8 x i8], align 8
  %result.i = alloca [8 x i8], align 8
  %count.i = alloca [8 x i8], align 8
  %name.i = alloca [16 x i8], align 8
  %e.i.i.i = alloca [1 x i8], align 1
  %_26.i.i.i = alloca [24 x i8], align 8
  %bytes.i.i.i = alloca [4 x i8], align 4
  %_14.i.i = alloca [16 x i8], align 8
  %text.i.i = alloca [24 x i8], align 8
  %_4.i.i = alloca [16 x i8], align 4
  %16 = alloca [16 x i8], align 8
  %result = alloca [8 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %15), !noalias !272
  store i64 0, ptr %15, align 8, !noalias !272
  %17 = getelementptr inbounds nuw i8, ptr %15, i64 8
  store ptr inttoptr (i64 1 to ptr), ptr %17, align 8, !noalias !272
  %18 = getelementptr inbounds nuw i8, ptr %15, i64 16
  store i64 0, ptr %18, align 8, !noalias !272
  %19 = load atomic i32, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 48) acquire, align 8, !dbg !275, !noalias !272
  %20 = icmp eq i32 %19, 0, !dbg !313
  br i1 %20, label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, label %21, !dbg !313, !prof !314

21:                                               ; preds = %start
; call <std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::initialize::<<std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::get_or_init<std::io::stdio::stdin::{closure#0}>::{closure#0}, !>
  tail call fastcc void @_RINvMNtNtCsjrHSEGnQ3l9_3std4sync9once_lockINtB3_8OnceLockINtNtNtB5_6poison5mutex5MutexINtNtNtNtB7_2io8buffered9bufreader9BufReaderNtNtB1t_5stdio8StdinRawEEE10initializeNCINvB2_11get_or_initNCNvB26_5stdin0E0zEB7_() #67, !dbg !315, !noalias !272
  br label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, !dbg !316

_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i: ; preds = %21, %start
  tail call void @llvm.experimental.noalias.scope.decl(metadata !317)
  %22 = cmpxchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0, i32 1 acquire monotonic, align 4, !dbg !320, !noalias !342
  %23 = extractvalue { i32, i1 } %22, 1, !dbg !347
  br i1 %23, label %25, label %24, !dbg !348, !prof !314

24:                                               ; preds = %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
; call <std::sys::sync::mutex::futex::Mutex>::lock_contended
  tail call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys4sync5mutex5futexNtB2_5Mutex14lock_contended(ptr noundef nonnull align 8 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE), !dbg !349, !noalias !342
  br label %25, !dbg !349

25:                                               ; preds = %24, %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
  %26 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !350, !noalias !342
  %27 = and i64 %26, 9223372036854775807, !dbg !375
  %28 = icmp eq i64 %27, 0, !dbg !375
  br i1 %28, label %32, label %29, !dbg !375, !prof !314

29:                                               ; preds = %25
; call std::panicking::panic_count::is_zero_slow_path
  %30 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #103, !dbg !376, !noalias !342
  %31 = xor i1 %30, true, !dbg !377
  br label %32, !dbg !376

32:                                               ; preds = %29, %25
  %33 = phi i1 [ %31, %29 ], [ false, %25 ], !dbg !378
  %34 = load atomic i8, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !379, !noalias !342
  tail call void @llvm.experimental.noalias.scope.decl(metadata !388), !dbg !391
  tail call void @llvm.experimental.noalias.scope.decl(metadata !392), !dbg !395
  %35 = load i64, ptr %18, align 8, !dbg !399, !alias.scope !419, !noalias !420, !noundef !43
  %36 = icmp sgt i64 %35, -1, !dbg !422
  tail call void @llvm.assume(i1 %36), !dbg !424
  %37 = icmp eq i64 %35, 0, !dbg !425
  br i1 %37, label %38, label %63, !dbg !425

38:                                               ; preds = %32
  tail call void @llvm.experimental.noalias.scope.decl(metadata !426), !dbg !429
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %39 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef nonnull align 8 dereferenceable(24) %15)
          to label %42 unwind label %40, !dbg !430, !noalias !272

40:                                               ; preds = %38
  %41 = landingpad { ptr, i32 }
          cleanup
  br label %55, !dbg !438

42:                                               ; preds = %38
  %43 = extractvalue { i64, ptr } %39, 0, !dbg !439
  %44 = extractvalue { i64, ptr } %39, 1, !dbg !439
  %45 = load ptr, ptr %17, align 8, !dbg !440, !alias.scope !459, !noalias !460, !nonnull !43, !noundef !43
  %46 = load i64, ptr %18, align 8, !dbg !462, !alias.scope !459, !noalias !460, !noundef !43
  call void @llvm.lifetime.start.p0(ptr nonnull %12), !dbg !463, !noalias !465
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %12, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %45, i64 noundef %46), !dbg !463, !noalias !465
  %47 = load i64, ptr %12, align 8, !dbg !466, !range !474, !noalias !465, !noundef !43
  %48 = icmp eq i64 %47, 0, !dbg !475
  call void @llvm.lifetime.end.p0(ptr nonnull %12), !dbg !476, !noalias !465
  br i1 %48, label %49, label %52, !dbg !463

49:                                               ; preds = %42
  %50 = icmp sgt i64 %46, -1, !dbg !477
  tail call void @llvm.assume(i1 %50), !dbg !481
  %51 = trunc nuw i64 %43 to i1
  br label %58, !dbg !482

52:                                               ; preds = %42
  %53 = trunc nuw i64 %43 to i1, !dbg !483
  %54 = select i1 %53, ptr %44, ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50, !dbg !483
  br label %58, !dbg !483

55:                                               ; preds = %71, %67, %40
  %56 = phi { ptr, i32 } [ %41, %40 ], [ %68, %71 ], [ %68, %67 ]
  %57 = zext i1 %33 to i8, !dbg !486
; call core::ptr::drop_in_place::<std::io::stdio::StdinLock>
  tail call fastcc void @_RINvNtCsgEmfK2I1SDS_4core3ptr13drop_in_placeNtNtNtCsjrHSEGnQ3l9_3std2io5stdio9StdinLockEBM_(ptr nonnull @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i8 %57) #104, !dbg !487, !noalias !488
  resume { ptr, i32 } %56, !dbg !489

58:                                               ; preds = %52, %49
  %59 = phi ptr [ %44, %49 ], [ %54, %52 ], !dbg !429
  %60 = phi i1 [ %51, %49 ], [ true, %52 ], !dbg !429
  %61 = phi i64 [ %46, %49 ], [ 0, %52 ], !dbg !490
  store i64 %61, ptr %18, align 8, !dbg !491, !alias.scope !459, !noalias !501
  %62 = ptrtoint ptr %59 to i64, !dbg !429
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !504

63:                                               ; preds = %32
  call void @llvm.lifetime.start.p0(ptr nonnull %14), !dbg !505, !noalias !506
  store i64 0, ptr %14, align 8, !dbg !507, !noalias !506
  %64 = getelementptr inbounds nuw i8, ptr %14, i64 8, !dbg !507
  store ptr inttoptr (i64 1 to ptr), ptr %64, align 8, !dbg !507, !noalias !506
  %65 = getelementptr inbounds nuw i8, ptr %14, i64 16, !dbg !507
  store i64 0, ptr %65, align 8, !dbg !507, !noalias !506
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %66 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef align 8 dereferenceable(24) %14)
          to label %73 unwind label %67, !dbg !510, !noalias !512

67:                                               ; preds = %93, %63
  %68 = landingpad { ptr, i32 }
          cleanup
  %69 = load i64, ptr %14, align 8, !dbg !513, !range !247, !alias.scope !516, !noalias !506, !noundef !43
  %70 = icmp eq i64 %69, 0, !dbg !519
  br i1 %70, label %55, label %71, !dbg !519

71:                                               ; preds = %67
  %72 = load ptr, ptr %64, align 8, !dbg !513, !alias.scope !516, !noalias !506, !nonnull !43, !noundef !43
  tail call void @free(ptr noundef nonnull %72) #67, !dbg !530, !noalias !545
  br label %55, !dbg !546

73:                                               ; preds = %63
  %74 = extractvalue { i64, ptr } %66, 0, !dbg !547
  %75 = trunc nuw i64 %74 to i1, !dbg !548
  br i1 %75, label %76, label %79, !dbg !548

76:                                               ; preds = %73
  %77 = extractvalue { i64, ptr } %66, 1, !dbg !547
  %78 = ptrtoint ptr %77 to i64, !dbg !547
  br label %110, !dbg !551

79:                                               ; preds = %73
  call void @llvm.lifetime.start.p0(ptr nonnull %13), !dbg !554, !noalias !506
  %80 = load ptr, ptr %64, align 8, !dbg !555, !noalias !506, !nonnull !43, !noundef !43
  %81 = load i64, ptr %65, align 8, !dbg !568, !noalias !506, !noundef !43
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %13, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %80, i64 noundef %81), !dbg !554, !noalias !506
  %82 = load i64, ptr %13, align 8, !dbg !569, !range !474, !noalias !506, !noundef !43
  %83 = trunc nuw i64 %82 to i1, !dbg !572
  br i1 %83, label %84, label %85, !dbg !572

84:                                               ; preds = %79
  call void @llvm.lifetime.end.p0(ptr nonnull %13), !dbg !573, !noalias !506
  br label %110, !dbg !551

85:                                               ; preds = %79
  %86 = getelementptr inbounds nuw i8, ptr %13, i64 8, !dbg !574
  %87 = load ptr, ptr %86, align 8, !dbg !574, !noalias !506, !nonnull !43, !align !63, !noundef !43
  %88 = getelementptr inbounds nuw i8, ptr %13, i64 16, !dbg !574
  %89 = load i64, ptr %88, align 8, !dbg !574, !noalias !506, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %13), !dbg !573, !noalias !506
  tail call void @llvm.experimental.noalias.scope.decl(metadata !575), !dbg !578
  %90 = load i64, ptr %15, align 8, !dbg !593, !range !247, !alias.scope !607, !noalias !420, !noundef !43
  %91 = sub nsw i64 %90, %35, !dbg !610
  %92 = icmp ugt i64 %89, %91, !dbg !616
  br i1 %92, label %93, label %97, !dbg !617, !prof !618

93:                                               ; preds = %85
; invoke <alloc::raw_vec::RawVecInner<_>>::reserve::do_reserve_and_handle::<alloc::alloc::Global>
  invoke fastcc void @_RINvNvMs2_NtCslNYArtu3iFV_5alloc7raw_vecINtB8_11RawVecInnerpE7reserve21do_reserve_and_handleNtNtBa_5alloc6GlobalECsjrHSEGnQ3l9_3std(ptr noalias noundef nonnull align 8 dereferenceable(24) %15, i64 noundef %35, i64 noundef %89, i64 noundef 1, i64 noundef 1)
          to label %94 unwind label %67, !dbg !619, !noalias !420

94:                                               ; preds = %93
  %95 = load i64, ptr %18, align 8, !dbg !620, !alias.scope !623, !noalias !420, !noundef !43
  %96 = icmp sgt i64 %95, -1, !dbg !624
  tail call void @llvm.assume(i1 %96), !dbg !626
  br label %99, !dbg !627

97:                                               ; preds = %85
  %98 = icmp eq i64 %89, 0, !dbg !627
  br i1 %98, label %103, label %99, !dbg !627

99:                                               ; preds = %97, %94
  %100 = phi i64 [ %95, %94 ], [ %35, %97 ]
  %101 = load ptr, ptr %17, align 8, !dbg !629, !alias.scope !623, !noalias !420, !nonnull !43, !noundef !43
  %102 = getelementptr inbounds nuw i8, ptr %101, i64 %100, !dbg !638
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %102, ptr nonnull readonly align 1 %87, i64 %89, i1 false), !dbg !644, !noalias !647
  br label %103, !dbg !648

103:                                              ; preds = %99, %97
  %104 = phi i64 [ %100, %99 ], [ %35, %97 ]
  %105 = add i64 %104, %89, !dbg !649
  store i64 %105, ptr %18, align 8, !dbg !649, !alias.scope !623, !noalias !420
  %106 = load i64, ptr %14, align 8, !dbg !650, !range !247, !alias.scope !652, !noalias !506, !noundef !43
  %107 = icmp eq i64 %106, 0, !dbg !655
  br i1 %107, label %109, label %108, !dbg !655

108:                                              ; preds = %103
  tail call void @free(ptr noundef nonnull %80) #67, !dbg !660, !noalias !545
  br label %109, !dbg !667

109:                                              ; preds = %108, %103
  call void @llvm.lifetime.end.p0(ptr nonnull %14), !dbg !668, !noalias !506
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !504

110:                                              ; preds = %84, %76
  %111 = phi i64 [ %78, %76 ], [ ptrtoint (ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50 to i64), %84 ], !dbg !669
  %112 = load i64, ptr %14, align 8, !dbg !673, !range !247, !alias.scope !675, !noalias !506, !noundef !43
  %113 = icmp eq i64 %112, 0, !dbg !678
  br i1 %113, label %116, label %114, !dbg !678

114:                                              ; preds = %110
  %115 = load ptr, ptr %64, align 8, !dbg !673, !alias.scope !675, !noalias !506, !nonnull !43, !noundef !43
  tail call void @free(ptr noundef nonnull %115) #67, !dbg !683, !noalias !545
  br label %116, !dbg !690

116:                                              ; preds = %114, %110
  call void @llvm.lifetime.end.p0(ptr nonnull %14), !dbg !668, !noalias !506
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !691

_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i: ; preds = %116, %109, %58
  %117 = phi i64 [ %62, %58 ], [ %111, %116 ], [ %89, %109 ], !dbg !692
  %118 = phi i1 [ %60, %58 ], [ true, %116 ], [ false, %109 ], !dbg !692
  %119 = inttoptr i64 %117 to ptr, !dbg !691
  br i1 %33, label %127, label %120, !dbg !693

120:                                              ; preds = %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %121 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !703, !noalias !488
  %122 = and i64 %121, 9223372036854775807, !dbg !713
  %123 = icmp eq i64 %122, 0, !dbg !713
  br i1 %123, label %127, label %124, !dbg !713, !prof !314

124:                                              ; preds = %120
; call std::panicking::panic_count::is_zero_slow_path
  %125 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #103, !dbg !714, !noalias !488
  br i1 %125, label %127, label %126, !dbg !715

126:                                              ; preds = %124
  store atomic i8 1, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !716, !noalias !488
  br label %127, !dbg !721

127:                                              ; preds = %126, %124, %120, %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %128 = atomicrmw xchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0 release, align 4, !dbg !722, !noalias !488
  %129 = icmp eq i32 %128, 2, !dbg !729
  br i1 %129, label %130, label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !729, !prof !618

130:                                              ; preds = %127
  %131 = tail call noundef i64 (i64, ...) @syscall(i64 noundef 202, ptr noundef nonnull align 4 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 noundef 129, i32 noundef 1) #67, !dbg !730, !noalias !488
  br label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !741

_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i: ; preds = %130, %127
  br i1 %118, label %132, label %135

132:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %133 = load i64, ptr %15, align 8, !range !247, !noalias !272, !noundef !43
  %134 = icmp eq i64 %133, 0
  br i1 %134, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, label %301

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread: ; preds = %132
  call void @llvm.lifetime.end.p0(ptr nonnull %15), !noalias !272
  br label %bb14

135:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %136 = load ptr, ptr %17, align 8, !noalias !272, !nonnull !43, !noundef !43
  %137 = load i64, ptr %18, align 8, !noalias !272, !noundef !43
  tail call void @llvm.experimental.noalias.scope.decl(metadata !742)
  call void @llvm.lifetime.start.p0(ptr nonnull %11), !noalias !745
  tail call void @llvm.experimental.noalias.scope.decl(metadata !747)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !750)
  %138 = getelementptr inbounds nuw i8, ptr %136, i64 %137
  call void @llvm.lifetime.start.p0(ptr nonnull %8), !noalias !752
  %139 = icmp samesign eq i64 %137, 0
  br i1 %139, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %140

140:                                              ; preds = %135
  %141 = getelementptr inbounds nuw i8, ptr %136, i64 1
  %142 = load i8, ptr %136, align 1, !alias.scope !755, !noalias !756, !noundef !43
  %143 = icmp sgt i8 %142, -1
  br i1 %143, label %155, label %144

144:                                              ; preds = %140
  %145 = and i8 %142, 31
  %146 = zext nneg i8 %145 to i32
  %147 = icmp samesign ne i64 %137, 1
  tail call void @llvm.assume(i1 %147)
  %148 = getelementptr inbounds nuw i8, ptr %136, i64 2
  %149 = load i8, ptr %141, align 1, !alias.scope !755, !noalias !756, !noundef !43
  %150 = shl nuw nsw i32 %146, 6
  %151 = and i8 %149, 63
  %152 = zext nneg i8 %151 to i32
  %153 = or disjoint i32 %150, %152
  %154 = icmp samesign ugt i8 %142, -33
  br i1 %154, label %157, label %180

155:                                              ; preds = %140
  %156 = zext nneg i8 %142 to i32
  br label %180

157:                                              ; preds = %144
  %158 = icmp samesign ne i64 %137, 2
  tail call void @llvm.assume(i1 %158)
  %159 = getelementptr inbounds nuw i8, ptr %136, i64 3
  %160 = load i8, ptr %148, align 1, !alias.scope !755, !noalias !756, !noundef !43
  %161 = shl nuw nsw i32 %152, 6
  %162 = and i8 %160, 63
  %163 = zext nneg i8 %162 to i32
  %164 = or disjoint i32 %161, %163
  %165 = shl nuw nsw i32 %146, 12
  %166 = or disjoint i32 %164, %165
  %167 = icmp samesign ugt i8 %142, -17
  br i1 %167, label %168, label %180

168:                                              ; preds = %157
  %169 = icmp samesign ne i64 %137, 3
  tail call void @llvm.assume(i1 %169)
  %170 = getelementptr inbounds nuw i8, ptr %136, i64 4
  %171 = load i8, ptr %159, align 1, !alias.scope !755, !noalias !756, !noundef !43
  %172 = shl nuw nsw i32 %146, 18
  %173 = and i32 %172, 1835008
  %174 = shl nuw nsw i32 %164, 6
  %175 = and i8 %171, 63
  %176 = zext nneg i8 %175 to i32
  %177 = or disjoint i32 %174, %176
  %178 = or disjoint i32 %177, %173
  %179 = icmp eq i32 %178, 1114112
  br i1 %179, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %180

180:                                              ; preds = %168, %157, %155, %144
  %181 = phi i32 [ %178, %168 ], [ %166, %157 ], [ %153, %144 ], [ %156, %155 ]
  %182 = phi ptr [ %170, %168 ], [ %159, %157 ], [ %148, %144 ], [ %141, %155 ]
  %183 = ptrtoint ptr %138 to i64
  %184 = ptrtoint ptr %182 to i64
  %185 = sub nuw i64 %183, %184
  %186 = lshr i64 %185, 2
  %187 = and i64 %185, 3
  %188 = icmp ne i64 %187, 0
  %189 = zext i1 %188 to i64
  %190 = add nuw nsw i64 %186, %189
  %191 = tail call i64 @llvm.umax.i64(i64 %190, i64 3)
  %192 = add nuw nsw i64 %191, 1
  %193 = shl i64 %192, 2
  %194 = icmp samesign ugt i64 %190, 4611686018427387902
  %195 = icmp ugt i64 %193, 9223372036854775804
  %196 = select i1 %194, i1 true, i1 %195, !prof !761
  br i1 %196, label %.split.i.i.i, label %197, !prof !761

.split.i.i.i:                                     ; preds = %180
; call alloc::raw_vec::capacity_overflow
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #105, !dbg !762, !noalias !764
  unreachable, !dbg !762

197:                                              ; preds = %180
  %198 = icmp eq i64 %193, 0
  br i1 %198, label %201, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i: ; preds = %197
  %199 = tail call noundef ptr @malloc(i64 noundef range(i64 0, -9223372036854775808) %193) #67, !dbg !765, !noalias !770
  %200 = icmp eq ptr %199, null
  br i1 %200, label %.split1.i.i.i, label %201

.split1.i.i.i:                                    ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 4, i64 %193) #106, !noalias !764
  unreachable

201:                                              ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i, %197
  %202 = phi i64 [ 0, %197 ], [ %192, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i ]
  %203 = phi ptr [ inttoptr (i64 4 to ptr), %197 ], [ %199, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i ]
  %204 = icmp samesign ult i64 %191, %202
  tail call void @llvm.assume(i1 %204)
  store i32 %181, ptr %203, align 4, !noalias !764
  store i64 %202, ptr %8, align 8, !noalias !752
  %205 = getelementptr inbounds nuw i8, ptr %8, i64 8
  store ptr %203, ptr %205, align 8, !noalias !752
  %206 = getelementptr inbounds nuw i8, ptr %8, i64 16
  store i64 1, ptr %206, align 8, !noalias !752
  tail call void @llvm.experimental.noalias.scope.decl(metadata !773)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !776)
  %207 = icmp eq ptr %182, %138
  br i1 %207, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %.preheader280

.preheader280:                                    ; preds = %201, %266
  %208 = phi ptr [ %267, %266 ], [ %203, %201 ]
  %209 = phi i64 [ %269, %266 ], [ 1, %201 ]
  %210 = phi ptr [ %252, %266 ], [ %182, %201 ]
  %211 = getelementptr inbounds nuw i8, ptr %210, i64 1
  %212 = load i8, ptr %210, align 1, !alias.scope !755, !noalias !779, !noundef !43
  %213 = icmp sgt i8 %212, -1
  br i1 %213, label %225, label %214

214:                                              ; preds = %.preheader280
  %215 = and i8 %212, 31
  %216 = zext nneg i8 %215 to i32
  %217 = icmp ne ptr %211, %138
  tail call void @llvm.assume(i1 %217)
  %218 = getelementptr inbounds nuw i8, ptr %210, i64 2
  %219 = load i8, ptr %211, align 1, !alias.scope !755, !noalias !779, !noundef !43
  %220 = shl nuw nsw i32 %216, 6
  %221 = and i8 %219, 63
  %222 = zext nneg i8 %221 to i32
  %223 = or disjoint i32 %220, %222
  %224 = icmp samesign ugt i8 %212, -33
  br i1 %224, label %227, label %250

225:                                              ; preds = %.preheader280
  %226 = zext nneg i8 %212 to i32
  br label %250

227:                                              ; preds = %214
  %228 = icmp ne ptr %218, %138
  tail call void @llvm.assume(i1 %228)
  %229 = getelementptr inbounds nuw i8, ptr %210, i64 3
  %230 = load i8, ptr %218, align 1, !alias.scope !755, !noalias !779, !noundef !43
  %231 = shl nuw nsw i32 %222, 6
  %232 = and i8 %230, 63
  %233 = zext nneg i8 %232 to i32
  %234 = or disjoint i32 %231, %233
  %235 = shl nuw nsw i32 %216, 12
  %236 = or disjoint i32 %234, %235
  %237 = icmp samesign ugt i8 %212, -17
  br i1 %237, label %238, label %250

238:                                              ; preds = %227
  %239 = icmp ne ptr %229, %138
  tail call void @llvm.assume(i1 %239)
  %240 = getelementptr inbounds nuw i8, ptr %210, i64 4
  %241 = load i8, ptr %229, align 1, !alias.scope !755, !noalias !779, !noundef !43
  %242 = shl nuw nsw i32 %216, 18
  %243 = and i32 %242, 1835008
  %244 = shl nuw nsw i32 %234, 6
  %245 = and i8 %241, 63
  %246 = zext nneg i8 %245 to i32
  %247 = or disjoint i32 %244, %246
  %248 = or disjoint i32 %247, %243
  %249 = icmp eq i32 %248, 1114112
  br i1 %249, label %271, label %250

250:                                              ; preds = %238, %227, %225, %214
  %251 = phi i32 [ %248, %238 ], [ %236, %227 ], [ %223, %214 ], [ %226, %225 ]
  %252 = phi ptr [ %240, %238 ], [ %229, %227 ], [ %218, %214 ], [ %211, %225 ]
  %253 = icmp samesign ult i64 %209, 2305843009213693952
  tail call void @llvm.assume(i1 %253)
  %254 = load i64, ptr %8, align 8, !range !247, !alias.scope !784, !noalias !752, !noundef !43
  %255 = icmp eq i64 %209, %254
  br i1 %255, label %256, label %266

256:                                              ; preds = %250
  %257 = ptrtoint ptr %252 to i64
  %258 = sub nuw i64 %183, %257
  %259 = lshr i64 %258, 2
  %260 = and i64 %258, 3
  %261 = icmp ne i64 %260, 0
  %262 = zext i1 %261 to i64
  %263 = add nuw nsw i64 %259, 1
  %264 = add nuw nsw i64 %263, %262
; call alloc::raw_vec::RawVecInner<A>::reserve::do_reserve_and_handle
  call fastcc void @"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$7reserve21do_reserve_and_handle17h9d2eedb01691c0ccE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %8, i64 noundef %209, i64 noundef range(i64 1, 0) %264, i64 noundef 4, i64 noundef 4) #67, !noalias !764
  %265 = load ptr, ptr %205, align 8, !alias.scope !784, !noalias !752
  br label %266

266:                                              ; preds = %256, %250
  %267 = phi ptr [ %265, %256 ], [ %208, %250 ]
  %268 = getelementptr inbounds nuw i32, ptr %267, i64 %209
  store i32 %251, ptr %268, align 4, !noalias !785
  %269 = add nuw nsw i64 %209, 1
  store i64 %269, ptr %206, align 8, !alias.scope !784, !noalias !752
  %270 = icmp eq ptr %252, %138
  br i1 %270, label %271, label %.preheader280

271:                                              ; preds = %266, %238
  %272 = phi i64 [ %209, %238 ], [ %269, %266 ]
  %273 = load i64, ptr %8, align 8, !noalias !786
  %274 = load ptr, ptr %205, align 8, !noalias !786
  br label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i

_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i: ; preds = %271, %201, %168, %135
  %275 = phi i64 [ 0, %135 ], [ 0, %168 ], [ %272, %271 ], [ 1, %201 ]
  %276 = phi ptr [ inttoptr (i64 4 to ptr), %135 ], [ inttoptr (i64 4 to ptr), %168 ], [ %274, %271 ], [ %203, %201 ]
  %277 = phi i64 [ 0, %135 ], [ 0, %168 ], [ %273, %271 ], [ %202, %201 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %8), !noalias !752
  store i64 %277, ptr %11, align 8, !alias.scope !747, !noalias !787
  %278 = getelementptr inbounds nuw i8, ptr %11, i64 8
  store ptr %276, ptr %278, align 8, !alias.scope !747, !noalias !787
  %279 = getelementptr inbounds nuw i8, ptr %11, i64 16
  store i64 %275, ptr %279, align 8, !alias.scope !747, !noalias !787
  %280 = getelementptr inbounds nuw i8, ptr %11, i64 24
  store i64 0, ptr %280, align 8, !alias.scope !747, !noalias !787
  call void @llvm.lifetime.start.p0(ptr nonnull %10), !noalias !745
  store i64 0, ptr %10, align 8, !noalias !745
  %281 = getelementptr inbounds nuw i8, ptr %10, i64 8
  store ptr inttoptr (i64 8 to ptr), ptr %281, align 8, !noalias !745
  %282 = getelementptr inbounds nuw i8, ptr %10, i64 16
  store i64 0, ptr %282, align 8, !noalias !745
  br label %283

283:                                              ; preds = %295, %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i
  %_3.sroa.6.0.copyload = phi ptr [ %296, %295 ], [ inttoptr (i64 8 to ptr), %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i ]
  %_3.sroa.9.0.copyload = phi i64 [ %298, %295 ], [ 0, %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i ]
; call r7rs_wasm_reference::Reader::skip_space
  %284 = call fastcc noundef zeroext i1 @_ZN19r7rs_wasm_reference6Reader10skip_space17h8f14cc2594bb2e68E(ptr noalias noundef align 8 dereferenceable(32) %11) #67, !noalias !788
  br i1 %284, label %290, label %285

285:                                              ; preds = %283
  %_3.sroa.6.0.copyload.lcssa = phi ptr [ %_3.sroa.6.0.copyload, %283 ]
  %_3.sroa.9.0.copyload.lcssa = phi i64 [ %_3.sroa.9.0.copyload, %283 ]
  %_3.sroa.0.0.copyload = load i64, ptr %10, align 8, !noalias !742
  call void @llvm.lifetime.end.p0(ptr nonnull %10), !noalias !745
  %286 = load i64, ptr %11, align 8, !range !247, !noalias !745, !noundef !43
  %287 = icmp eq i64 %286, 0
  br i1 %287, label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, label %288

288:                                              ; preds = %285
  %289 = load ptr, ptr %278, align 8, !noalias !745, !nonnull !43, !noundef !43
  tail call void @free(ptr noundef nonnull %289) #67, !dbg !234, !noalias !788
  br label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i

290:                                              ; preds = %283
  call void @llvm.lifetime.start.p0(ptr nonnull %9), !noalias !745
; call r7rs_wasm_reference::Reader::datum
  call fastcc void @_ZN19r7rs_wasm_reference6Reader5datum17h7ae745f2407c5577E(ptr noalias noundef align 8 captures(address) dereferenceable(32) %9, ptr noalias noundef align 8 dereferenceable(32) %11) #67, !noalias !788
  tail call void @llvm.experimental.noalias.scope.decl(metadata !789)
  %291 = load i64, ptr %10, align 8, !range !247, !alias.scope !789, !noalias !792, !noundef !43
  %292 = icmp eq i64 %_3.sroa.9.0.copyload, %291
  br i1 %292, label %293, label %295

293:                                              ; preds = %290
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h93d0dd34c8f30447E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %10) #107, !noalias !794
  %294 = load ptr, ptr %281, align 8, !alias.scope !789, !noalias !792
  br label %295

295:                                              ; preds = %293, %290
  %296 = phi ptr [ %_3.sroa.6.0.copyload, %290 ], [ %294, %293 ]
  %297 = getelementptr inbounds nuw { i64, [3 x i64] }, ptr %296, i64 %_3.sroa.9.0.copyload
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %297, ptr noundef nonnull readonly align 8 dereferenceable(32) %9, i64 32, i1 false), !noalias !795
  %298 = add i64 %_3.sroa.9.0.copyload, 1
  store i64 %298, ptr %282, align 8, !alias.scope !789, !noalias !792
  call void @llvm.lifetime.end.p0(ptr nonnull %9), !noalias !745
  br label %283

_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i: ; preds = %288, %285
  call void @llvm.lifetime.end.p0(ptr nonnull %11), !noalias !745
  %299 = load i64, ptr %15, align 8, !range !247, !noalias !272, !noundef !43
  %300 = icmp eq i64 %299, 0
  br i1 %300, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, label %301

301:                                              ; preds = %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, %132
  %_3.sroa.9.0 = phi i64 [ undef, %132 ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.0 = phi ptr [ %119, %132 ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.0 = phi i64 [ -9223372036854775808, %132 ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %302 = load ptr, ptr %17, align 8, !noalias !272, !nonnull !43, !noundef !43
  tail call void @free(ptr noundef nonnull %302) #67, !dbg !234, !noalias !272
  br label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit: ; preds = %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, %301
  %_3.sroa.9.1 = phi i64 [ %_3.sroa.9.0, %301 ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.1 = phi ptr [ %_3.sroa.6.0, %301 ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.1 = phi i64 [ %_3.sroa.0.0, %301 ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %15), !noalias !272
  %303 = icmp eq i64 %_3.sroa.0.1, -9223372036854775808
  br i1 %303, label %bb14, label %bb16

bb16:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit
  %_33.not = icmp eq i64 %_3.sroa.9.1, 0
  br i1 %_33.not, label %panic, label %bb17

bb17:                                             ; preds = %bb16
  %304 = icmp ne ptr %_3.sroa.6.1, null
  tail call void @llvm.assume(i1 %304)
; call r7rs_wasm_reference::Datum::number
  %count = tail call fastcc noundef i64 @_ZN19r7rs_wasm_reference5Datum6number17h11d92c433e08e7b1E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %_3.sroa.6.1) #67
  %_41.not = icmp eq i64 %_3.sroa.9.1, 1
  br i1 %_41.not, label %panic1, label %bb18

panic:                                            ; preds = %bb16
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 0, i64 noundef 0, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_6ab71a0be8ce77214c0f86a837642cc0) #108
  unreachable

bb18:                                             ; preds = %bb17
  %_9 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 32
  tail call void @llvm.experimental.noalias.scope.decl(metadata !796)
  %305 = load i64, ptr %_9, align 8, !range !233, !alias.scope !796, !noundef !43
  %306 = icmp ne i64 %305, -9223372036854775805
  tail call void @llvm.assume(i1 %306)
  %307 = icmp slt i64 %305, -9223372036854775806
  br i1 %307, label %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit, label %308, !prof !799

308:                                              ; preds = %bb18
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.21, ptr noundef nonnull inttoptr (i64 53 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.23) #108, !noalias !796
  unreachable

_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit: ; preds = %bb18
  %309 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 48
  %310 = load ptr, ptr %309, align 8, !alias.scope !796, !nonnull !43, !noundef !43
  %311 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 56
  %312 = load i64, ptr %311, align 8, !alias.scope !796, !noundef !43
  %_46 = icmp ugt i64 %_3.sroa.9.1, 2
  br i1 %_46, label %bb19, label %panic2

panic1:                                           ; preds = %bb17
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 1, i64 noundef 1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_adb5c27321735eb352899c401f796d92) #108
  unreachable

bb19:                                             ; preds = %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit
  %_11 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 64
  tail call void @llvm.experimental.noalias.scope.decl(metadata !800)
  call void @llvm.lifetime.start.p0(ptr nonnull %7), !noalias !800
  tail call void @llvm.experimental.noalias.scope.decl(metadata !803)
  %313 = load i64, ptr %_11, align 8, !range !233, !alias.scope !806, !noundef !43
  %314 = icmp ne i64 %313, -9223372036854775805
  tail call void @llvm.assume(i1 %314)
  %315 = icmp slt i64 %313, -9223372036854775806
  br i1 %315, label %317, label %316, !prof !799

316:                                              ; preds = %bb19
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.21, ptr noundef nonnull inttoptr (i64 53 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.23) #108, !noalias !806
  unreachable

317:                                              ; preds = %bb19
  %318 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 80
  %319 = load ptr, ptr %318, align 8, !alias.scope !806, !nonnull !43, !noundef !43
  %320 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 88
  %321 = load i64, ptr %320, align 8, !alias.scope !806, !noundef !43
; call <f64 as core::str::traits::FromStr>::from_str
  call fastcc void @_RNvXs2_NtNtCsgEmfK2I1SDS_4core3num7dec2fltdNtNtNtB9_3str6traits7FromStr8from_str(ptr noalias noundef nonnull align 8 captures(address) dereferenceable(16) %7, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %319, i64 noundef %321) #107, !noalias !800
  tail call void @llvm.experimental.noalias.scope.decl(metadata !807)
  %322 = load i8, ptr %7, align 8, !range !181, !alias.scope !807, !noalias !800, !noundef !43
  %323 = trunc nuw i8 %322 to i1
  br i1 %323, label %324, label %_ZN19r7rs_wasm_reference5Datum4real17hd02df52f069da243E.exit, !prof !618

324:                                              ; preds = %317
  call void @llvm.lifetime.start.p0(ptr nonnull %6), !noalias !810
  %325 = getelementptr inbounds nuw i8, ptr %7, i64 1
  %326 = load i8, ptr %325, align 1, !range !181, !alias.scope !807, !noalias !800, !noundef !43
  store i8 %326, ptr %6, align 1, !noalias !810
; call core::result::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6result13unwrap_failed(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @anon.d3ffb10234040c548dbe347741c6fc8a.26, i64 noundef 22, ptr noundef nonnull align 1 %6, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) @anon.d3ffb10234040c548dbe347741c6fc8a.101, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.27) #108, !noalias !810
  unreachable

_ZN19r7rs_wasm_reference5Datum4real17hd02df52f069da243E.exit: ; preds = %317
  %327 = getelementptr inbounds nuw i8, ptr %7, i64 8
  %328 = load double, ptr %327, align 8, !alias.scope !807, !noalias !800, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %7), !noalias !800
; call <std::sys::pal::unix::time::Timespec>::now
  %329 = tail call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #67, !dbg !811
  %start.0 = extractvalue { i64, i32 } %329, 0
  %start.1 = extractvalue { i64, i32 } %329, 1
  store double 0.000000e+00, ptr %result, align 8
  %_4768.not = icmp eq i64 %count, 0
  br i1 %_4768.not, label %bb21, label %bb20.lr.ph

bb20.lr.ph:                                       ; preds = %_ZN19r7rs_wasm_reference5Datum4real17hd02df52f069da243E.exit
  %330 = getelementptr inbounds nuw i8, ptr %16, i64 8
  %_7.sroa.4.0._4.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %_4.i.i, i64 4
  %_7.sroa.5.0._4.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %_4.i.i, i64 8
  %_16.sroa.4.0.text.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %text.i.i, i64 8
  %_16.sroa.5.0.text.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %text.i.i, i64 16
  %_52.i.i.i = getelementptr inbounds nuw i8, ptr %bytes.i.i.i, i64 1
  %331 = getelementptr inbounds nuw i8, ptr %_26.i.i.i, i64 8
  %332 = getelementptr inbounds nuw i8, ptr %_26.i.i.i, i64 16
  %333 = getelementptr inbounds nuw i8, ptr %_14.i.i, i64 8
  %334 = ptrtoint ptr %3 to i64
  %335 = add i64 %334, 7
  %336 = and i64 %335, -8
  %337 = sub i64 %336, %334
  %338 = icmp ult i64 %337, 8
  %339 = icmp eq i64 %336, %334
  %340 = getelementptr inbounds nuw i8, ptr %5, i64 8
  %341 = getelementptr inbounds nuw i8, ptr %5, i64 4
  br label %bb20

panic2:                                           ; preds = %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 2, i64 noundef 2, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_0879021f8c7a68275cecdcec9b752b0f) #108
  unreachable

bb21.loopexit:                                    ; preds = %bb25
  %_22.pre = load double, ptr %result, align 8
  br label %bb21

bb21:                                             ; preds = %bb21.loopexit, %_ZN19r7rs_wasm_reference5Datum4real17hd02df52f069da243E.exit
  %_22 = phi double [ %_22.pre, %bb21.loopexit ], [ 0.000000e+00, %_ZN19r7rs_wasm_reference5Datum4real17hd02df52f069da243E.exit ]
  %_21 = fsub double %_22, %328
  %342 = call double @llvm.fabs.f64(double %_21)
  %_19 = fcmp ugt double %342, 1.000000e-09
  br i1 %_19, label %bb10, label %bb9, !prof !618

bb20:                                             ; preds = %bb20.lr.ph, %bb25
  %iter.sroa.0.069 = phi i64 [ 0, %bb20.lr.ph ], [ %_48, %bb25 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %16)
  store ptr %310, ptr %16, align 8
  store i64 %312, ptr %330, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %16) #67, !srcloc !229
  %_16.0 = load ptr, ptr %16, align 8, !nonnull !43, !align !63, !noundef !43
  %_16.1 = load i64, ptr %330, align 8, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %16)
  call void @llvm.lifetime.start.p0(ptr nonnull %_4.i.i), !noalias !822
  store i32 0, ptr %_4.i.i, align 4, !noalias !822
  store i32 438, ptr %_7.sroa.4.0._4.sroa_idx.i.i, align 4, !noalias !822
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 4 dereferenceable(6) %_7.sroa.5.0._4.sroa_idx.i.i, i8 0, i64 6, i1 false), !noalias !822
  store i8 1, ptr %_7.sroa.5.0._4.sroa_idx.i.i, align 4, !noalias !822
  call void @llvm.lifetime.start.p0(ptr nonnull %5), !dbg !829, !noalias !834
  call void @llvm.experimental.noalias.scope.decl(metadata !839), !dbg !829, !noalias !842
  call void @llvm.lifetime.start.p0(ptr nonnull %4), !dbg !843, !noalias !850
  store ptr %_4.i.i, ptr %4, align 8, !dbg !843, !noalias !850
  %343 = icmp ugt i64 %_16.1, 383, !dbg !853
  br i1 %343, label %404, label %344, !dbg !853, !prof !618

344:                                              ; preds = %bb20
  call void @llvm.experimental.noalias.scope.decl(metadata !861), !dbg !864, !noalias !842
  call void @llvm.lifetime.start.p0(ptr nonnull %3), !dbg !865, !noalias !868
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %3, ptr nonnull readonly align 1 %_16.0, i64 range(i64 0, 384) %_16.1, i1 false), !dbg !870, !noalias !875
  %345 = getelementptr inbounds nuw i8, ptr %3, i64 %_16.1, !dbg !876
  store i8 0, ptr %345, align 1, !dbg !879, !noalias !868
  %346 = add nuw nsw i64 %_16.1, 1, !dbg !884
  %347 = icmp ult i64 %_16.1, 15, !dbg !885
  br i1 %347, label %.preheader554, label %348, !dbg !885

348:                                              ; preds = %344
  call void @llvm.assume(i1 %338), !dbg !897, !noalias !920
  br i1 %339, label %349, label %.preheader278, !dbg !921

349:                                              ; preds = %348
  %350 = add nsw i64 %_16.1, -15
  br label %354, !dbg !923

351:                                              ; preds = %390
  %352 = add nsw i64 %_16.1, -15
  %353 = icmp ugt i64 %337, %352, !dbg !923
  br i1 %353, label %.loopexit277, label %354, !dbg !923

354:                                              ; preds = %351, %349
  %355 = phi i64 [ %350, %349 ], [ %352, %351 ]
  %356 = phi i64 [ 0, %349 ], [ %337, %351 ]
  br label %357, !dbg !925

357:                                              ; preds = %374, %354
  %358 = phi i64 [ %375, %374 ], [ %356, %354 ]
  %359 = getelementptr inbounds nuw i8, ptr %3, i64 %358, !dbg !930
  %360 = load i64, ptr %359, align 8, !dbg !933, !alias.scope !934, !noalias !943, !noundef !43
  %361 = getelementptr i8, ptr %359, i64 8, !dbg !945
  %362 = load i64, ptr %361, align 8, !dbg !947, !alias.scope !934, !noalias !943, !noundef !43
  %363 = sub i64 72340172838076672, %360, !dbg !948
  %364 = or i64 %363, %360, !dbg !948
  %365 = sub i64 72340172838076672, %362, !dbg !951
  %366 = or i64 %365, %362, !dbg !951
  %367 = and i64 %364, -9187201950435737472, !dbg !925
  %368 = and i64 %367, %366, !dbg !925
  %369 = icmp eq i64 %368, -9187201950435737472, !dbg !925
  br i1 %369, label %374, label %.loopexit277, !dbg !925

.loopexit277:                                     ; preds = %374, %357, %351
  %370 = phi i64 [ %337, %351 ], [ %375, %374 ], [ %358, %357 ], !dbg !953
  %371 = getelementptr inbounds nuw i8, ptr %3, i64 %370, !dbg !954
  %372 = sub i64 %346, %370, !dbg !956
  %373 = icmp eq i64 %346, %370, !dbg !957
  br i1 %373, label %.loopexit275, label %.preheader, !dbg !957

374:                                              ; preds = %357
  %375 = add i64 %358, 16, !dbg !963
  %376 = icmp ugt i64 %375, %355, !dbg !923
  br i1 %376, label %.loopexit277, label %357, !dbg !923

.preheader:                                       ; preds = %.loopexit277, %381
  %377 = phi i64 [ %382, %381 ], [ 0, %.loopexit277 ]
  %378 = getelementptr inbounds nuw i8, ptr %371, i64 %377, !dbg !964
  %379 = load i8, ptr %378, align 1, !dbg !964, !alias.scope !934, !noalias !943, !noundef !43
  %380 = icmp eq i8 %379, 0, !dbg !964
  br i1 %380, label %384, label %381, !dbg !964

381:                                              ; preds = %.preheader
  %382 = add nuw i64 %377, 1, !dbg !965
  %383 = icmp eq i64 %382, %372, !dbg !957
  br i1 %383, label %.loopexit275, label %.preheader, !dbg !957

384:                                              ; preds = %.preheader
  %.lcssa558 = phi i64 [ %377, %.preheader ]
  %385 = add i64 %.lcssa558, %370, !dbg !966
  br label %.loopexit, !dbg !967

.preheader278:                                    ; preds = %348, %390
  %386 = phi i64 [ %391, %390 ], [ 0, %348 ]
  %387 = getelementptr inbounds nuw i8, ptr %3, i64 %386, !dbg !968
  %388 = load i8, ptr %387, align 1, !dbg !968, !alias.scope !934, !noalias !943, !noundef !43
  %389 = icmp eq i8 %388, 0, !dbg !968
  br i1 %389, label %.loopexit, label %390, !dbg !968

390:                                              ; preds = %.preheader278
  %391 = add nuw nsw i64 %386, 1, !dbg !973
  %392 = icmp eq i64 %391, %337, !dbg !974
  br i1 %392, label %351, label %.preheader278, !dbg !974

.preheader554:                                    ; preds = %344, %397
  %393 = phi i64 [ %398, %397 ], [ 0, %344 ]
  %394 = getelementptr inbounds nuw i8, ptr %3, i64 %393, !dbg !975
  %395 = load i8, ptr %394, align 1, !dbg !975, !alias.scope !979, !noalias !943, !noundef !43
  %396 = icmp eq i8 %395, 0, !dbg !975
  br i1 %396, label %.loopexit, label %397, !dbg !975

397:                                              ; preds = %.preheader554
  %398 = add nuw nsw i64 %393, 1, !dbg !980
  %399 = icmp eq i64 %393, %_16.1, !dbg !981
  br i1 %399, label %.loopexit275, label %.preheader554, !dbg !981

.loopexit:                                        ; preds = %.preheader278, %.preheader554, %384
  %400 = phi i64 [ %385, %384 ], [ %393, %.preheader554 ], [ %386, %.preheader278 ]
  %401 = icmp eq i64 %400, %_16.1, !dbg !982
  br i1 %401, label %402, label %.loopexit275, !dbg !982

.loopexit275:                                     ; preds = %381, %397, %.loopexit, %.loopexit277
  store ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.73, ptr %340, align 8, !dbg !984, !alias.scope !985, !noalias !986
  store i32 1, ptr %5, align 8, !dbg !984, !alias.scope !985, !noalias !986
  br label %403, !dbg !987

402:                                              ; preds = %.loopexit
; call <std::sys::fs::unix::File>::open_c
  call fastcc void @_RNvMsi_NtNtNtCsjrHSEGnQ3l9_3std3sys2fs4unixNtB5_4File6open_c(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(16) %5, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %3, ptr noalias noundef nonnull readonly align 4 captures(address, read_provenance) dereferenceable(16) %_4.i.i) #67, !dbg !988, !noalias !994
  br label %403, !dbg !995

403:                                              ; preds = %402, %.loopexit275
  call void @llvm.lifetime.end.p0(ptr nonnull %3), !dbg !996, !noalias !868
  br label %405, !dbg !864

404:                                              ; preds = %bb20
; call std::sys::helpers::small_c_string::run_with_cstr_allocating::<std::sys::fs::unix::File>
  call fastcc void @_RINvNtNtNtCsjrHSEGnQ3l9_3std3sys7helpers14small_c_string24run_with_cstr_allocatingNtNtNtB6_2fs4unix4FileEB8_(ptr noalias noundef nonnull align 8 captures(address) dereferenceable(16) %5, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %_16.0, i64 noundef %_16.1, ptr noundef nonnull align 1 %4) #107, !dbg !997, !noalias !998
  br label %405, !dbg !997

405:                                              ; preds = %404, %403
  call void @llvm.lifetime.end.p0(ptr nonnull %4), !dbg !999, !noalias !850
  %406 = load i32, ptr %5, align 8, !dbg !1000, !range !1003, !noalias !834, !noundef !43
  %407 = trunc nuw i32 %406 to i1, !dbg !1004
  br i1 %407, label %bb10.i, label %bb11.i, !dbg !1004

bb10.i:                                           ; preds = %405
  %408 = load ptr, ptr %340, align 8, !dbg !1005, !noalias !834, !nonnull !43, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %5), !dbg !1006, !noalias !834
  call void @llvm.lifetime.end.p0(ptr nonnull %_4.i.i), !noalias !822
  br label %bb24

bb11.i:                                           ; preds = %405
  %409 = load i32, ptr %341, align 4, !dbg !1007, !range !1008, !noalias !834, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %5), !dbg !1006, !noalias !834
  call void @llvm.lifetime.end.p0(ptr nonnull %_4.i.i), !noalias !822
  %410 = call noundef dereferenceable_or_null(8192) ptr @malloc(i64 noundef 8192) #67, !dbg !765, !noalias !1009
  %411 = icmp eq ptr %410, null
  br i1 %411, label %bb3.i.i.i, label %bb3.i, !prof !618

bb3.i.i.i:                                        ; preds = %bb11.i
; call alloc::raw_vec::handle_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 8192) #106, !noalias !1014
  unreachable

bb3.i:                                            ; preds = %bb11.i, %bb5.i
  %port.i.sroa.25.1 = phi <2 x i64> [ %port.i.sroa.25.6, %bb5.i ], [ zeroinitializer, %bb11.i ]
  %port.i.sroa.14.1 = phi i64 [ %port.i.sroa.14.6, %bb5.i ], [ 0, %bb11.i ]
  %sum.sroa.0.0.i = phi double [ %471, %bb5.i ], [ 0.000000e+00, %bb11.i ]
  call void @llvm.lifetime.start.p0(ptr nonnull %text.i.i), !noalias !1015
  store i64 0, ptr %text.i.i, align 8, !noalias !1015
  store ptr inttoptr (i64 1 to ptr), ptr %_16.sroa.4.0.text.sroa_idx.i.i, align 8, !noalias !1015
  br label %bb1.i.i.sink.split

bb1.i.i.sink.split:                               ; preds = %bb3.i, %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i
  %port.i.sroa.25.15 = phi <2 x i64> [ %port.i.sroa.25.1, %bb3.i ], [ %port.i.sroa.25.4576, %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i ]
  %port.i.sroa.14.15 = phi i64 [ %port.i.sroa.14.1, %bb3.i ], [ %port.i.sroa.14.4571, %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i ]
  %new_len.i.i.i.sink = phi i64 [ 0, %bb3.i ], [ %new_len.i.i.i, %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i ]
  store i64 %new_len.i.i.i.sink, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !noalias !1015
  br label %bb6.i.i.i.i

bb6.i.i.i.i:                                      ; preds = %bb5.i.i, %bb1.i.i.sink.split
  %port.i.sroa.25.2 = phi <2 x i64> [ %port.i.sroa.25.15, %bb1.i.i.sink.split ], [ %port.i.sroa.25.4, %bb5.i.i ]
  %port.i.sroa.14.2 = phi i64 [ %port.i.sroa.14.15, %bb1.i.i.sink.split ], [ %port.i.sroa.14.4, %bb5.i.i ]
  call void @llvm.lifetime.start.p0(ptr nonnull %bytes.i.i.i), !noalias !1019
  store i32 0, ptr %bytes.i.i.i, align 4, !noalias !1019
  call void @llvm.experimental.noalias.scope.decl(metadata !1023)
  %port.i.sroa.25.24.vec.extract = extractelement <2 x i64> %port.i.sroa.25.2, i64 0
  %_3.not.i.i.i.i.i = icmp ult i64 %port.i.sroa.14.2, %port.i.sroa.25.24.vec.extract
  br i1 %_3.not.i.i.i.i.i, label %bb13.i.i.i.i, label %bb1.i.i.i.i.i

bb1.i.i.i.i.i:                                    ; preds = %bb6.i.i.i.i
  %412 = call noundef i64 @read(i32 noundef range(i32 0, -1) %409, ptr noundef nonnull %410, i64 noundef 8192) #67, !dbg !1026, !noalias !1040
  %413 = icmp eq i64 %412, -1, !dbg !1049
  br i1 %413, label %"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread", label %bb11.i.i.i.i.i, !dbg !1056

bb11.i.i.i.i.i:                                   ; preds = %bb1.i.i.i.i.i
  %port.i.sroa.25.32.vec.extract209 = extractelement <2 x i64> %port.i.sroa.25.2, i64 1
  %414 = insertelement <2 x i64> poison, i64 %412, i64 0, !dbg !1057
  %415 = call noundef i64 @llvm.umax.i64(i64 %412, i64 %port.i.sroa.25.32.vec.extract209), !dbg !1065
  %buf.i.i.i.i.i.sroa.7.24.vec.insert263 = insertelement <2 x i64> %414, i64 %415, i64 1, !dbg !1073
  br label %bb13.i.i.i.i

"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread": ; preds = %bb1.i.i.i.i.i
  %.lcssa596 = phi i32 [ %409, %bb1.i.i.i.i.i ], !dbg !1007
  %.lcssa588 = phi ptr [ %410, %bb1.i.i.i.i.i ], !dbg !765
  %416 = tail call noundef ptr @__errno_location() #67, !dbg !1074
  %417 = load i32, ptr %416, align 4, !dbg !1086, !noalias !1040, !noundef !43
  %418 = sext i32 %417 to i64, !dbg !1087
  %419 = shl nsw i64 %418, 32, !dbg !1095
  %420 = or disjoint i64 %419, 2, !dbg !1095
  %421 = inttoptr i64 %420 to ptr, !dbg !1096
  br label %bb20.i.i

bb13.i.i.i.i:                                     ; preds = %bb6.i.i.i.i, %bb11.i.i.i.i.i
  %port.i.sroa.25.14 = phi <2 x i64> [ %port.i.sroa.25.2, %bb6.i.i.i.i ], [ %buf.i.i.i.i.i.sroa.7.24.vec.insert263, %bb11.i.i.i.i.i ]
  %v2.i.i.i.i = phi i64 [ %port.i.sroa.25.24.vec.extract, %bb6.i.i.i.i ], [ %412, %bb11.i.i.i.i.i ]
  %_40.i.i.i.i = phi i64 [ %port.i.sroa.14.2, %bb6.i.i.i.i ], [ 0, %bb11.i.i.i.i.i ]
  call void @llvm.experimental.noalias.scope.decl(metadata !1097)
  %.not = icmp eq i64 %v2.i.i.i.i, %_40.i.i.i.i
  br i1 %.not, label %bb21.thread.i.i, label %bb23.i.i.i

bb23.i.i.i:                                       ; preds = %bb13.i.i.i.i
  %_38.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %410, i64 %_40.i.i.i.i
  %_9.i.i.i.i.i = load i8, ptr %_38.i.i.i.i.i, align 1, !noalias !1100, !noundef !43
  store i8 %_9.i.i.i.i.i, ptr %bytes.i.i.i, align 4, !alias.scope !1102, !noalias !1103
  %v1.i.i.i.i = add nuw i64 %_40.i.i.i.i, 1
  %..i.i.i.i.i = call noundef i64 @llvm.umin.i64(i64 %v2.i.i.i.i, i64 %v1.i.i.i.i)
  %_17.i.i.i = icmp sgt i8 %_9.i.i.i.i.i, -1
  br i1 %_17.i.i.i, label %bb26.i.i.i, label %bb5.i.i.i

bb5.i.i.i:                                        ; preds = %bb23.i.i.i
  %422 = add nsw i8 %_9.i.i.i.i.i, 62
  %or.cond5.i.i.i = icmp ult i8 %422, 30
  br i1 %or.cond5.i.i.i, label %bb26.i.i.i, label %bb7.i.i.i

bb7.i.i.i:                                        ; preds = %bb5.i.i.i
  %423 = and i8 %_9.i.i.i.i.i, -16
  %or.cond7.i.i.i = icmp eq i8 %423, -32
  br i1 %or.cond7.i.i.i, label %bb26.i.i.i, label %bb9.i.i.i

bb9.i.i.i:                                        ; preds = %bb7.i.i.i
  %424 = add nsw i8 %_9.i.i.i.i.i, 16
  %or.cond9.i.i.i = icmp ult i8 %424, 5
  br i1 %or.cond9.i.i.i, label %bb26.i.i.i, label %bb20.i.i

bb26.i.i.i:                                       ; preds = %bb9.i.i.i, %bb7.i.i.i, %bb5.i.i.i, %bb23.i.i.i
  %width.sroa.0.0.i.i.i = phi i64 [ 3, %bb7.i.i.i ], [ 1, %bb23.i.i.i ], [ 2, %bb5.i.i.i ], [ 4, %bb9.i.i.i ]
  %_50.i.i.i = add nsw i64 %width.sroa.0.0.i.i.i, -1
  %port.i.sroa.25.24.vec.extract205 = extractelement <2 x i64> %port.i.sroa.25.14, i64 0
  %new_len.i.i19.i.i.i = sub nuw i64 %port.i.sroa.25.24.vec.extract205, %..i.i.i.i.i
  %_20.not.i.not.i.i.i.i = icmp ugt i64 %_50.i.i.i, %new_len.i.i19.i.i.i
  br i1 %_20.not.i.not.i.i.i.i, label %bb6.i.i.i.i.i.i, label %_ZN3std2io8buffered9bufreader6buffer6Buffer12consume_with17h14188f319f28167cE.exit.thread.i.i.i.i

_ZN3std2io8buffered9bufreader6buffer6Buffer12consume_with17h14188f319f28167cE.exit.thread.i.i.i.i: ; preds = %bb26.i.i.i
  %_17.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %410, i64 %..i.i.i.i.i
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %_52.i.i.i, ptr nonnull readonly align 1 %_17.i.i.i.i.i, i64 range(i64 0, 4) %_50.i.i.i, i1 false), !alias.scope !1105, !noalias !1109
  %425 = add i64 %..i.i.i.i.i, %_50.i.i.i
  br label %bb31.i.i.i

bb6.i.i.i.i.i.i:                                  ; preds = %bb26.i.i.i, %bb18.i.i.i.i.i
  %port.i.sroa.25.9 = phi <2 x i64> [ %port.i.sroa.25.10246, %bb18.i.i.i.i.i ], [ %port.i.sroa.25.14, %bb26.i.i.i ]
  %port.i.sroa.14.9 = phi i64 [ %port.i.sroa.14.10248, %bb18.i.i.i.i.i ], [ %..i.i.i.i.i, %bb26.i.i.i ]
  %buf.sroa.0.059.i.i.i.i.i = phi ptr [ %buf.sroa.0.148.i.i.i.i.i, %bb18.i.i.i.i.i ], [ %_52.i.i.i, %bb26.i.i.i ]
  %buf.sroa.7.058.i.i.i.i.i = phi i64 [ %buf.sroa.7.146.i.i.i.i.i, %bb18.i.i.i.i.i ], [ %_50.i.i.i, %bb26.i.i.i ]
  call void @llvm.experimental.noalias.scope.decl(metadata !1115)
  %port.i.sroa.25.24.vec.extract207 = extractelement <2 x i64> %port.i.sroa.25.9, i64 0
  %_3.not.i.i.i.i.i.i.i = icmp ult i64 %port.i.sroa.14.9, %port.i.sroa.25.24.vec.extract207
  br i1 %_3.not.i.i.i.i.i.i.i, label %bb13.i.i.i.i.i.i, label %bb1.i.i.i.i.i.i.i

bb1.i.i.i.i.i.i.i:                                ; preds = %bb6.i.i.i.i.i.i
  %426 = call noundef i64 @read(i32 noundef range(i32 0, -1) %409, ptr noundef nonnull %410, i64 noundef 8192) #67, !dbg !1026, !noalias !1118
  %427 = icmp eq i64 %426, -1, !dbg !1049
  br i1 %427, label %bb7.i.i.i.i.i, label %bb11.i.i.i.i.i.i.i, !dbg !1056

bb11.i.i.i.i.i.i.i:                               ; preds = %bb1.i.i.i.i.i.i.i
  %port.i.sroa.25.32.vec.extract = extractelement <2 x i64> %port.i.sroa.25.9, i64 1
  %buf.i.i.i.i.i.i.i.sroa.7.16.vec.insert270 = insertelement <2 x i64> poison, i64 %426, i64 0, !dbg !1057
  %428 = call noundef i64 @llvm.umax.i64(i64 %426, i64 %port.i.sroa.25.32.vec.extract), !dbg !1065
  %buf.i.i.i.i.i.i.i.sroa.7.24.vec.insert273 = insertelement <2 x i64> %buf.i.i.i.i.i.i.i.sroa.7.16.vec.insert270, i64 %428, i64 1, !dbg !1073
  br label %bb13.i.i.i.i.i.i

bb13.i.i.i.i.i.i:                                 ; preds = %bb6.i.i.i.i.i.i, %bb11.i.i.i.i.i.i.i
  %port.i.sroa.25.12 = phi <2 x i64> [ %port.i.sroa.25.9, %bb6.i.i.i.i.i.i ], [ %buf.i.i.i.i.i.i.i.sroa.7.24.vec.insert273, %bb11.i.i.i.i.i.i.i ]
  %v2.i.i.i.i.i.i = phi i64 [ %port.i.sroa.25.24.vec.extract207, %bb6.i.i.i.i.i.i ], [ %426, %bb11.i.i.i.i.i.i.i ]
  %_40.i.i.i.i.i.i = phi i64 [ %port.i.sroa.14.9, %bb6.i.i.i.i.i.i ], [ 0, %bb11.i.i.i.i.i.i.i ]
  %_38.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %410, i64 %_40.i.i.i.i.i.i
  %new_len.i.i.i.i.i.i.i = sub nuw i64 %v2.i.i.i.i.i.i, %_40.i.i.i.i.i.i
  call void @llvm.experimental.noalias.scope.decl(metadata !1127)
  %..i.i.i.i.i.i.i.i = call noundef i64 @llvm.umin.i64(i64 %new_len.i.i.i.i.i.i.i, i64 range(i64 1, 4) %buf.sroa.7.058.i.i.i.i.i)
  %429 = icmp eq i64 %..i.i.i.i.i.i.i.i, 1
  br i1 %429, label %bb6.i.i.i.i.i.thread, label %bb6.i.i.i.i.i

bb6.i.i.i.i.i.thread:                             ; preds = %bb13.i.i.i.i.i.i
  %_9.i.i.i.i.i.i.i = load i8, ptr %_38.i.i.i.i.i.i.i, align 1, !noalias !1130, !noundef !43
  store i8 %_9.i.i.i.i.i.i.i, ptr %buf.sroa.0.059.i.i.i.i.i, align 1, !alias.scope !1132, !noalias !1136
  %v1.i.i.i.i.i.i252 = add i64 %_40.i.i.i.i.i.i, 1
  %..i.i.i.i.i.i.i253 = call noundef i64 @llvm.umin.i64(i64 %v2.i.i.i.i.i.i, i64 %v1.i.i.i.i.i.i252)
  br label %bb8.i.i.i.i.i

bb7.i.i.i.i.i:                                    ; preds = %bb1.i.i.i.i.i.i.i
  %buf.i.i.i.i.i.i.i.sroa.7.24.vec.insert527 = insertelement <2 x i64> %port.i.sroa.25.9, i64 0, i64 0
  %430 = tail call noundef ptr @__errno_location() #67, !dbg !1074
  %431 = load i32, ptr %430, align 4, !dbg !1086, !noalias !1118, !noundef !43
  %432 = icmp eq i32 %431, 4
  br i1 %432, label %bb18.i.i.i.i.i, label %bb20.i.i.loopexit.split.loop.exit603

bb6.i.i.i.i.i:                                    ; preds = %bb13.i.i.i.i.i.i
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %buf.sroa.0.059.i.i.i.i.i, ptr nonnull readonly align 1 %_38.i.i.i.i.i.i.i, i64 range(i64 0, -9223372036854775808) %..i.i.i.i.i.i.i.i, i1 false), !alias.scope !1139, !noalias !1143
  %v1.i.i.i.i.i.i = add i64 %..i.i.i.i.i.i.i.i, %_40.i.i.i.i.i.i
  %..i.i.i.i.i.i.i = call noundef i64 @llvm.umin.i64(i64 %v2.i.i.i.i.i.i, i64 %v1.i.i.i.i.i.i)
  %433 = icmp eq i64 %v2.i.i.i.i.i.i, %_40.i.i.i.i.i.i
  br i1 %433, label %bb20.i.i, label %bb8.i.i.i.i.i

bb8.i.i.i.i.i:                                    ; preds = %bb6.i.i.i.i.i.thread, %bb6.i.i.i.i.i
  %434 = phi i64 [ 1, %bb6.i.i.i.i.i.thread ], [ %..i.i.i.i.i.i.i.i, %bb6.i.i.i.i.i ]
  %..i.i.i.i.i.i.i254 = phi i64 [ %..i.i.i.i.i.i.i253, %bb6.i.i.i.i.i.thread ], [ %..i.i.i.i.i.i.i, %bb6.i.i.i.i.i ]
  %_30.i.i.i.i.i = icmp ult i64 %buf.sroa.7.058.i.i.i.i.i, %434
  br i1 %_30.i.i.i.i.i, label %bb29.i.i.i.i.i, label %bb20.i.i.i.i.i, !prof !618

bb29.i.i.i.i.i:                                   ; preds = %bb8.i.i.i.i.i
  %buf.sroa.7.058.i.i.i.i.i.lcssa563 = phi i64 [ %buf.sroa.7.058.i.i.i.i.i, %bb8.i.i.i.i.i ]
  %.lcssa562 = phi i64 [ %434, %bb8.i.i.i.i.i ]
; call core::slice::index::slice_index_fail
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core5slice5index16slice_index_fail(i64 noundef %.lcssa562, i64 noundef %buf.sroa.7.058.i.i.i.i.i.lcssa563, i64 noundef %buf.sroa.7.058.i.i.i.i.i.lcssa563, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_a88a27e379ff673f820bdb7f20f9ea85) #108, !noalias !1145
  unreachable

bb20.i.i.i.i.i:                                   ; preds = %bb8.i.i.i.i.i
  %new_len.i1.i.i.i.i = sub nuw nsw i64 %buf.sroa.7.058.i.i.i.i.i, %434
  %_37.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %buf.sroa.0.059.i.i.i.i.i, i64 %434
  br label %bb18.i.i.i.i.i

bb18.i.i.i.i.i:                                   ; preds = %bb7.i.i.i.i.i, %bb20.i.i.i.i.i
  %port.i.sroa.14.10248 = phi i64 [ %..i.i.i.i.i.i.i254, %bb20.i.i.i.i.i ], [ 0, %bb7.i.i.i.i.i ]
  %port.i.sroa.25.10246 = phi <2 x i64> [ %port.i.sroa.25.12, %bb20.i.i.i.i.i ], [ %buf.i.i.i.i.i.i.i.sroa.7.24.vec.insert527, %bb7.i.i.i.i.i ]
  %buf.sroa.0.148.i.i.i.i.i = phi ptr [ %_37.i.i.i.i.i, %bb20.i.i.i.i.i ], [ %buf.sroa.0.059.i.i.i.i.i, %bb7.i.i.i.i.i ]
  %buf.sroa.7.146.i.i.i.i.i = phi i64 [ %new_len.i1.i.i.i.i, %bb20.i.i.i.i.i ], [ %buf.sroa.7.058.i.i.i.i.i, %bb7.i.i.i.i.i ]
  %435 = icmp eq i64 %buf.sroa.7.146.i.i.i.i.i, 0
  br i1 %435, label %bb31.i.i.i, label %bb6.i.i.i.i.i.i

bb31.i.i.i:                                       ; preds = %bb18.i.i.i.i.i, %_ZN3std2io8buffered9bufreader6buffer6Buffer12consume_with17h14188f319f28167cE.exit.thread.i.i.i.i
  %port.i.sroa.25.4 = phi <2 x i64> [ %port.i.sroa.25.14, %_ZN3std2io8buffered9bufreader6buffer6Buffer12consume_with17h14188f319f28167cE.exit.thread.i.i.i.i ], [ %port.i.sroa.25.10246, %bb18.i.i.i.i.i ]
  %port.i.sroa.14.4 = phi i64 [ %425, %_ZN3std2io8buffered9bufreader6buffer6Buffer12consume_with17h14188f319f28167cE.exit.thread.i.i.i.i ], [ %port.i.sroa.14.10248, %bb18.i.i.i.i.i ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_26.i.i.i), !noalias !1019
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %_26.i.i.i, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %bytes.i.i.i, i64 noundef %width.sroa.0.0.i.i.i) #67, !noalias !1145
  %_66.i.i.i = load i64, ptr %_26.i.i.i, align 8, !range !474, !noalias !1019, !noundef !43
  %436 = trunc nuw i64 %_66.i.i.i to i1
  br i1 %436, label %bb36.i.i.i, label %bb37.i.i.i

bb36.i.i.i:                                       ; preds = %bb31.i.i.i
  %.lcssa600 = phi i32 [ %409, %bb31.i.i.i ], !dbg !1007
  %.lcssa592 = phi ptr [ %410, %bb31.i.i.i ], !dbg !765
  call void @llvm.lifetime.end.p0(ptr nonnull %_26.i.i.i), !noalias !1019
  br label %bb20.i.i

bb37.i.i.i:                                       ; preds = %bb31.i.i.i
  %_67.0.i.i.i = load ptr, ptr %331, align 8, !noalias !1019, !nonnull !43, !align !63, !noundef !43
  %_67.1.i.i.i = load i64, ptr %332, align 8, !noalias !1019, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %_26.i.i.i), !noalias !1019
  %_6.i.i.not.i.i.i = icmp samesign eq i64 %_67.1.i.i.i, 0
  br i1 %_6.i.i.not.i.i.i, label %bb21.thread.i.i, label %bb14.i.i.i.i

bb14.i.i.i.i:                                     ; preds = %bb37.i.i.i
  %x.i.i.i.i = load i8, ptr %_67.0.i.i.i, align 1, !noalias !1146, !noundef !43
  %_7.i.i.i.i = icmp sgt i8 %x.i.i.i.i, -1
  br i1 %_7.i.i.i.i, label %bb3.i.i.i.i, label %bb4.i.i.i.i

bb4.i.i.i.i:                                      ; preds = %bb14.i.i.i.i
  %_16.i.i20.i.i.i = getelementptr inbounds nuw i8, ptr %_67.0.i.i.i, i64 1
  %_33.i.i.i.i = and i8 %x.i.i.i.i, 31
  %init.i.i.i.i = zext nneg i8 %_33.i.i.i.i to i32
  %_6.i10.i.i.i.i = icmp samesign ne i64 %_67.1.i.i.i, 1
  call void @llvm.assume(i1 %_6.i10.i.i.i.i)
  %y.i.i.i.i = load i8, ptr %_16.i.i20.i.i.i, align 1, !noalias !1146, !noundef !43
  %_36.i.i.i.i = shl nuw nsw i32 %init.i.i.i.i, 6
  %_38.i.i.i.i = and i8 %y.i.i.i.i, 63
  %_37.i.i.i.i = zext nneg i8 %_38.i.i.i.i to i32
  %437 = or disjoint i32 %_36.i.i.i.i, %_37.i.i.i.i
  %_14.i.i.i.i = icmp samesign ugt i8 %x.i.i.i.i, -33
  br i1 %_14.i.i.i.i, label %bb6.i23.i.i.i, label %bb21.i.i

bb3.i.i.i.i:                                      ; preds = %bb14.i.i.i.i
  %_8.i.i.i.i = zext nneg i8 %x.i.i.i.i to i32
  br label %bb21.i.i

bb6.i23.i.i.i:                                    ; preds = %bb4.i.i.i.i
  %_16.i12.i.i.i.i = getelementptr inbounds nuw i8, ptr %_67.0.i.i.i, i64 2
  %_6.i17.i.i.i.i = icmp samesign ne i64 %_67.1.i.i.i, 2
  call void @llvm.assume(i1 %_6.i17.i.i.i.i)
  %z.i.i.i.i = load i8, ptr %_16.i12.i.i.i.i, align 1, !noalias !1146, !noundef !43
  %_41.i.i.i.i = shl nuw nsw i32 %_37.i.i.i.i, 6
  %_43.i.i.i.i = and i8 %z.i.i.i.i, 63
  %_42.i.i.i.i = zext nneg i8 %_43.i.i.i.i to i32
  %y_z.i.i.i.i = or disjoint i32 %_41.i.i.i.i, %_42.i.i.i.i
  %_21.i.i.i.i = shl nuw nsw i32 %init.i.i.i.i, 12
  %438 = or disjoint i32 %y_z.i.i.i.i, %_21.i.i.i.i
  %_22.i.i.i.i = icmp samesign ugt i8 %x.i.i.i.i, -17
  br i1 %_22.i.i.i.i, label %bb8.i.i.i.i, label %bb21.i.i

bb8.i.i.i.i:                                      ; preds = %bb6.i23.i.i.i
  %_16.i19.i.i.i.i = getelementptr inbounds nuw i8, ptr %_67.0.i.i.i, i64 3
  %_6.i24.i.i.i.i = icmp samesign ne i64 %_67.1.i.i.i, 3
  call void @llvm.assume(i1 %_6.i24.i.i.i.i)
  %w.i.i.i.i = load i8, ptr %_16.i19.i.i.i.i, align 1, !noalias !1146, !noundef !43
  %_27.i.i.i.i = shl nuw nsw i32 %init.i.i.i.i, 18
  %_26.i.i.i.i = and i32 %_27.i.i.i.i, 1835008
  %_46.i.i.i.i = shl nuw nsw i32 %y_z.i.i.i.i, 6
  %_48.i.i.i.i = and i8 %w.i.i.i.i, 63
  %_47.i.i.i.i = zext nneg i8 %_48.i.i.i.i to i32
  %_28.i.i.i.i = or disjoint i32 %_46.i.i.i.i, %_47.i.i.i.i
  %439 = or disjoint i32 %_28.i.i.i.i, %_26.i.i.i.i
  br label %bb21.i.i

bb20.i.i.loopexit.split.loop.exit603:             ; preds = %bb7.i.i.i.i.i
  %.lcssa610 = phi i32 [ %431, %bb7.i.i.i.i.i ]
  %.lcssa598.ph604 = phi i32 [ %409, %bb7.i.i.i.i.i ]
  %.lcssa590.ph605 = phi ptr [ %410, %bb7.i.i.i.i.i ]
  %440 = sext i32 %.lcssa610 to i64
  %441 = shl nsw i64 %440, 32
  %442 = or disjoint i64 %441, 2
  %443 = inttoptr i64 %442 to ptr
  br label %bb20.i.i

bb20.i.i:                                         ; preds = %bb9.i.i.i, %bb20.i.i.loopexit.split.loop.exit603, %bb6.i.i.i.i.i, %"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread", %bb36.i.i.i
  %444 = phi i32 [ %.lcssa596, %"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread" ], [ %.lcssa600, %bb36.i.i.i ], [ %409, %bb6.i.i.i.i.i ], [ %.lcssa598.ph604, %bb20.i.i.loopexit.split.loop.exit603 ], [ %409, %bb9.i.i.i ]
  %445 = phi ptr [ %.lcssa588, %"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread" ], [ %.lcssa592, %bb36.i.i.i ], [ %410, %bb6.i.i.i.i.i ], [ %.lcssa590.ph605, %bb20.i.i.loopexit.split.loop.exit603 ], [ %410, %bb9.i.i.i ]
  %_4.sroa.8.1.ph.i.i = phi ptr [ %421, %"_ZN82_$LT$std..io..buffered..bufreader..BufReader$LT$R$GT$$u20$as$u20$std..io..Read$GT$4read17h847c498895aa8df8E.exit.i.i.i.thread" ], [ inttoptr (i64 90194313219 to ptr), %bb36.i.i.i ], [ @alloc_6267043576f6d5bfcf8d6dfb9352cc26, %bb6.i.i.i.i.i ], [ %443, %bb20.i.i.loopexit.split.loop.exit603 ], [ inttoptr (i64 90194313219 to ptr), %bb9.i.i.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %bytes.i.i.i), !noalias !1019
  %text.val.i.i = load i64, ptr %text.i.i, align 8, !range !247, !noalias !1015, !noundef !43
  %446 = icmp eq i64 %text.val.i.i, 0
  br i1 %446, label %"_ZN4core3ptr81drop_in_place$LT$std..io..buffered..bufreader..BufReader$LT$std..fs..File$GT$$GT$17h41715630dc6f2039E.exit.i", label %_ZN4sum111read_number17h9f925a3d0a921f93E.exit.thread18.i

_ZN4sum111read_number17h9f925a3d0a921f93E.exit.thread18.i: ; preds = %bb20.i.i
  %text.val4.i22.i = load ptr, ptr %_16.sroa.4.0.text.sroa_idx.i.i, align 8, !noalias !1015, !nonnull !43, !noundef !43
  call void @free(ptr noundef nonnull %text.val4.i22.i) #67, !dbg !234
  br label %"_ZN4core3ptr81drop_in_place$LT$std..io..buffered..bufreader..BufReader$LT$std..fs..File$GT$$GT$17h41715630dc6f2039E.exit.i"

bb21.thread.i.i:                                  ; preds = %bb37.i.i.i, %bb13.i.i.i.i
  %port.i.sroa.25.8 = phi <2 x i64> [ %port.i.sroa.25.14, %bb13.i.i.i.i ], [ %port.i.sroa.25.4, %bb37.i.i.i ]
  %port.i.sroa.14.8 = phi i64 [ %v2.i.i.i.i, %bb13.i.i.i.i ], [ %port.i.sroa.14.4, %bb37.i.i.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %bytes.i.i.i), !noalias !1019
  br label %bb11.i.i

bb21.i.i:                                         ; preds = %bb8.i.i.i.i, %bb6.i23.i.i.i, %bb3.i.i.i.i, %bb4.i.i.i.i
  %_4.sroa.5.1.i.i = phi i32 [ %437, %bb4.i.i.i.i ], [ %438, %bb6.i23.i.i.i ], [ %439, %bb8.i.i.i.i ], [ %_8.i.i.i.i, %bb3.i.i.i.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %bytes.i.i.i), !noalias !1019
  switch i32 %_4.sroa.5.1.i.i, label %bb23.i.i [
    i32 1114112, label %bb11.i.i
    i32 32, label %bb5.i.i
  ]

bb23.i.i:                                         ; preds = %bb21.i.i
  %447 = add nsw i32 %_4.sroa.5.1.i.i, -9
  %or.cond.i.i = icmp ult i32 %447, 5
  br i1 %or.cond.i.i, label %bb5.i.i, label %bb22.i.i

bb22.i.i:                                         ; preds = %bb23.i.i
  %_26.i.i = icmp samesign ult i32 %_4.sroa.5.1.i.i, 128
  br i1 %_26.i.i, label %bb8.i.i, label %bb26.i.i

bb26.i.i:                                         ; preds = %bb22.i.i
  %_3.i.i.i = lshr i32 %_4.sroa.5.1.i.i, 8
  switch i32 %_3.i.i.i, label %bb3.i7.i.i [
    i32 0, label %bb6.i.i.i
    i32 22, label %bb4.i.i.i
    i32 32, label %bb7.i5.i.i
    i32 48, label %bb2.i.i.i
  ]

bb4.i.i.i:                                        ; preds = %bb26.i.i
  %448 = icmp eq i32 %_4.sroa.5.1.i.i, 5760
  %449 = zext i1 %448 to i8
  br label %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i

bb2.i.i.i:                                        ; preds = %bb26.i.i
  %450 = icmp eq i32 %_4.sroa.5.1.i.i, 12288
  %451 = zext i1 %450 to i8
  br label %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i

bb6.i.i.i:                                        ; preds = %bb26.i.i
  %452 = and i32 %_4.sroa.5.1.i.i, 255
  %_8.i.i.i = zext nneg i32 %452 to i64
  %453 = getelementptr inbounds nuw i8, ptr @_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space14WHITESPACE_MAP, i64 %_8.i.i.i
  %_6.i.i.i = load i8, ptr %453, align 1, !noalias !1015, !noundef !43
  br label %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i

bb7.i5.i.i:                                       ; preds = %bb26.i.i
  %454 = and i32 %_4.sroa.5.1.i.i, 255
  %_14.i.i.i = zext nneg i32 %454 to i64
  %455 = getelementptr inbounds nuw i8, ptr @_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space14WHITESPACE_MAP, i64 %_14.i.i.i
  %_12.i.i.i = load i8, ptr %455, align 1, !noalias !1015, !noundef !43
  %_11.i.i.i = lshr i8 %_12.i.i.i, 1
  br label %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i

_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i: ; preds = %bb7.i5.i.i, %bb6.i.i.i, %bb2.i.i.i, %bb4.i.i.i
  %_0.sroa.0.0.i.i.i = phi i8 [ %451, %bb2.i.i.i ], [ %_6.i.i.i, %bb6.i.i.i ], [ %449, %bb4.i.i.i ], [ %_11.i.i.i, %bb7.i5.i.i ]
  %456 = trunc i8 %_0.sroa.0.0.i.i.i to i1
  br i1 %456, label %bb5.i.i, label %bb3.i7.i.i

bb8.i.i:                                          ; preds = %bb22.i.i
  %_4.sroa.5.1.i.i.lcssa577 = phi i32 [ %_4.sroa.5.1.i.i, %bb22.i.i ]
  %port.i.sroa.25.4.lcssa573 = phi <2 x i64> [ %port.i.sroa.25.4, %bb22.i.i ]
  %port.i.sroa.14.4.lcssa568 = phi i64 [ %port.i.sroa.14.4, %bb22.i.i ]
  %_26.i.i.lcssa = phi i1 [ %_26.i.i, %bb22.i.i ]
  call void @llvm.experimental.noalias.scope.decl(metadata !1149)
  %len.i.i.i = load i64, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !alias.scope !1149, !noalias !1015, !noundef !43
  %_14.i6.i.i = icmp sgt i64 %len.i.i.i, -1
  call void @llvm.assume(i1 %_14.i6.i.i)
  br label %bb2.i10.i.i

bb3.i7.i.i:                                       ; preds = %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i, %bb26.i.i
  %_4.sroa.5.1.i.i.lcssa578 = phi i32 [ %_4.sroa.5.1.i.i, %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i ], [ %_4.sroa.5.1.i.i, %bb26.i.i ]
  %port.i.sroa.25.4.lcssa574 = phi <2 x i64> [ %port.i.sroa.25.4, %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i ], [ %port.i.sroa.25.4, %bb26.i.i ]
  %port.i.sroa.14.4.lcssa569 = phi i64 [ %port.i.sroa.14.4, %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i ], [ %port.i.sroa.14.4, %bb26.i.i ]
  %_26.i.i.lcssa565 = phi i1 [ %_26.i.i, %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i ], [ %_26.i.i, %bb26.i.i ]
  %len.i39.i.i = load i64, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !alias.scope !1152, !noalias !1015, !noundef !43
  %_14.i640.i.i = icmp sgt i64 %len.i39.i.i, -1
  call void @llvm.assume(i1 %_14.i640.i.i)
  %_17.i8.i.i = icmp samesign ult i32 %_4.sroa.5.1.i.i.lcssa578, 2048
  br i1 %_17.i8.i.i, label %bb2.i10.i.i, label %bb4.i9.i.i

bb4.i9.i.i:                                       ; preds = %bb3.i7.i.i
  %_18.i.i.i = icmp samesign ult i32 %_4.sroa.5.1.i.i.lcssa578, 65536
  %..i.i.i = select i1 %_18.i.i.i, i64 3, i64 4
  br label %bb2.i10.i.i

bb2.i10.i.i:                                      ; preds = %bb4.i9.i.i, %bb3.i7.i.i, %bb8.i.i
  %_4.sroa.5.1.i.i580 = phi i32 [ %_4.sroa.5.1.i.i.lcssa578, %bb3.i7.i.i ], [ %_4.sroa.5.1.i.i.lcssa578, %bb4.i9.i.i ], [ %_4.sroa.5.1.i.i.lcssa577, %bb8.i.i ]
  %port.i.sroa.25.4576 = phi <2 x i64> [ %port.i.sroa.25.4.lcssa574, %bb3.i7.i.i ], [ %port.i.sroa.25.4.lcssa574, %bb4.i9.i.i ], [ %port.i.sroa.25.4.lcssa573, %bb8.i.i ]
  %port.i.sroa.14.4571 = phi i64 [ %port.i.sroa.14.4.lcssa569, %bb3.i7.i.i ], [ %port.i.sroa.14.4.lcssa569, %bb4.i9.i.i ], [ %port.i.sroa.14.4.lcssa568, %bb8.i.i ]
  %_26.i.i566 = phi i1 [ %_26.i.i.lcssa565, %bb3.i7.i.i ], [ %_26.i.i.lcssa565, %bb4.i9.i.i ], [ %_26.i.i.lcssa, %bb8.i.i ]
  %len.i45.i.i = phi i64 [ %len.i39.i.i, %bb3.i7.i.i ], [ %len.i39.i.i, %bb4.i9.i.i ], [ %len.i.i.i, %bb8.i.i ]
  %ch_len.sroa.0.0.i.i.i = phi i64 [ 2, %bb3.i7.i.i ], [ %..i.i.i, %bb4.i9.i.i ], [ 1, %bb8.i.i ]
  %self2.i.i.i.i = load i64, ptr %text.i.i, align 8, !range !247, !alias.scope !1154, !noalias !1015, !noundef !43
  %_9.i.i.i.i = sub nsw i64 %self2.i.i.i.i, %len.i45.i.i
  %_7.i.i11.i.i = icmp ugt i64 %ch_len.sroa.0.0.i.i.i, %_9.i.i.i.i
  br i1 %_7.i.i11.i.i, label %bb1.i.i.i.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17h3ad626e797474f5eE.exit.i.i.i", !prof !618

bb1.i.i.i.i:                                      ; preds = %bb2.i10.i.i
; call alloc::raw_vec::RawVecInner<A>::reserve::do_reserve_and_handle
  call fastcc void @"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$7reserve21do_reserve_and_handle17h344dccae7007051bE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %text.i.i, i64 noundef %len.i45.i.i, i64 noundef range(i64 1, 5) %ch_len.sroa.0.0.i.i.i) #67
  %count.pre.i.i.i = load i64, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !alias.scope !1149, !noalias !1015
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17h3ad626e797474f5eE.exit.i.i.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17h3ad626e797474f5eE.exit.i.i.i": ; preds = %bb1.i.i.i.i, %bb2.i10.i.i
  %count.i.i.i = phi i64 [ %len.i45.i.i, %bb2.i10.i.i ], [ %count.pre.i.i.i, %bb1.i.i.i.i ]
  %_20.i.i.i = load ptr, ptr %_16.sroa.4.0.text.sroa_idx.i.i, align 8, !alias.scope !1149, !noalias !1015, !nonnull !43, !noundef !43
  %_21.i.i.i = icmp sgt i64 %count.i.i.i, -1
  call void @llvm.assume(i1 %_21.i.i.i)
  %_8.i12.i.i = getelementptr inbounds nuw i8, ptr %_20.i.i.i, i64 %count.i.i.i
  br i1 %_26.i.i566, label %bb12.i.i23.i.i, label %bb7.i.i.i.i

bb7.i.i.i.i:                                      ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17h3ad626e797474f5eE.exit.i.i.i"
  %_27.i.i13.i.i = icmp samesign ult i32 %_4.sroa.5.1.i.i580, 2048
  %457 = trunc i32 %_4.sroa.5.1.i.i580 to i8
  %_5.i.i.i.i = and i8 %457, 63
  %last1.i.i.i.i = or disjoint i8 %_5.i.i.i.i, -128
  %_10.i.i.i.i = lshr i32 %_4.sroa.5.1.i.i580, 6
  %458 = trunc i32 %_10.i.i.i.i to i8
  %_8.i.i14.i.i = and i8 %458, 63
  %last2.i.i.i.i = or disjoint i8 %_8.i.i14.i.i, -128
  %_14.i.i15.i.i = lshr i32 %_4.sroa.5.1.i.i580, 12
  %459 = trunc i32 %_14.i.i15.i.i to i8
  %_12.i.i.i.i = and i8 %459, 63
  %last3.i.i.i.i = or disjoint i8 %_12.i.i.i.i, -128
  %_18.i.i.i.i = lshr i32 %_4.sroa.5.1.i.i580, 18
  %_16.i.i.i.i = trunc nuw nsw i32 %_18.i.i.i.i to i8
  %last4.i.i.i.i = or disjoint i8 %_16.i.i.i.i, -16
  br i1 %_27.i.i13.i.i, label %bb1.i2.i.i.i, label %bb2.i.i16.i.i

bb12.i.i23.i.i:                                   ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17h3ad626e797474f5eE.exit.i.i.i"
  %460 = trunc nuw nsw i32 %_4.sroa.5.1.i.i580 to i8
  store i8 %460, ptr %_8.i12.i.i, align 1, !noalias !1157
  br label %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i

bb1.i2.i.i.i:                                     ; preds = %bb7.i.i.i.i
  %461 = or disjoint i8 %458, -64
  store i8 %461, ptr %_8.i12.i.i, align 1, !noalias !1157
  %_20.i.i.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 1
  store i8 %last1.i.i.i.i, ptr %_20.i.i.i.i, align 1, !noalias !1157
  br label %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i

bb2.i.i16.i.i:                                    ; preds = %bb7.i.i.i.i
  %_28.i.i17.i.i = icmp samesign ult i32 %_4.sroa.5.1.i.i580, 65536
  br i1 %_28.i.i17.i.i, label %bb3.i.i20.i.i, label %bb4.i.i18.i.i

bb3.i.i20.i.i:                                    ; preds = %bb2.i.i16.i.i
  %462 = or disjoint i8 %459, -32
  store i8 %462, ptr %_8.i12.i.i, align 1, !noalias !1157
  %_21.i.i21.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 1
  store i8 %last2.i.i.i.i, ptr %_21.i.i21.i.i, align 1, !noalias !1157
  %_22.i.i22.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 2
  store i8 %last1.i.i.i.i, ptr %_22.i.i22.i.i, align 1, !noalias !1157
  br label %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i

bb4.i.i18.i.i:                                    ; preds = %bb2.i.i16.i.i
  store i8 %last4.i.i.i.i, ptr %_8.i12.i.i, align 1, !noalias !1157
  %_23.i.i.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 1
  store i8 %last3.i.i.i.i, ptr %_23.i.i.i.i, align 1, !noalias !1157
  %_24.i.i.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 2
  store i8 %last2.i.i.i.i, ptr %_24.i.i.i.i, align 1, !noalias !1157
  %_25.i.i19.i.i = getelementptr inbounds nuw i8, ptr %_8.i12.i.i, i64 3
  store i8 %last1.i.i.i.i, ptr %_25.i.i19.i.i, align 1, !noalias !1157
  br label %_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i

_RNvMNtCslNYArtu3iFV_5alloc6stringNtB2_6String4push.exit.i.i: ; preds = %bb4.i.i18.i.i, %bb3.i.i20.i.i, %bb1.i2.i.i.i, %bb12.i.i23.i.i
  %new_len.i.i.i = add nuw i64 %ch_len.sroa.0.0.i.i.i, %len.i45.i.i
  br label %bb1.i.i.sink.split

bb5.i.i:                                          ; preds = %_RNvNtNtNtCsgEmfK2I1SDS_4core7unicode12unicode_data11white_space6lookup.exit.i.i, %bb23.i.i, %bb21.i.i
  %_27.i.i = load i64, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !noalias !1015, !noundef !43
  %_28.i.i = icmp sgt i64 %_27.i.i, -1
  call void @llvm.assume(i1 %_28.i.i)
  %463 = icmp eq i64 %_27.i.i, 0
  br i1 %463, label %bb6.i.i.i.i, label %bb13.i.i

bb11.i.i:                                         ; preds = %bb21.i.i, %bb21.thread.i.i
  %port.i.sroa.25.7 = phi <2 x i64> [ %port.i.sroa.25.8, %bb21.thread.i.i ], [ %port.i.sroa.25.4, %bb21.i.i ]
  %port.i.sroa.14.7 = phi i64 [ %port.i.sroa.14.8, %bb21.thread.i.i ], [ %port.i.sroa.14.4, %bb21.i.i ]
  %_29.pr.i.i = load i64, ptr %_16.sroa.5.0.text.sroa_idx.i.i, align 8, !noalias !1015
  %_30.i.i = icmp sgt i64 %_29.pr.i.i, -1
  call void @llvm.assume(i1 %_30.i.i)
  %464 = icmp eq i64 %_29.pr.i.i, 0
  br i1 %464, label %bb15.i.i, label %bb13.i.i

bb13.i.i:                                         ; preds = %bb5.i.i, %bb11.i.i
  %port.i.sroa.25.5 = phi <2 x i64> [ %port.i.sroa.25.7, %bb11.i.i ], [ %port.i.sroa.25.4, %bb5.i.i ]
  %port.i.sroa.14.5 = phi i64 [ %port.i.sroa.14.7, %bb11.i.i ], [ %port.i.sroa.14.4, %bb5.i.i ]
  %_2950.i.i = phi i64 [ %_29.pr.i.i, %bb11.i.i ], [ %_27.i.i, %bb5.i.i ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_14.i.i), !noalias !1015
  %_35.i.i = load ptr, ptr %_16.sroa.4.0.text.sroa_idx.i.i, align 8, !noalias !1015, !nonnull !43, !noundef !43
; call <f64 as core::str::traits::FromStr>::from_str
  call fastcc void @_RNvXs2_NtNtCsgEmfK2I1SDS_4core3num7dec2fltdNtNtNtB9_3str6traits7FromStr8from_str(ptr noalias noundef nonnull align 8 captures(address) dereferenceable(16) %_14.i.i, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %_35.i.i, i64 noundef %_2950.i.i) #107, !noalias !1158
  call void @llvm.experimental.noalias.scope.decl(metadata !1159)
  %465 = load i8, ptr %_14.i.i, align 8, !range !181, !alias.scope !1159, !noalias !1015, !noundef !43
  %466 = trunc nuw i8 %465 to i1
  br i1 %466, label %bb2.i25.i.i, label %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i", !prof !618

bb2.i25.i.i:                                      ; preds = %bb13.i.i
  call void @llvm.lifetime.start.p0(ptr nonnull %e.i.i.i), !noalias !1162
  %467 = getelementptr inbounds nuw i8, ptr %_14.i.i, i64 1
  %468 = load i8, ptr %467, align 1, !range !181, !alias.scope !1159, !noalias !1015, !noundef !43
  store i8 %468, ptr %e.i.i.i, align 1, !noalias !1162
; call core::result::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6result13unwrap_failed(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @alloc_56c71436c5446be1435fed115caba36c, i64 noundef 18, ptr noundef nonnull align 1 %e.i.i.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) @vtable.2, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_ee09c00b7705b8ec86cae7e001d1fb36) #108, !noalias !1163
  unreachable

"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i": ; preds = %bb13.i.i
  %t.i.i2324.i = load double, ptr %333, align 8, !alias.scope !1159, !noalias !1015, !noundef !43
  call void @llvm.lifetime.end.p0(ptr nonnull %_14.i.i), !noalias !1015
  br label %bb15.i.i

bb15.i.i:                                         ; preds = %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i", %bb11.i.i
  %port.i.sroa.25.6 = phi <2 x i64> [ %port.i.sroa.25.7, %bb11.i.i ], [ %port.i.sroa.25.5, %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i" ]
  %port.i.sroa.14.6 = phi i64 [ %port.i.sroa.14.7, %bb11.i.i ], [ %port.i.sroa.14.5, %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i" ]
  %_12.sroa.0.0.i.i = phi i1 [ false, %bb11.i.i ], [ true, %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i" ]
  %469 = phi double [ undef, %bb11.i.i ], [ %t.i.i2324.i, %"_ZN4core6result19Result$LT$T$C$E$GT$6expect17ha63b907b65a52ac0E.exit.i.i" ]
  %text.val3.i.i = load i64, ptr %text.i.i, align 8, !range !247, !noalias !1015, !noundef !43
  %470 = icmp eq i64 %text.val3.i.i, 0
  br i1 %470, label %bb14.i, label %_ZN4sum111read_number17h9f925a3d0a921f93E.exit.i

_ZN4sum111read_number17h9f925a3d0a921f93E.exit.i: ; preds = %bb15.i.i
  %text.val4.i.i = load ptr, ptr %_16.sroa.4.0.text.sroa_idx.i.i, align 8, !noalias !1015, !nonnull !43, !noundef !43
  call void @free(ptr noundef nonnull %text.val4.i.i) #67, !dbg !234
  br label %bb14.i

"_ZN4core3ptr81drop_in_place$LT$std..io..buffered..bufreader..BufReader$LT$std..fs..File$GT$$GT$17h41715630dc6f2039E.exit.i": ; preds = %_ZN4sum111read_number17h9f925a3d0a921f93E.exit.thread18.i, %bb20.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %text.i.i), !noalias !1015
  call void @free(ptr noundef nonnull %445) #67, !dbg !234
  %_5.i.i.i.i.i.i.i = call noundef i32 @close(i32 noundef %444) #67, !noalias !1164
  br label %bb24

bb14.i:                                           ; preds = %_ZN4sum111read_number17h9f925a3d0a921f93E.exit.i, %bb15.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %text.i.i), !noalias !1015
  br i1 %_12.sroa.0.0.i.i, label %bb5.i, label %bb25

bb5.i:                                            ; preds = %bb14.i
  %471 = fadd double %sum.sroa.0.0.i, %469
  br label %bb3.i

bb10:                                             ; preds = %bb21
; call core::panicking::panic
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking5panic(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @alloc_3f3d441048e765db18832d0500eb115d, i64 noundef 51, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_90059340275da8a37e8c29ce14dfa28b) #108
  unreachable

bb9:                                              ; preds = %bb21
  call void @llvm.lifetime.start.p0(ptr nonnull %result.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %name.i)
  store ptr @alloc_02b85f19480a4281b6fcdcd262ee1055, ptr %name.i, align 8
  %472 = getelementptr inbounds nuw i8, ptr %name.i, i64 8
  store i64 4, ptr %472, align 8
  store i64 %count, ptr %count.i, align 8
  store double %_22, ptr %result.i, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %seconds.i)
; call <std::sys::pal::unix::time::Timespec>::now
  %473 = call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #67, !dbg !1167
  %474 = extractvalue { i64, i32 } %473, 0, !dbg !1171
  %475 = extractvalue { i64, i32 } %473, 1, !dbg !1171
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store i64 %474, ptr %2, align 8
  %476 = getelementptr inbounds nuw i8, ptr %2, i64 8
  store i32 %475, ptr %476, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %1), !noalias !1172
  store i64 %start.0, ptr %1, align 8, !noalias !1175
  %477 = getelementptr inbounds nuw i8, ptr %1, i64 8
  store i32 %start.1, ptr %477, align 8, !noalias !1175
  call void @llvm.lifetime.start.p0(ptr nonnull %0), !dbg !1178, !noalias !1188
; call <std::sys::pal::unix::time::Timespec>::sub_timespec
  call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec12sub_timespec(ptr noalias noundef align 8 captures(none) dereferenceable(24) %0, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %2, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %1) #67, !dbg !1192
  %478 = load i64, ptr %0, align 8, !dbg !1193, !range !474, !noalias !1188, !noundef !43
  %479 = trunc nuw i64 %478 to i1, !dbg !1196
  %480 = getelementptr inbounds nuw i8, ptr %0, i64 8, !dbg !1196
  %481 = load i64, ptr %480, align 8, !dbg !1196, !noalias !1188
  %482 = getelementptr inbounds nuw i8, ptr %0, i64 16, !dbg !1196
  %483 = load i32, ptr %482, align 8, !dbg !1196, !range !1197, !noalias !1188
  call void @llvm.lifetime.end.p0(ptr nonnull %0), !dbg !1198, !noalias !1188
  call void @llvm.lifetime.end.p0(ptr nonnull %1), !dbg !1199, !noalias !1172
  call void @llvm.lifetime.end.p0(ptr nonnull %2), !dbg !1200
  %484 = uitofp i64 %481 to double
  %485 = uitofp nneg i32 %483 to double
  %486 = fdiv double %485, 1.000000e+09
  %487 = fadd double %486, %484
  %488 = select i1 %479, double 0.000000e+00, double %487
  store double %488, ptr %seconds.i, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %args.i)
  store ptr %result.i, ptr %args.i, align 8
  %_12.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args.i, i64 8
  store ptr @_RNvXs7_NtNtCsgEmfK2I1SDS_4core3fmt5floatdNtB7_7Display3fmt, ptr %_12.sroa.4.0..sroa_idx.i, align 8
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_1411a66fb3eebd1e386b0f09aa6c2612, ptr noundef nonnull %args.i) #67
  call void @llvm.lifetime.end.p0(ptr nonnull %args.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %args2.i)
  store ptr %name.i, ptr %args2.i, align 8
  %_20.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 8
  store ptr @"_ZN44_$LT$$RF$T$u20$as$u20$core..fmt..Display$GT$3fmt17h4650503e7affaf37E", ptr %_20.sroa.4.0..sroa_idx.i, align 8
  %489 = getelementptr inbounds nuw i8, ptr %args2.i, i64 16
  store ptr %count.i, ptr %489, align 8
  %_21.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 24
  store ptr @_RNvXsd_NtNtNtCsgEmfK2I1SDS_4core3fmt3num3impyNtB9_7Display3fmt, ptr %_21.sroa.4.0..sroa_idx.i, align 8
  %490 = getelementptr inbounds nuw i8, ptr %args2.i, i64 32
  store ptr %seconds.i, ptr %490, align 8
  %_22.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 40
  store ptr @_RNvXs7_NtNtCsgEmfK2I1SDS_4core3fmt5floatdNtB7_7Display3fmt, ptr %_22.sroa.4.0..sroa_idx.i, align 8
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_425ac0839427cedeadf73b1b30f184e4, ptr noundef nonnull %args2.i) #67
  call void @llvm.lifetime.end.p0(ptr nonnull %args2.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %seconds.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %result.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %name.i)
  br label %bb2.i.i

bb2.i.i:                                          ; preds = %bb9, %bb2.i.i
  %_3.sroa.0.04.i.i = phi i64 [ %491, %bb2.i.i ], [ 0, %bb9 ]
  %_6.i.i = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %_3.sroa.6.1, i64 %_3.sroa.0.04.i.i
  %491 = add nuw i64 %_3.sroa.0.04.i.i, 1
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h2e1408dfad6e001fE"(ptr noalias noundef readonly align 8 dereferenceable(32) %_6.i.i) #67, !noalias !1201
  %_7.i.i = icmp eq i64 %491, %_3.sroa.9.1
  br i1 %_7.i.i, label %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i", label %bb2.i.i

"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i": ; preds = %bb2.i.i
  %492 = icmp eq i64 %_3.sroa.0.1, 0
  br i1 %492, label %bb14, label %bb2.i.i.i.i9

bb2.i.i.i.i9:                                     ; preds = %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i"
  call void @free(ptr noundef nonnull %_3.sroa.6.1) #67, !dbg !234
  br label %bb14

bb14:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i17", %bb2.i.i.i.i19, %bb2.i.i.i.i9, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i"
  %_0.sroa.0.0 = phi ptr [ null, %bb2.i.i.i.i9 ], [ null, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i" ], [ %_15.sroa.7.0.ph.in, %bb2.i.i.i.i19 ], [ %_15.sroa.7.0.ph.in, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i17" ], [ %119, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread ], [ %_3.sroa.6.1, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit ]
  ret ptr %_0.sroa.0.0

bb24:                                             ; preds = %bb10.i, %"_ZN4core3ptr81drop_in_place$LT$std..io..buffered..bufreader..BufReader$LT$std..fs..File$GT$$GT$17h41715630dc6f2039E.exit.i"
  %_15.sroa.7.0.ph.in = phi ptr [ %_4.sroa.8.1.ph.i.i, %"_ZN4core3ptr81drop_in_place$LT$std..io..buffered..bufreader..BufReader$LT$std..fs..File$GT$$GT$17h41715630dc6f2039E.exit.i" ], [ %408, %bb10.i ]
  br label %bb2.i.i13

bb2.i.i13:                                        ; preds = %bb24, %bb2.i.i13
  %_3.sroa.0.04.i.i14 = phi i64 [ %493, %bb2.i.i13 ], [ 0, %bb24 ]
  %_6.i.i15 = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %_3.sroa.6.1, i64 %_3.sroa.0.04.i.i14
  %493 = add nuw i64 %_3.sroa.0.04.i.i14, 1
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h2e1408dfad6e001fE"(ptr noalias noundef readonly align 8 dereferenceable(32) %_6.i.i15) #67, !noalias !1206
  %_7.i.i16 = icmp eq i64 %493, %_3.sroa.9.1
  br i1 %_7.i.i16, label %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i17", label %bb2.i.i13

"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i17": ; preds = %bb2.i.i13
  %494 = icmp eq i64 %_3.sroa.0.1, 0
  br i1 %494, label %bb14, label %bb2.i.i.i.i19

bb2.i.i.i.i19:                                    ; preds = %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17h5f9b27beee25e560E.exit.i17"
  call void @free(ptr noundef nonnull %_3.sroa.6.1) #67, !dbg !234
  br label %bb14

bb25:                                             ; preds = %bb14.i
  %sum.sroa.0.0.i.lcssa586 = phi double [ %sum.sroa.0.0.i, %bb14.i ]
  call void @free(ptr noundef nonnull %410) #67, !dbg !234
  %_5.i.i.i.i.i.i8.i = call noundef i32 @close(i32 noundef %409) #67, !noalias !1211
  %_48 = add nuw i64 %iter.sroa.0.069, 1
  store double %sum.sroa.0.0.i.lcssa586, ptr %result, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %result) #67, !srcloc !229
  %exitcond.not = icmp eq i64 %_48, %count
  br i1 %exitcond.not, label %bb21.loopexit, label %bb20
}
