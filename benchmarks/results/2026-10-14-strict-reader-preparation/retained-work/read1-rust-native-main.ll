define internal noundef ptr @_ZN5read14main17h512f48c69a119d1cE() unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %0 = alloca [24 x i8], align 8
  %1 = alloca [16 x i8], align 8
  %2 = alloca [16 x i8], align 8
  %3 = alloca [24 x i8], align 8
  %4 = alloca [24 x i8], align 8
  %5 = alloca [24 x i8], align 8
  %6 = alloca [144 x i8], align 8
  %7 = alloca [176 x i8], align 8
  %8 = alloca [384 x i8], align 1
  %9 = alloca [8 x i8], align 8
  %10 = alloca [16 x i8], align 8
  %11 = alloca [16 x i8], align 4
  %12 = alloca [24 x i8], align 8
  %13 = alloca [32 x i8], align 8
  %14 = alloca [24 x i8], align 8
  %15 = alloca [32 x i8], align 8
  %16 = alloca [24 x i8], align 8
  %17 = alloca [24 x i8], align 8
  %18 = alloca [24 x i8], align 8
  %19 = alloca [24 x i8], align 8
  %args2.i = alloca [48 x i8], align 8
  %args.i = alloca [16 x i8], align 8
  %seconds.i = alloca [8 x i8], align 8
  %result.i11 = alloca [8 x i8], align 8
  %count.i = alloca [8 x i8], align 8
  %name.i = alloca [16 x i8], align 8
  %_11.i = alloca [32 x i8], align 8
  %result.i = alloca [32 x i8], align 8
  %reader.i = alloca [32 x i8], align 8
  %20 = alloca [16 x i8], align 8
  %_16.sroa.9 = alloca [16 x i8], align 8
  %_14 = alloca [32 x i8], align 8
  %result = alloca [32 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %19), !noalias !614
  store i64 0, ptr %19, align 8, !noalias !614
  %21 = getelementptr inbounds nuw i8, ptr %19, i64 8
  store ptr inttoptr (i64 1 to ptr), ptr %21, align 8, !noalias !614
  %22 = getelementptr inbounds nuw i8, ptr %19, i64 16
  store i64 0, ptr %22, align 8, !noalias !614
  %23 = load atomic i32, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 48) acquire, align 8, !dbg !617, !noalias !614
  %24 = icmp eq i32 %23, 0, !dbg !655
  br i1 %24, label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, label %25, !dbg !655, !prof !656

25:                                               ; preds = %start
; call <std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::initialize::<<std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::get_or_init<std::io::stdio::stdin::{closure#0}>::{closure#0}, !>
  tail call fastcc void @_RINvMNtNtCsjrHSEGnQ3l9_3std4sync9once_lockINtB3_8OnceLockINtNtNtB5_6poison5mutex5MutexINtNtNtNtB7_2io8buffered9bufreader9BufReaderNtNtB1t_5stdio8StdinRawEEE10initializeNCINvB2_11get_or_initNCNvB26_5stdin0E0zEB7_() #64, !dbg !657, !noalias !614
  br label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, !dbg !658

_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i: ; preds = %25, %start
  tail call void @llvm.experimental.noalias.scope.decl(metadata !659)
  %26 = cmpxchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0, i32 1 acquire monotonic, align 4, !dbg !662, !noalias !684
  %27 = extractvalue { i32, i1 } %26, 1, !dbg !689
  br i1 %27, label %29, label %28, !dbg !690, !prof !656

28:                                               ; preds = %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
; call <std::sys::sync::mutex::futex::Mutex>::lock_contended
  tail call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys4sync5mutex5futexNtB2_5Mutex14lock_contended(ptr noundef nonnull align 8 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE), !dbg !691, !noalias !684
  br label %29, !dbg !691

29:                                               ; preds = %28, %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
  %30 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !692, !noalias !684
  %31 = and i64 %30, 9223372036854775807, !dbg !717
  %32 = icmp eq i64 %31, 0, !dbg !717
  br i1 %32, label %36, label %33, !dbg !717, !prof !656

33:                                               ; preds = %29
; call std::panicking::panic_count::is_zero_slow_path
  %34 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #103, !dbg !718, !noalias !684
  %35 = xor i1 %34, true, !dbg !719
  br label %36, !dbg !718

36:                                               ; preds = %33, %29
  %37 = phi i1 [ %35, %33 ], [ false, %29 ], !dbg !720
  %38 = load atomic i8, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !721, !noalias !684
  tail call void @llvm.experimental.noalias.scope.decl(metadata !730), !dbg !733
  tail call void @llvm.experimental.noalias.scope.decl(metadata !734), !dbg !737
  %39 = load i64, ptr %22, align 8, !dbg !741, !alias.scope !761, !noalias !762, !noundef !31
  %40 = icmp sgt i64 %39, -1, !dbg !764
  tail call void @llvm.assume(i1 %40), !dbg !766
  %41 = icmp eq i64 %39, 0, !dbg !767
  br i1 %41, label %42, label %67, !dbg !767

42:                                               ; preds = %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !768), !dbg !771
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %43 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef nonnull align 8 dereferenceable(24) %19)
          to label %46 unwind label %44, !dbg !772, !noalias !614

44:                                               ; preds = %42
  %45 = landingpad { ptr, i32 }
          cleanup
  br label %59, !dbg !780

46:                                               ; preds = %42
  %47 = extractvalue { i64, ptr } %43, 0, !dbg !781
  %48 = extractvalue { i64, ptr } %43, 1, !dbg !781
  %49 = load ptr, ptr %21, align 8, !dbg !782, !alias.scope !801, !noalias !802, !nonnull !31, !noundef !31
  %50 = load i64, ptr %22, align 8, !dbg !804, !alias.scope !801, !noalias !802, !noundef !31
  call void @llvm.lifetime.start.p0(ptr nonnull %16), !dbg !805, !noalias !807
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %16, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %49, i64 noundef %50), !dbg !805, !noalias !807
  %51 = load i64, ptr %16, align 8, !dbg !808, !range !816, !noalias !807, !noundef !31
  %52 = icmp eq i64 %51, 0, !dbg !817
  call void @llvm.lifetime.end.p0(ptr nonnull %16), !dbg !818, !noalias !807
  br i1 %52, label %53, label %56, !dbg !805

53:                                               ; preds = %46
  %54 = icmp sgt i64 %50, -1, !dbg !819
  tail call void @llvm.assume(i1 %54), !dbg !823
  %55 = trunc nuw i64 %47 to i1
  br label %62, !dbg !824

56:                                               ; preds = %46
  %57 = trunc nuw i64 %47 to i1, !dbg !825
  %58 = select i1 %57, ptr %48, ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50, !dbg !825
  br label %62, !dbg !825

common.resume:                                    ; preds = %.body.i, %59
  %common.resume.op = phi { ptr, i32 } [ %60, %59 ], [ %468, %.body.i ]
  resume { ptr, i32 } %common.resume.op, !dbg !828

59:                                               ; preds = %75, %71, %44
  %60 = phi { ptr, i32 } [ %45, %44 ], [ %72, %75 ], [ %72, %71 ]
  %61 = zext i1 %37 to i8, !dbg !829
; call core::ptr::drop_in_place::<std::io::stdio::StdinLock>
  tail call fastcc void @_RINvNtCsgEmfK2I1SDS_4core3ptr13drop_in_placeNtNtNtCsjrHSEGnQ3l9_3std2io5stdio9StdinLockEBM_(ptr nonnull @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i8 %61) #104, !dbg !830, !noalias !831
  br label %common.resume, !dbg !832

62:                                               ; preds = %56, %53
  %63 = phi ptr [ %48, %53 ], [ %58, %56 ], !dbg !771
  %64 = phi i1 [ %55, %53 ], [ true, %56 ], !dbg !771
  %65 = phi i64 [ %50, %53 ], [ 0, %56 ], !dbg !833
  store i64 %65, ptr %22, align 8, !dbg !834, !alias.scope !801, !noalias !844
  %66 = ptrtoint ptr %63 to i64, !dbg !771
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !847

67:                                               ; preds = %36
  call void @llvm.lifetime.start.p0(ptr nonnull %18), !dbg !848, !noalias !849
  store i64 0, ptr %18, align 8, !dbg !850, !noalias !849
  %68 = getelementptr inbounds nuw i8, ptr %18, i64 8, !dbg !850
  store ptr inttoptr (i64 1 to ptr), ptr %68, align 8, !dbg !850, !noalias !849
  %69 = getelementptr inbounds nuw i8, ptr %18, i64 16, !dbg !850
  store i64 0, ptr %69, align 8, !dbg !850, !noalias !849
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %70 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef align 8 dereferenceable(24) %18)
          to label %77 unwind label %71, !dbg !853, !noalias !855

71:                                               ; preds = %97, %67
  %72 = landingpad { ptr, i32 }
          cleanup
  %73 = load i64, ptr %18, align 8, !dbg !856, !range !595, !alias.scope !859, !noalias !849, !noundef !31
  %74 = icmp eq i64 %73, 0, !dbg !862
  br i1 %74, label %59, label %75, !dbg !862

75:                                               ; preds = %71
  %76 = load ptr, ptr %68, align 8, !dbg !856, !alias.scope !859, !noalias !849, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %76) #64, !dbg !873, !noalias !888
  br label %59, !dbg !889

77:                                               ; preds = %67
  %78 = extractvalue { i64, ptr } %70, 0, !dbg !890
  %79 = trunc nuw i64 %78 to i1, !dbg !891
  br i1 %79, label %80, label %83, !dbg !891

80:                                               ; preds = %77
  %81 = extractvalue { i64, ptr } %70, 1, !dbg !890
  %82 = ptrtoint ptr %81 to i64, !dbg !890
  br label %114, !dbg !894

83:                                               ; preds = %77
  call void @llvm.lifetime.start.p0(ptr nonnull %17), !dbg !897, !noalias !849
  %84 = load ptr, ptr %68, align 8, !dbg !898, !noalias !849, !nonnull !31, !noundef !31
  %85 = load i64, ptr %69, align 8, !dbg !911, !noalias !849, !noundef !31
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %17, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %84, i64 noundef %85), !dbg !897, !noalias !849
  %86 = load i64, ptr %17, align 8, !dbg !912, !range !816, !noalias !849, !noundef !31
  %87 = trunc nuw i64 %86 to i1, !dbg !915
  br i1 %87, label %88, label %89, !dbg !915

88:                                               ; preds = %83
  call void @llvm.lifetime.end.p0(ptr nonnull %17), !dbg !916, !noalias !849
  br label %114, !dbg !894

89:                                               ; preds = %83
  %90 = getelementptr inbounds nuw i8, ptr %17, i64 8, !dbg !917
  %91 = load ptr, ptr %90, align 8, !dbg !917, !noalias !849, !nonnull !31, !align !70, !noundef !31
  %92 = getelementptr inbounds nuw i8, ptr %17, i64 16, !dbg !917
  %93 = load i64, ptr %92, align 8, !dbg !917, !noalias !849, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %17), !dbg !916, !noalias !849
  tail call void @llvm.experimental.noalias.scope.decl(metadata !918), !dbg !921
  %94 = load i64, ptr %19, align 8, !dbg !936, !range !595, !alias.scope !950, !noalias !762, !noundef !31
  %95 = sub nsw i64 %94, %39, !dbg !953
  %96 = icmp ugt i64 %93, %95, !dbg !959
  br i1 %96, label %97, label %101, !dbg !960, !prof !961

97:                                               ; preds = %89
; invoke <alloc::raw_vec::RawVecInner<_>>::reserve::do_reserve_and_handle::<alloc::alloc::Global>
  invoke fastcc void @_RINvNvMs2_NtCslNYArtu3iFV_5alloc7raw_vecINtB8_11RawVecInnerpE7reserve21do_reserve_and_handleNtNtBa_5alloc6GlobalECsjrHSEGnQ3l9_3std(ptr noalias noundef nonnull align 8 dereferenceable(24) %19, i64 noundef %39, i64 noundef %93, i64 noundef 1, i64 noundef 1)
          to label %98 unwind label %71, !dbg !962, !noalias !762

98:                                               ; preds = %97
  %99 = load i64, ptr %22, align 8, !dbg !963, !alias.scope !966, !noalias !762, !noundef !31
  %100 = icmp sgt i64 %99, -1, !dbg !967
  tail call void @llvm.assume(i1 %100), !dbg !969
  br label %103, !dbg !970

101:                                              ; preds = %89
  %102 = icmp eq i64 %93, 0, !dbg !970
  br i1 %102, label %107, label %103, !dbg !970

103:                                              ; preds = %101, %98
  %104 = phi i64 [ %99, %98 ], [ %39, %101 ]
  %105 = load ptr, ptr %21, align 8, !dbg !972, !alias.scope !966, !noalias !762, !nonnull !31, !noundef !31
  %106 = getelementptr inbounds nuw i8, ptr %105, i64 %104, !dbg !981
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %106, ptr nonnull readonly align 1 %91, i64 %93, i1 false), !dbg !987, !noalias !990
  br label %107, !dbg !991

107:                                              ; preds = %103, %101
  %108 = phi i64 [ %104, %103 ], [ %39, %101 ]
  %109 = add i64 %108, %93, !dbg !992
  store i64 %109, ptr %22, align 8, !dbg !992, !alias.scope !966, !noalias !762
  %110 = load i64, ptr %18, align 8, !dbg !993, !range !595, !alias.scope !995, !noalias !849, !noundef !31
  %111 = icmp eq i64 %110, 0, !dbg !998
  br i1 %111, label %113, label %112, !dbg !998

112:                                              ; preds = %107
  tail call void @free(ptr noundef nonnull %84) #64, !dbg !1003, !noalias !888
  br label %113, !dbg !1010

113:                                              ; preds = %112, %107
  call void @llvm.lifetime.end.p0(ptr nonnull %18), !dbg !1011, !noalias !849
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !847

114:                                              ; preds = %88, %80
  %115 = phi i64 [ %82, %80 ], [ ptrtoint (ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50 to i64), %88 ], !dbg !1012
  %116 = load i64, ptr %18, align 8, !dbg !1016, !range !595, !alias.scope !1018, !noalias !849, !noundef !31
  %117 = icmp eq i64 %116, 0, !dbg !1021
  br i1 %117, label %120, label %118, !dbg !1021

118:                                              ; preds = %114
  %119 = load ptr, ptr %68, align 8, !dbg !1016, !alias.scope !1018, !noalias !849, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %119) #64, !dbg !1026, !noalias !888
  br label %120, !dbg !1033

120:                                              ; preds = %118, %114
  call void @llvm.lifetime.end.p0(ptr nonnull %18), !dbg !1011, !noalias !849
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !1034

_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i: ; preds = %120, %113, %62
  %121 = phi i64 [ %66, %62 ], [ %115, %120 ], [ %93, %113 ], !dbg !1035
  %122 = phi i1 [ %64, %62 ], [ true, %120 ], [ false, %113 ], !dbg !1035
  %123 = inttoptr i64 %121 to ptr, !dbg !1034
  br i1 %37, label %131, label %124, !dbg !1036

124:                                              ; preds = %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %125 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1046, !noalias !831
  %126 = and i64 %125, 9223372036854775807, !dbg !1056
  %127 = icmp eq i64 %126, 0, !dbg !1056
  br i1 %127, label %131, label %128, !dbg !1056, !prof !656

128:                                              ; preds = %124
; call std::panicking::panic_count::is_zero_slow_path
  %129 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #103, !dbg !1057, !noalias !831
  br i1 %129, label %131, label %130, !dbg !1058

130:                                              ; preds = %128
  store atomic i8 1, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !1059, !noalias !831
  br label %131, !dbg !1064

131:                                              ; preds = %130, %128, %124, %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %132 = atomicrmw xchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0 release, align 4, !dbg !1065, !noalias !831
  %133 = icmp eq i32 %132, 2, !dbg !1072
  br i1 %133, label %134, label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !1072, !prof !961

134:                                              ; preds = %131
  %135 = tail call noundef i64 (i64, ...) @syscall(i64 noundef 202, ptr noundef nonnull align 4 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 noundef 129, i32 noundef 1) #64, !dbg !1073, !noalias !831
  br label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !1084

_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i: ; preds = %134, %131
  br i1 %122, label %136, label %139

136:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %137 = load i64, ptr %19, align 8, !range !595, !noalias !614, !noundef !31
  %138 = icmp eq i64 %137, 0
  br i1 %138, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, label %._crit_edge

._crit_edge:                                      ; preds = %136
  %.pre = load ptr, ptr %21, align 8, !noalias !614
  br label %163

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread: ; preds = %136
  call void @llvm.lifetime.end.p0(ptr nonnull %19), !noalias !614
  br label %bb17

139:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %140 = load ptr, ptr %21, align 8, !noalias !614, !nonnull !31, !noundef !31
  %141 = load i64, ptr %22, align 8, !noalias !614, !noundef !31
  call void @llvm.lifetime.start.p0(ptr nonnull %15), !noalias !1085
; call r7rs_wasm_reference::Reader::new
  call fastcc void @_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(32) %15, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %140, i64 noundef %141) #64, !noalias !1089
  call void @llvm.lifetime.start.p0(ptr nonnull %14), !noalias !1085
  store i64 0, ptr %14, align 8, !noalias !1085
  %142 = getelementptr inbounds nuw i8, ptr %14, i64 8
  store ptr inttoptr (i64 8 to ptr), ptr %142, align 8, !noalias !1085
  %143 = getelementptr inbounds nuw i8, ptr %14, i64 16
  store i64 0, ptr %143, align 8, !noalias !1085
  br label %144

144:                                              ; preds = %157, %139
  %_3.sroa.6.0.copyload = phi ptr [ %158, %157 ], [ inttoptr (i64 8 to ptr), %139 ]
  %_3.sroa.9.0.copyload = phi i64 [ %160, %157 ], [ 0, %139 ]
; call r7rs_wasm_reference::Reader::skip_space
  %145 = call fastcc noundef zeroext i1 @_ZN19r7rs_wasm_reference6Reader10skip_space17h8f14cc2594bb2e68E(ptr noalias noundef align 8 dereferenceable(32) %15) #64, !noalias !1089
  br i1 %145, label %152, label %146

146:                                              ; preds = %144
  %_3.sroa.6.0.copyload.lcssa = phi ptr [ %_3.sroa.6.0.copyload, %144 ]
  %_3.sroa.9.0.copyload.lcssa = phi i64 [ %_3.sroa.9.0.copyload, %144 ]
  %_3.sroa.0.0.copyload = load i64, ptr %14, align 8, !noalias !1090
  call void @llvm.lifetime.end.p0(ptr nonnull %14), !noalias !1085
  %147 = load i64, ptr %15, align 8, !range !595, !noalias !1085, !noundef !31
  %148 = icmp eq i64 %147, 0
  br i1 %148, label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, label %149

149:                                              ; preds = %146
  %150 = getelementptr inbounds nuw i8, ptr %15, i64 8
  %151 = load ptr, ptr %150, align 8, !noalias !1085, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %151) #64, !dbg !581, !noalias !1089
  br label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i

152:                                              ; preds = %144
  call void @llvm.lifetime.start.p0(ptr nonnull %13), !noalias !1085
; call r7rs_wasm_reference::Reader::datum
  call fastcc void @_ZN19r7rs_wasm_reference6Reader5datum17h7ae745f2407c5577E(ptr noalias noundef align 8 captures(address) dereferenceable(32) %13, ptr noalias noundef align 8 dereferenceable(32) %15) #64, !noalias !1089
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1091)
  %153 = load i64, ptr %14, align 8, !range !595, !alias.scope !1091, !noalias !1094, !noundef !31
  %154 = icmp eq i64 %_3.sroa.9.0.copyload, %153
  br i1 %154, label %155, label %157

155:                                              ; preds = %152
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h93d0dd34c8f30447E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %14) #105, !noalias !1096
  %156 = load ptr, ptr %142, align 8, !alias.scope !1091, !noalias !1094
  br label %157

157:                                              ; preds = %155, %152
  %158 = phi ptr [ %_3.sroa.6.0.copyload, %152 ], [ %156, %155 ]
  %159 = getelementptr inbounds nuw { i64, [3 x i64] }, ptr %158, i64 %_3.sroa.9.0.copyload
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %159, ptr noundef nonnull readonly align 8 dereferenceable(32) %13, i64 32, i1 false), !noalias !1097
  %160 = add i64 %_3.sroa.9.0.copyload, 1
  store i64 %160, ptr %143, align 8, !alias.scope !1091, !noalias !1094
  call void @llvm.lifetime.end.p0(ptr nonnull %13), !noalias !1085
  br label %144

_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i: ; preds = %149, %146
  call void @llvm.lifetime.end.p0(ptr nonnull %15), !noalias !1085
  %161 = load i64, ptr %19, align 8, !range !595, !noalias !614, !noundef !31
  %162 = icmp eq i64 %161, 0
  br i1 %162, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, label %163

163:                                              ; preds = %._crit_edge, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i
  %164 = phi ptr [ %.pre, %._crit_edge ], [ %140, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.9.0 = phi i64 [ undef, %._crit_edge ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.0 = phi ptr [ %123, %._crit_edge ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.0 = phi i64 [ -9223372036854775808, %._crit_edge ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  tail call void @free(ptr noundef nonnull %164) #64, !dbg !581, !noalias !614
  br label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit: ; preds = %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, %163
  %_3.sroa.9.1 = phi i64 [ %_3.sroa.9.0, %163 ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.1 = phi ptr [ %_3.sroa.6.0, %163 ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.1 = phi i64 [ %_3.sroa.0.0, %163 ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %19), !noalias !614
  %165 = icmp eq i64 %_3.sroa.0.1, -9223372036854775808
  br i1 %165, label %bb17, label %bb19

bb19:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit
  %_34.not = icmp eq i64 %_3.sroa.9.1, 0
  br i1 %_34.not, label %panic, label %bb20

bb20:                                             ; preds = %bb19
  %166 = icmp ne ptr %_3.sroa.6.1, null
  tail call void @llvm.assume(i1 %166)
; call r7rs_wasm_reference::Datum::number
  %count = tail call fastcc noundef i64 @_ZN19r7rs_wasm_reference5Datum6number17h11d92c433e08e7b1E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %_3.sroa.6.1) #64
  %_42.not = icmp eq i64 %_3.sroa.9.1, 1
  br i1 %_42.not, label %panic2, label %bb21

panic:                                            ; preds = %bb19
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 0, i64 noundef 0, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_845863b49363c8d214794d4926557505) #102
  unreachable

bb21:                                             ; preds = %bb20
  %_9 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 32
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1098)
  %167 = load i64, ptr %_9, align 8, !range !580, !alias.scope !1098, !noundef !31
  %168 = icmp ne i64 %167, -9223372036854775805
  tail call void @llvm.assume(i1 %168)
  %169 = icmp slt i64 %167, -9223372036854775806
  br i1 %169, label %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit, label %170, !prof !1101

170:                                              ; preds = %bb21
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.21, ptr noundef nonnull inttoptr (i64 53 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.23) #102, !noalias !1098
  unreachable

_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit: ; preds = %bb21
  %171 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 48
  %172 = load ptr, ptr %171, align 8, !alias.scope !1098, !nonnull !31, !noundef !31
  %173 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 56
  %174 = load i64, ptr %173, align 8, !alias.scope !1098, !noundef !31
; call <std::sys::pal::unix::time::Timespec>::now
  %175 = tail call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #64, !dbg !1102
  %start.0 = extractvalue { i64, i32 } %175, 0
  %start.1 = extractvalue { i64, i32 } %175, 1
  %176 = tail call noundef dereferenceable_or_null(2) ptr @malloc(i64 noundef 2) #64, !dbg !1113, !noalias !1118
  %177 = icmp eq ptr %176, null
  br i1 %177, label %bb25, label %bb26, !prof !961

panic2:                                           ; preds = %bb20
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 1, i64 noundef 1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_288c5cfe5ce029c76ef56f391afd341d) #102
  unreachable

bb25:                                             ; preds = %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 2) #106
  unreachable

bb26:                                             ; preds = %_ZN19r7rs_wasm_reference5Datum4atom17h0f3b7fb7e7332b1bE.exit
  store i16 26147, ptr %176, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %result)
  store i64 -9223372036854775808, ptr %result, align 8
  %_12.sroa.2.0.result.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 8
  store i64 2, ptr %_12.sroa.2.0.result.sroa_idx, align 8
  %_12.sroa.2.sroa.2.0._12.sroa.2.0.result.sroa_idx.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 16
  store ptr %176, ptr %_12.sroa.2.sroa.2.0._12.sroa.2.0.result.sroa_idx.sroa_idx, align 8
  %_12.sroa.2.sroa.3.0._12.sroa.2.0.result.sroa_idx.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 24
  store i64 2, ptr %_12.sroa.2.sroa.3.0._12.sroa.2.0.result.sroa_idx.sroa_idx, align 8
  %_6234.not = icmp eq i64 %count, 0
  br i1 %_6234.not, label %bb28, label %bb27.lr.ph

bb27.lr.ph:                                       ; preds = %bb26
  %178 = getelementptr inbounds nuw i8, ptr %20, i64 8
  %179 = getelementptr inbounds nuw i8, ptr %result.i, i64 8
  %_10.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %result.i, i64 16
  %_10.sroa.5.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %result.i, i64 24
  %180 = getelementptr inbounds nuw i8, ptr %reader.i, i64 8
  %val1.sroa.2.0._14.sroa_idx = getelementptr inbounds nuw i8, ptr %_14, i64 8
  %val1.sroa.3.0._14.sroa_idx = getelementptr inbounds nuw i8, ptr %_14, i64 16
  %181 = getelementptr inbounds nuw i8, ptr %11, i64 4
  %182 = getelementptr inbounds nuw i8, ptr %11, i64 8
  %183 = ptrtoint ptr %8 to i64
  %184 = add i64 %183, 7
  %185 = and i64 %184, -8
  %186 = sub i64 %185, %183
  %187 = icmp ult i64 %186, 8
  %188 = icmp eq i64 %185, %183
  %189 = getelementptr inbounds nuw i8, ptr %10, i64 8
  %190 = getelementptr inbounds nuw i8, ptr %10, i64 4
  %191 = getelementptr inbounds nuw i8, ptr %7, i64 8
  %192 = getelementptr inbounds nuw i8, ptr %7, i64 80
  %193 = getelementptr inbounds nuw i8, ptr %6, i64 48
  %194 = getelementptr inbounds nuw i8, ptr %12, i64 8
  %195 = getelementptr inbounds nuw i8, ptr %12, i64 16
  %196 = getelementptr inbounds nuw i8, ptr %4, i64 8
  %197 = getelementptr inbounds nuw i8, ptr %3, i64 8
  br label %bb27

bb28:                                             ; preds = %bb32, %bb26
  %_69 = icmp ugt i64 %_3.sroa.9.1, 2
  br i1 %_69, label %bb30, label %panic3

bb27:                                             ; preds = %bb27.lr.ph, %bb32
  %iter.sroa.0.035 = phi i64 [ 0, %bb27.lr.ph ], [ %_63, %bb32 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_14)
  call void @llvm.lifetime.start.p0(ptr nonnull %_16.sroa.9)
  call void @llvm.lifetime.start.p0(ptr nonnull %20)
  store ptr %172, ptr %20, align 8
  store i64 %174, ptr %178, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %20) #64, !srcloc !30
  %_17.0 = load ptr, ptr %20, align 8, !nonnull !31, !align !70, !noundef !31
  %_17.1 = load i64, ptr %178, align 8, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %20)
  call void @llvm.lifetime.start.p0(ptr nonnull %_11.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %result.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %11), !dbg !1121, !noalias !1129
  store i32 0, ptr %11, align 4, !dbg !1138, !noalias !1129
  store i32 438, ptr %181, align 4, !dbg !1138, !noalias !1129
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 4 dereferenceable(6) %182, i8 0, i64 6, i1 false), !dbg !1138, !noalias !1129
  store i8 1, ptr %182, align 4, !dbg !1142, !noalias !1129
  call void @llvm.lifetime.start.p0(ptr nonnull %10), !dbg !1151, !noalias !1156
  call void @llvm.experimental.noalias.scope.decl(metadata !1165), !dbg !1151, !noalias !1168
  call void @llvm.lifetime.start.p0(ptr nonnull %9), !dbg !1169, !noalias !1173
  store ptr %11, ptr %9, align 8, !dbg !1169, !noalias !1173
  %198 = icmp ugt i64 %_17.1, 383, !dbg !1176
  br i1 %198, label %259, label %199, !dbg !1176, !prof !961

199:                                              ; preds = %bb27
  call void @llvm.experimental.noalias.scope.decl(metadata !1184), !dbg !1187, !noalias !1168
  call void @llvm.lifetime.start.p0(ptr nonnull %8), !dbg !1188, !noalias !1191
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %8, ptr nonnull readonly align 1 %_17.0, i64 range(i64 0, 384) %_17.1, i1 false), !dbg !1193, !noalias !1198
  %200 = getelementptr inbounds nuw i8, ptr %8, i64 %_17.1, !dbg !1199
  store i8 0, ptr %200, align 1, !dbg !1202, !noalias !1191
  %201 = add nuw nsw i64 %_17.1, 1, !dbg !1207
  %202 = icmp ult i64 %_17.1, 15, !dbg !1208
  br i1 %202, label %.preheader192, label %203, !dbg !1208

203:                                              ; preds = %199
  call void @llvm.assume(i1 %187), !dbg !1219, !noalias !1242
  br i1 %188, label %204, label %.preheader102, !dbg !1243

204:                                              ; preds = %203
  %205 = add nsw i64 %_17.1, -15
  br label %209, !dbg !1245

206:                                              ; preds = %245
  %207 = add nsw i64 %_17.1, -15
  %208 = icmp ugt i64 %186, %207, !dbg !1245
  br i1 %208, label %.loopexit101, label %209, !dbg !1245

209:                                              ; preds = %206, %204
  %210 = phi i64 [ %205, %204 ], [ %207, %206 ]
  %211 = phi i64 [ 0, %204 ], [ %186, %206 ]
  br label %212, !dbg !1247

212:                                              ; preds = %229, %209
  %213 = phi i64 [ %230, %229 ], [ %211, %209 ]
  %214 = getelementptr inbounds nuw i8, ptr %8, i64 %213, !dbg !1252
  %215 = load i64, ptr %214, align 8, !dbg !1255, !alias.scope !1256, !noalias !1265, !noundef !31
  %216 = getelementptr i8, ptr %214, i64 8, !dbg !1267
  %217 = load i64, ptr %216, align 8, !dbg !1269, !alias.scope !1256, !noalias !1265, !noundef !31
  %218 = sub i64 72340172838076672, %215, !dbg !1270
  %219 = or i64 %218, %215, !dbg !1270
  %220 = sub i64 72340172838076672, %217, !dbg !1273
  %221 = or i64 %220, %217, !dbg !1273
  %222 = and i64 %219, -9187201950435737472, !dbg !1247
  %223 = and i64 %222, %221, !dbg !1247
  %224 = icmp eq i64 %223, -9187201950435737472, !dbg !1247
  br i1 %224, label %229, label %.loopexit101, !dbg !1247

.loopexit101:                                     ; preds = %229, %212, %206
  %225 = phi i64 [ %186, %206 ], [ %230, %229 ], [ %213, %212 ], !dbg !1275
  %226 = getelementptr inbounds nuw i8, ptr %8, i64 %225, !dbg !1276
  %227 = sub i64 %201, %225, !dbg !1278
  %228 = icmp eq i64 %201, %225, !dbg !1279
  br i1 %228, label %.loopexit99, label %.preheader, !dbg !1279

229:                                              ; preds = %212
  %230 = add i64 %213, 16, !dbg !1285
  %231 = icmp ugt i64 %230, %210, !dbg !1245
  br i1 %231, label %.loopexit101, label %212, !dbg !1245

.preheader:                                       ; preds = %.loopexit101, %236
  %232 = phi i64 [ %237, %236 ], [ 0, %.loopexit101 ]
  %233 = getelementptr inbounds nuw i8, ptr %226, i64 %232, !dbg !1286
  %234 = load i8, ptr %233, align 1, !dbg !1286, !alias.scope !1256, !noalias !1265, !noundef !31
  %235 = icmp eq i8 %234, 0, !dbg !1286
  br i1 %235, label %239, label %236, !dbg !1286

236:                                              ; preds = %.preheader
  %237 = add nuw i64 %232, 1, !dbg !1287
  %238 = icmp eq i64 %237, %227, !dbg !1279
  br i1 %238, label %.loopexit99, label %.preheader, !dbg !1279

239:                                              ; preds = %.preheader
  %.lcssa197 = phi i64 [ %232, %.preheader ]
  %240 = add i64 %.lcssa197, %225, !dbg !1288
  br label %.loopexit98, !dbg !1289

.preheader102:                                    ; preds = %203, %245
  %241 = phi i64 [ %246, %245 ], [ 0, %203 ]
  %242 = getelementptr inbounds nuw i8, ptr %8, i64 %241, !dbg !1290
  %243 = load i8, ptr %242, align 1, !dbg !1290, !alias.scope !1256, !noalias !1265, !noundef !31
  %244 = icmp eq i8 %243, 0, !dbg !1290
  br i1 %244, label %.loopexit98, label %245, !dbg !1290

245:                                              ; preds = %.preheader102
  %246 = add nuw nsw i64 %241, 1, !dbg !1295
  %247 = icmp eq i64 %246, %186, !dbg !1296
  br i1 %247, label %206, label %.preheader102, !dbg !1296

.preheader192:                                    ; preds = %199, %252
  %248 = phi i64 [ %253, %252 ], [ 0, %199 ]
  %249 = getelementptr inbounds nuw i8, ptr %8, i64 %248, !dbg !1297
  %250 = load i8, ptr %249, align 1, !dbg !1297, !alias.scope !1301, !noalias !1265, !noundef !31
  %251 = icmp eq i8 %250, 0, !dbg !1297
  br i1 %251, label %.loopexit98, label %252, !dbg !1297

252:                                              ; preds = %.preheader192
  %253 = add nuw nsw i64 %248, 1, !dbg !1302
  %254 = icmp eq i64 %248, %_17.1, !dbg !1303
  br i1 %254, label %.loopexit99, label %.preheader192, !dbg !1303

.loopexit98:                                      ; preds = %.preheader102, %.preheader192, %239
  %255 = phi i64 [ %240, %239 ], [ %248, %.preheader192 ], [ %241, %.preheader102 ]
  %256 = icmp eq i64 %255, %_17.1, !dbg !1304
  br i1 %256, label %257, label %.loopexit99, !dbg !1304

.loopexit99:                                      ; preds = %236, %252, %.loopexit98, %.loopexit101
  store ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.73, ptr %189, align 8, !dbg !1306, !alias.scope !1307, !noalias !1308
  store i32 1, ptr %10, align 8, !dbg !1306, !alias.scope !1307, !noalias !1308
  br label %258, !dbg !1309

257:                                              ; preds = %.loopexit98
; call <std::sys::fs::unix::File>::open_c
  call fastcc void @_RNvMsi_NtNtNtCsjrHSEGnQ3l9_3std3sys2fs4unixNtB5_4File6open_c(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(16) %10, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %8, ptr noalias noundef nonnull readonly align 4 captures(address, read_provenance) dereferenceable(16) %11) #64, !dbg !1310, !noalias !1316
  br label %258, !dbg !1317

258:                                              ; preds = %257, %.loopexit99
  call void @llvm.lifetime.end.p0(ptr nonnull %8), !dbg !1318, !noalias !1191
  br label %260, !dbg !1187

259:                                              ; preds = %bb27
; call std::sys::helpers::small_c_string::run_with_cstr_allocating::<std::sys::fs::unix::File>
  call fastcc void @_RINvNtNtNtCsjrHSEGnQ3l9_3std3sys7helpers14small_c_string24run_with_cstr_allocatingNtNtNtB6_2fs4unix4FileEB8_(ptr noalias noundef nonnull align 8 captures(address) dereferenceable(16) %10, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %_17.0, i64 noundef %_17.1, ptr noundef nonnull align 1 %9) #105, !dbg !1319, !noalias !1316
  br label %260, !dbg !1319

260:                                              ; preds = %259, %258
  call void @llvm.lifetime.end.p0(ptr nonnull %9), !dbg !1320, !noalias !1173
  %261 = load i32, ptr %10, align 8, !dbg !1321, !range !1324, !noalias !1156, !noundef !31
  %262 = trunc nuw i32 %261 to i1, !dbg !1325
  br i1 %262, label %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread, label %264, !dbg !1325

_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread: ; preds = %260
  %263 = load ptr, ptr %189, align 8, !dbg !1326, !noalias !1156, !nonnull !31, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %10), !dbg !1327, !noalias !1156
  call void @llvm.lifetime.end.p0(ptr nonnull %11), !dbg !1328, !noalias !1129
  br label %_ZN5read19read_file17h6af6fcbddb469649E.exit.thread

264:                                              ; preds = %260
  %265 = load i32, ptr %190, align 4, !dbg !1329, !range !1330, !noalias !1156, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %10), !dbg !1327, !noalias !1156
  call void @llvm.lifetime.end.p0(ptr nonnull %11), !dbg !1328, !noalias !1129
  call void @llvm.lifetime.start.p0(ptr nonnull %7), !dbg !1331, !noalias !1339
; invoke std::sys::fs::unix::try_statx
  invoke fastcc void @_RNvNtNtNtCsjrHSEGnQ3l9_3std3sys2fs4unix9try_statx(ptr noalias noundef align 8 captures(none) dereferenceable(176) %7, i32 noundef %265, ptr noundef nonnull @anon.eb89d4395b0ead844ef0b45b8b54da85.127, i32 noundef 4096)
          to label %266 unwind label %285, !dbg !1345, !noalias !1316

266:                                              ; preds = %264
  %267 = load i64, ptr %7, align 8, !dbg !1331, !range !1346, !noalias !1339, !noundef !31
  %268 = icmp eq i64 %267, 3, !dbg !1331
  br i1 %268, label %269, label %281, !dbg !1347

269:                                              ; preds = %266
  call void @llvm.lifetime.end.p0(ptr nonnull %7), !dbg !1348, !noalias !1339
  call void @llvm.lifetime.start.p0(ptr nonnull %6), !dbg !1349, !noalias !1339
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(144) %6, i8 0, i64 144, i1 false), !dbg !1350, !noalias !1339
  %270 = call noundef i32 @fstat64(i32 noundef %265, ptr noundef nonnull %6) #64, !dbg !1361, !noalias !1363
  %271 = icmp eq i32 %270, -1, !dbg !1364
  br i1 %271, label %272, label %279, !dbg !1371

272:                                              ; preds = %269
  %273 = tail call noundef ptr @__errno_location() #64, !dbg !1372
  %274 = load i32, ptr %273, align 4, !dbg !1384, !noalias !1385, !noundef !31
  %275 = sext i32 %274 to i64, !dbg !1388
  %276 = shl nsw i64 %275, 32, !dbg !1396
  %277 = or disjoint i64 %276, 2, !dbg !1396
  %278 = inttoptr i64 %277 to ptr, !dbg !1397
  call void @llvm.lifetime.end.p0(ptr nonnull %6), !dbg !1404, !noalias !1339
  br label %287, !dbg !1405

279:                                              ; preds = %269
  %280 = load i64, ptr %193, align 8, !dbg !1408, !noalias !1413
  call void @llvm.lifetime.end.p0(ptr nonnull %6), !dbg !1404, !noalias !1339
  br label %318, !dbg !1405

281:                                              ; preds = %266
  %282 = load ptr, ptr %191, align 8, !dbg !1414, !noalias !1413
  %283 = load i64, ptr %192, align 8, !dbg !1414, !noalias !1413
  call void @llvm.lifetime.end.p0(ptr nonnull %7), !dbg !1348, !noalias !1339
  %284 = icmp eq i64 %267, 2, !dbg !1417
  br i1 %284, label %287, label %318, !dbg !1405

285:                                              ; preds = %264
  %.lcssa228 = phi i32 [ %265, %264 ], !dbg !1329
  %286 = landingpad { ptr, i32 }
          cleanup
  br label %.body.i

287:                                              ; preds = %281, %272
  %288 = phi ptr [ %278, %272 ], [ %282, %281 ]
  %289 = icmp ne ptr %288, null
  call void @llvm.assume(i1 %289), !noalias !1168
  %290 = ptrtoint ptr %288 to i64, !dbg !1418
  %291 = and i64 %290, 3, !dbg !1434
  switch i64 %291, label %default.unreachable [
    i64 2, label %.thread
    i64 3, label %292
    i64 0, label %.thread
    i64 1, label %294
  ], !dbg !1436, !prof !1437

default.unreachable:                              ; preds = %287
  unreachable

292:                                              ; preds = %287
  %293 = icmp ult ptr %288, inttoptr (i64 180388626432 to ptr), !dbg !1438
  call void @llvm.assume(i1 %293), !dbg !1442, !noalias !1168
  br label %.thread, !dbg !1443

294:                                              ; preds = %287
  %295 = getelementptr i8, ptr %288, i64 -1, !dbg !1444
  %296 = icmp ne ptr %295, null
  call void @llvm.assume(i1 %296), !noalias !1168
  %297 = load ptr, ptr %295, align 8, !dbg !1451, !noalias !1456
  %298 = getelementptr i8, ptr %288, i64 7, !dbg !1451
  %299 = load ptr, ptr %298, align 8, !dbg !1451, !noalias !1456, !nonnull !31, !align !32, !noundef !31
  %300 = load ptr, ptr %299, align 8, !dbg !1459, !invariant.load !31, !noalias !1456
  %301 = icmp eq ptr %300, null, !dbg !1459
  br i1 %301, label %304, label %302, !dbg !1459

302:                                              ; preds = %294
  %303 = icmp ne ptr %297, null
  call void @llvm.assume(i1 %303), !noalias !1168
  invoke void %300(ptr noundef nonnull %297)
          to label %304 unwind label %310, !dbg !1459, !noalias !1456

304:                                              ; preds = %302, %294
  %305 = getelementptr inbounds nuw i8, ptr %299, i64 8, !dbg !1464
  %306 = load i64, ptr %305, align 8, !dbg !1464, !range !595, !invariant.load !31, !noalias !1456
  %307 = icmp eq i64 %306, 0, !dbg !1479
  br i1 %307, label %317, label %308, !dbg !1479

308:                                              ; preds = %304
  %309 = icmp ne ptr %297, null
  call void @llvm.assume(i1 %309), !noalias !1168
  call void @free(ptr noundef nonnull %297) #64, !dbg !1481, !noalias !1456
  br label %317, !dbg !1488

310:                                              ; preds = %302
  %.lcssa230 = phi i32 [ %265, %302 ], !dbg !1329
  %.lcssa227 = phi ptr [ %295, %302 ], !dbg !1444
  %.lcssa226 = phi ptr [ %297, %302 ], !dbg !1451
  %.lcssa225 = phi ptr [ %299, %302 ], !dbg !1451
  %311 = landingpad { ptr, i32 }
          cleanup
  %312 = getelementptr inbounds nuw i8, ptr %.lcssa225, i64 8, !dbg !1489
  %313 = load i64, ptr %312, align 8, !dbg !1489, !range !595, !invariant.load !31, !noalias !1456
  %314 = icmp eq i64 %313, 0, !dbg !1493
  br i1 %314, label %316, label %315, !dbg !1493

315:                                              ; preds = %310
  call void @free(ptr noundef nonnull %.lcssa226) #64, !dbg !1494, !noalias !1456
  br label %316, !dbg !1501

316:                                              ; preds = %315, %310
  call void @free(ptr noundef nonnull %.lcssa227) #64, !dbg !1502, !noalias !1456
  br label %.body.i, !dbg !1451

317:                                              ; preds = %308, %304
  call void @free(ptr noundef nonnull %295) #64, !dbg !1513, !noalias !1456
  br label %.thread, !dbg !1521

318:                                              ; preds = %281, %279
  %319 = phi i64 [ %283, %281 ], [ %280, %279 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %12), !dbg !1522, !noalias !1524
  store i64 0, ptr %12, align 8, !dbg !1525, !noalias !1524
  store ptr inttoptr (i64 1 to ptr), ptr %194, align 8, !dbg !1525, !noalias !1524
  store i64 0, ptr %195, align 8, !dbg !1525, !noalias !1524
  call void @llvm.experimental.noalias.scope.decl(metadata !1528), !dbg !1531, !noalias !1168
  call void @llvm.experimental.noalias.scope.decl(metadata !1533), !dbg !1536, !noalias !1168
  %.not = icmp eq i64 %319, 0, !dbg !1543
  br i1 %.not, label %328, label %320, !dbg !1548

320:                                              ; preds = %318
  call void @llvm.experimental.noalias.scope.decl(metadata !1549), !dbg !1552, !noalias !1168
  call void @llvm.lifetime.start.p0(ptr nonnull %4), !dbg !1553, !noalias !1557
; call <alloc::raw_vec::RawVecInner>::finish_grow
  call fastcc void @_RNvMs4_NtCslNYArtu3iFV_5alloc7raw_vecNtB5_11RawVecInner11finish_growB7_(ptr noalias noundef align 8 captures(none) dereferenceable(24) %4, i64 0, ptr nonnull inttoptr (i64 1 to ptr), i64 noundef %319), !dbg !1558, !noalias !1559
  %321 = load i64, ptr %4, align 8, !dbg !1560, !range !816, !noalias !1557, !noundef !31
  %322 = trunc nuw i64 %321 to i1, !dbg !1563
  br i1 %322, label %.thread243, label %323, !dbg !1563

323:                                              ; preds = %320
  %324 = load ptr, ptr %196, align 8, !dbg !1564, !noalias !1557, !nonnull !31, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %4), !dbg !1565, !noalias !1557
  store ptr %324, ptr %194, align 8, !dbg !1566, !alias.scope !1570, !noalias !1524
  %325 = icmp sgt i64 %319, -1, !dbg !1571
  call void @llvm.assume(i1 %325), !dbg !1571, !noalias !1168
  store i64 %319, ptr %12, align 8, !dbg !1577, !alias.scope !1570, !noalias !1524
  br label %328, !dbg !1578

.thread243:                                       ; preds = %320
  call void @llvm.lifetime.end.p0(ptr nonnull %4), !dbg !1565, !noalias !1557
  br label %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244, !dbg !1581

326:                                              ; preds = %454
  %327 = load ptr, ptr %194, align 8, !dbg !1589, !alias.scope !1592, !noalias !1524, !nonnull !31, !noundef !31
  call void @free(ptr noundef nonnull %327) #64, !dbg !1597, !noalias !1316
  br label %.body.i, !dbg !1607

.thread:                                          ; preds = %287, %287, %292, %317
  call void @llvm.lifetime.start.p0(ptr nonnull %12), !dbg !1522, !noalias !1524
  store i64 0, ptr %12, align 8, !dbg !1525, !noalias !1524
  store ptr inttoptr (i64 1 to ptr), ptr %194, align 8, !dbg !1525, !noalias !1524
  store i64 0, ptr %195, align 8, !dbg !1525, !noalias !1524
  call void @llvm.experimental.noalias.scope.decl(metadata !1608), !dbg !1611, !noalias !1168
  call void @llvm.experimental.noalias.scope.decl(metadata !1614), !dbg !1617, !noalias !1168
  br label %350, !dbg !1624

328:                                              ; preds = %323, %318
  %329 = phi i64 [ %319, %323 ], [ 0, %318 ], !dbg !1631
  %330 = add nuw i64 %319, 1024, !dbg !1638
  %331 = and i64 %330, 8191, !dbg !1647
  %332 = icmp eq i64 %331, 0, !dbg !1652
  %333 = sub i64 %319, %331, !dbg !1652
  %334 = add i64 %333, 9216, !dbg !1652
  %335 = icmp ult i64 %334, %330, !dbg !1652
  %336 = select i1 %335, i64 8192, i64 %334, !dbg !1653
  %337 = select i1 %332, i64 %330, i64 %336, !dbg !1653
  %338 = icmp eq i64 %319, 0
  br i1 %338, label %339, label %344, !dbg !1656

339:                                              ; preds = %328
  %340 = phi i64 [ %329, %328 ]
  %341 = phi i1 [ false, %328 ]
  %342 = phi i64 [ %337, %328 ], !dbg !1660
  %343 = icmp ult i64 %340, 32, !dbg !1624
  br i1 %343, label %350, label %344, !dbg !1624

344:                                              ; preds = %360, %339, %328
  %345 = phi i64 [ %353, %360 ], [ %340, %339 ], [ %329, %328 ]
  %346 = phi i64 [ %362, %360 ], [ %340, %339 ], [ %329, %328 ], !dbg !1661
  %347 = phi i64 [ %361, %360 ], [ 0, %339 ], [ 0, %328 ], !dbg !1668
  %348 = phi i1 [ %352, %360 ], [ %341, %339 ], [ false, %328 ], !dbg !1671
  %349 = phi i64 [ %351, %360 ], [ %342, %339 ], [ %337, %328 ], !dbg !1674
  br label %.outer, !dbg !1675

350:                                              ; preds = %.thread, %339
  %351 = phi i64 [ 8192, %.thread ], [ %342, %339 ]
  %352 = phi i1 [ true, %.thread ], [ %341, %339 ]
  %353 = phi i64 [ 0, %.thread ], [ %340, %339 ]
; invoke std::io::default_read_to_end::small_probe_read::<std::fs::File>
  %354 = invoke fastcc { i64, ptr } @_RINvNvNtCsjrHSEGnQ3l9_3std2io19default_read_to_end16small_probe_readNtNtB6_2fs4FileEB6_(i32 range(i32 0, -1) %265, ptr noalias noundef nonnull align 8 dereferenceable(24) %12)
          to label %.noexc.i unwind label %.loopexit.split-lp, !dbg !1676, !noalias !1316

.noexc.i:                                         ; preds = %350
  %355 = extractvalue { i64, ptr } %354, 0, !dbg !1676
  %356 = extractvalue { i64, ptr } %354, 1, !dbg !1676
  %357 = trunc nuw i64 %355 to i1, !dbg !1677
  br i1 %357, label %_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i, label %358, !dbg !1677

358:                                              ; preds = %.noexc.i
  %359 = icmp eq ptr %356, null, !dbg !1680
  br i1 %359, label %_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i, label %360, !dbg !1680

360:                                              ; preds = %358
  %361 = load i64, ptr %195, align 8, !dbg !1668, !alias.scope !1614, !noalias !1524
  %362 = load i64, ptr %12, align 8, !dbg !1661, !range !595, !alias.scope !1614, !noalias !1524
  br label %344, !dbg !1680

363:                                              ; preds = %.outer, %428
  %364 = phi i64 [ %404, %428 ], [ %.ph, %.outer ], !dbg !1661
  %365 = phi i64 [ %424, %428 ], [ %.ph188, %.outer ], !dbg !1668
  %366 = phi i32 [ %431, %428 ], [ %.ph189, %.outer ], !dbg !1682
  %367 = phi i64 [ %423, %428 ], [ %.ph190, %.outer ], !dbg !1683
  %368 = icmp eq i64 %365, %364, !dbg !1684
  %369 = icmp eq i64 %364, %345
  %370 = and i1 %368, %369, !dbg !1684
  br i1 %370, label %379, label %371, !dbg !1684

371:                                              ; preds = %389, %363
  %372 = phi i64 [ %390, %389 ], [ %364, %363 ], !dbg !1685
  %373 = phi i64 [ %388, %389 ], [ %365, %363 ], !dbg !1691
  %374 = icmp sgt i64 %373, -1, !dbg !1693
  call void @llvm.assume(i1 %374), !dbg !1695, !noalias !1168
  %375 = icmp eq i64 %373, %372, !dbg !1696
  %376 = load ptr, ptr %194, align 8, !dbg !1697, !alias.scope !1614, !noalias !1524
  br i1 %375, label %393, label %377, !dbg !1696

377:                                              ; preds = %371
  %378 = load i64, ptr %12, align 8, !dbg !1708, !range !595, !alias.scope !1614, !noalias !1524
  br label %403, !dbg !1696

379:                                              ; preds = %363
; invoke std::io::default_read_to_end::small_probe_read::<std::fs::File>
  %380 = invoke fastcc { i64, ptr } @_RINvNvNtCsjrHSEGnQ3l9_3std2io19default_read_to_end16small_probe_readNtNtB6_2fs4FileEB6_(i32 range(i32 0, -1) %265, ptr noalias noundef nonnull align 8 dereferenceable(24) %12)
          to label %.noexc4.i unwind label %.loopexit, !dbg !1712, !noalias !1316

.noexc4.i:                                        ; preds = %379
  %381 = extractvalue { i64, ptr } %380, 0, !dbg !1712
  %382 = extractvalue { i64, ptr } %380, 1, !dbg !1712
  %383 = trunc nuw i64 %381 to i1, !dbg !1713
  br i1 %383, label %384, label %386, !dbg !1713

384:                                              ; preds = %.noexc4.i
  %.lcssa205 = phi ptr [ %382, %.noexc4.i ], !dbg !1712
  %385 = ptrtoint ptr %.lcssa205 to i64, !dbg !1712
  br label %444, !dbg !1715

386:                                              ; preds = %.noexc4.i
  %387 = icmp eq ptr %382, null, !dbg !1717
  %388 = load i64, ptr %195, align 8, !dbg !1691, !alias.scope !1614, !noalias !1524
  br i1 %387, label %391, label %389, !dbg !1717

389:                                              ; preds = %386
  %390 = load i64, ptr %12, align 8, !dbg !1685, !range !595, !alias.scope !1614, !noalias !1524
  br label %371, !dbg !1717

391:                                              ; preds = %386
  %.lcssa207 = phi i64 [ %388, %386 ], !dbg !1691
  %392 = icmp sgt i64 %.lcssa207, -1, !dbg !1719
  call void @llvm.assume(i1 %392), !dbg !1722, !noalias !1168
  br label %444, !dbg !1723

393:                                              ; preds = %371
  call void @llvm.experimental.noalias.scope.decl(metadata !1725), !dbg !1728, !noalias !1168
  call void @llvm.experimental.noalias.scope.decl(metadata !1733), !dbg !1736, !noalias !1168
  %394 = add nuw i64 %372, 32, !dbg !1739
  %395 = shl nuw i64 %372, 1, !dbg !1744
  %396 = call noundef i64 @llvm.umax.i64(i64 %394, i64 %395), !dbg !1746
  call void @llvm.lifetime.start.p0(ptr nonnull %3), !dbg !1754, !noalias !1757
; call <alloc::raw_vec::RawVecInner>::finish_grow
  call fastcc void @_RNvMs4_NtCslNYArtu3iFV_5alloc7raw_vecNtB5_11RawVecInner11finish_growCsjrHSEGnQ3l9_3std(ptr noalias noundef align 8 captures(none) dereferenceable(24) %3, i64 %372, ptr %376, i64 noundef %396, i64 noundef 1, i64 noundef 1), !dbg !1758, !noalias !1759
  %397 = load i64, ptr %3, align 8, !dbg !1760, !range !816, !noalias !1757, !noundef !31
  %398 = trunc nuw i64 %397 to i1, !dbg !1763
  br i1 %398, label %399, label %400, !dbg !1763

399:                                              ; preds = %393
  call void @llvm.lifetime.end.p0(ptr nonnull %3), !dbg !1764, !noalias !1757
  br label %444, !dbg !1765

400:                                              ; preds = %393
  %401 = load ptr, ptr %197, align 8, !dbg !1767, !noalias !1757, !nonnull !31, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %3), !dbg !1764, !noalias !1757
  store ptr %401, ptr %194, align 8, !dbg !1768, !alias.scope !1772, !noalias !1524
  %402 = icmp sgt i64 %396, -1, !dbg !1773
  call void @llvm.assume(i1 %402), !dbg !1773, !noalias !1168
  store i64 %396, ptr %12, align 8, !dbg !1776, !alias.scope !1772, !noalias !1524
  br label %403, !dbg !1777

403:                                              ; preds = %400, %377
  %404 = phi i64 [ %378, %377 ], [ %396, %400 ], !dbg !1708
  %405 = phi ptr [ %376, %377 ], [ %401, %400 ], !dbg !1697
  %406 = getelementptr inbounds nuw i8, ptr %405, i64 %373, !dbg !1780
  %407 = sub nsw i64 %404, %373, !dbg !1783
  %408 = call noundef i64 @llvm.umin.i64(i64 %.ph191, i64 %407), !dbg !1784
  %409 = call noundef i64 @llvm.umin.i64(i64 %408, i64 9223372036854775807)
  br label %410, !dbg !1790

410:                                              ; preds = %413, %403
  %411 = call noundef i64 @read(i32 noundef range(i32 0, -1) %265, ptr noundef nonnull %406, i64 noundef %409) #64, !dbg !1794, !noalias !1809
  %412 = icmp eq i64 %411, -1, !dbg !1819
  br i1 %412, label %413, label %421, !dbg !1825

413:                                              ; preds = %410
  %414 = tail call noundef ptr @__errno_location() #64, !dbg !1826
  %415 = load i32, ptr %414, align 4, !dbg !1829, !noalias !1809, !noundef !31
  %416 = icmp eq i32 %415, 4, !dbg !1830
  br i1 %416, label %410, label %417, !dbg !1836

417:                                              ; preds = %413
  %.lcssa218 = phi i64 [ %373, %413 ], !dbg !1691
  %.lcssa204 = phi i32 [ %415, %413 ], !dbg !1829
  %418 = sext i32 %.lcssa204 to i64, !dbg !1837
  %419 = shl nsw i64 %418, 32, !dbg !1840
  %420 = or disjoint i64 %419, 2, !dbg !1840
  store i64 %.lcssa218, ptr %195, align 8, !dbg !1841, !alias.scope !1614, !noalias !1524
  br label %444, !dbg !1849

421:                                              ; preds = %410
  %.lcssa201 = phi i64 [ %411, %410 ], !dbg !1794
  %422 = call noundef i64 @llvm.umax.i64(i64 %.lcssa201, i64 %367), !dbg !1851
  %423 = sub nuw i64 %422, %.lcssa201, !dbg !1862
  %424 = add i64 %.lcssa201, %373, !dbg !1869
  store i64 %424, ptr %195, align 8, !dbg !1841, !alias.scope !1614, !noalias !1524
  %425 = icmp eq i64 %.lcssa201, 0, !dbg !1870
  br i1 %425, label %426, label %428, !dbg !1870

426:                                              ; preds = %421
  %.lcssa208 = phi i64 [ %424, %421 ], !dbg !1869
  %427 = icmp sgt i64 %.lcssa208, -1, !dbg !1871
  call void @llvm.assume(i1 %427), !dbg !1874, !noalias !1168
  br label %444, !dbg !1849

428:                                              ; preds = %421
  %429 = icmp ult i64 %.lcssa201, %408, !dbg !1875
  %430 = add i32 %366, 1, !dbg !1875
  %431 = select i1 %429, i32 %430, i32 0, !dbg !1875
  br i1 %348, label %432, label %363, !dbg !1876

432:                                              ; preds = %428
  %.lcssa242 = phi i64 [ %408, %428 ]
  %.lcssa241 = phi i64 [ %422, %428 ]
  %.lcssa223 = phi i64 [ %404, %428 ], !dbg !1708
  %.lcssa214 = phi i32 [ %431, %428 ], !dbg !1875
  %.lcssa213 = phi i64 [ %423, %428 ], !dbg !1862
  %.lcssa209 = phi i64 [ %424, %428 ], !dbg !1869
  %.lcssa201.lcssa203 = phi i64 [ %.lcssa201, %428 ], !dbg !1794
  %433 = icmp ne i64 %.lcssa241, %.lcssa242
  %434 = icmp sgt i32 %.lcssa214, 1
  %435 = select i1 %433, i1 %434, i1 false, !dbg !1877
  %436 = select i1 %435, i64 -1, i64 %.ph191, !dbg !1877
  %437 = icmp uge i64 %.lcssa242, %436, !dbg !1878
  %438 = icmp eq i64 %.lcssa201.lcssa203, %.lcssa242
  %439 = and i1 %438, %437, !dbg !1878
  br i1 %439, label %440, label %.outer.backedge, !dbg !1878

440:                                              ; preds = %432
  %441 = shl nuw i64 %436, 1, !dbg !1879
  %442 = icmp slt i64 %436, 0, !dbg !1879
  br i1 %442, label %443, label %.outer.backedge, !dbg !1886, !prof !961

.outer:                                           ; preds = %.outer.backedge, %344
  %.ph = phi i64 [ %346, %344 ], [ %.lcssa223, %.outer.backedge ]
  %.ph188 = phi i64 [ %347, %344 ], [ %.lcssa209, %.outer.backedge ]
  %.ph189 = phi i32 [ 0, %344 ], [ %.lcssa214, %.outer.backedge ]
  %.ph190 = phi i64 [ 0, %344 ], [ %.lcssa213, %.outer.backedge ]
  %.ph191 = phi i64 [ %349, %344 ], [ %.ph191.be, %.outer.backedge ]
  br label %363, !dbg !1684

443:                                              ; preds = %440
  br label %.outer.backedge, !dbg !1891

.outer.backedge:                                  ; preds = %443, %440, %432
  %.ph191.be = phi i64 [ %436, %432 ], [ %441, %440 ], [ -1, %443 ]
  br label %.outer, !dbg !1684

444:                                              ; preds = %426, %417, %399, %391, %384
  %445 = phi i64 [ %385, %384 ], [ %.lcssa207, %391 ], [ %.lcssa208, %426 ], [ %420, %417 ], [ 163208757251, %399 ], !dbg !1892
  %446 = phi i1 [ true, %384 ], [ false, %391 ], [ false, %426 ], [ true, %417 ], [ true, %399 ], !dbg !1892
  %447 = inttoptr i64 %445 to ptr, !dbg !1893
  br label %_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i, !dbg !1894

_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i: ; preds = %444, %358, %.noexc.i
  %448 = phi ptr [ %447, %444 ], [ %356, %.noexc.i ], [ null, %358 ], !dbg !1682
  %449 = phi i1 [ %446, %444 ], [ true, %.noexc.i ], [ false, %358 ], !dbg !1682
  %450 = load ptr, ptr %194, align 8, !dbg !1896, !alias.scope !1608, !noalias !1524, !nonnull !31, !noundef !31
  %451 = load i64, ptr %195, align 8, !dbg !1910, !alias.scope !1608, !noalias !1524, !noundef !31
  call void @llvm.lifetime.start.p0(ptr nonnull %5), !dbg !1911, !noalias !1913
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %5, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %450, i64 noundef %451), !dbg !1911, !noalias !1914
  %452 = load i64, ptr %5, align 8, !dbg !1915, !range !816, !noalias !1913, !noundef !31
  %453 = icmp eq i64 %452, 0, !dbg !1922
  call void @llvm.lifetime.end.p0(ptr nonnull %5), !dbg !1923, !noalias !1913
  br i1 %453, label %459, label %.thread87, !dbg !1911

.loopexit:                                        ; preds = %379
  %.lcssa232 = phi i32 [ %265, %379 ], !dbg !1329
  %lpad.loopexit = landingpad { ptr, i32 }
          cleanup
  br label %454

.loopexit.split-lp:                               ; preds = %350
  %.lcssa231 = phi i32 [ %265, %350 ], !dbg !1329
  %lpad.loopexit.split-lp = landingpad { ptr, i32 }
          cleanup
  br label %454

454:                                              ; preds = %.loopexit.split-lp, %.loopexit
  %455 = phi i32 [ %.lcssa232, %.loopexit ], [ %.lcssa231, %.loopexit.split-lp ]
  %lpad.phi = phi { ptr, i32 } [ %lpad.loopexit, %.loopexit ], [ %lpad.loopexit.split-lp, %.loopexit.split-lp ]
  %456 = load i64, ptr %12, align 8, !dbg !1589, !range !595, !alias.scope !1592, !noalias !1524, !noundef !31
  %457 = icmp eq i64 %456, 0, !dbg !1924
  br i1 %457, label %.body.i, label %326, !dbg !1924

.thread87:                                        ; preds = %_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i
  %458 = select i1 %449, ptr %448, ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50, !dbg !1926
  %.pre137 = load i64, ptr %12, align 8, !dbg !1929, !range !595, !alias.scope !1930, !noalias !1524
  br label %461, !dbg !1935

459:                                              ; preds = %_RINvNtCsjrHSEGnQ3l9_3std2io19default_read_to_endNtNtB4_2fs4FileEB4_.exit.i
  %460 = icmp sgt i64 %451, -1, !dbg !1939
  call void @llvm.assume(i1 %460), !dbg !1943, !noalias !1168
  %.pre138 = load i64, ptr %12, align 8, !dbg !1929, !alias.scope !1930, !noalias !1524
  br i1 %449, label %461, label %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit, !dbg !1935

461:                                              ; preds = %459, %.thread87
  %462 = phi ptr [ %450, %459 ], [ %450, %.thread87 ]
  %463 = phi i64 [ %.pre138, %459 ], [ %.pre137, %.thread87 ], !dbg !1929
  %464 = phi ptr [ %448, %459 ], [ %458, %.thread87 ]
  %465 = icmp eq i64 %463, 0, !dbg !1581
  br i1 %465, label %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244, label %466, !dbg !1581

466:                                              ; preds = %461
  call void @free(ptr noundef nonnull %462) #64, !dbg !1944, !noalias !1316
  br label %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244, !dbg !1951

.body.i:                                          ; preds = %285, %316, %326, %454
  %467 = phi i32 [ %455, %326 ], [ %455, %454 ], [ %.lcssa228, %285 ], [ %.lcssa230, %316 ]
  %468 = phi { ptr, i32 } [ %lpad.phi, %326 ], [ %lpad.phi, %454 ], [ %286, %285 ], [ %311, %316 ]
  %469 = call noundef i32 @close(i32 noundef %467) #64, !dbg !1952, !noalias !1968
  br label %common.resume, !dbg !1971

_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244: ; preds = %466, %461, %.thread243
  %_4.i.sroa.7.0.ph = phi ptr [ inttoptr (i64 163208757251 to ptr), %.thread243 ], [ %464, %461 ], [ %464, %466 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %12), !dbg !1972, !noalias !1524
  %470 = call noundef i32 @close(i32 noundef %265) #64, !dbg !1973, !noalias !1316
  br label %_ZN5read19read_file17h6af6fcbddb469649E.exit.thread

_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit: ; preds = %459
  %_4.i.sroa.11.1 = phi i64 [ %451, %459 ]
  %_4.i.sroa.7.0 = phi ptr [ %450, %459 ], !dbg !1979
  %_4.i.sroa.0.0 = phi i64 [ %.pre138, %459 ], !dbg !1979
  call void @llvm.lifetime.end.p0(ptr nonnull %12), !dbg !1972, !noalias !1524
  %471 = call noundef i32 @close(i32 noundef %265) #64, !dbg !1973, !noalias !1316
  %472 = icmp eq i64 %_4.i.sroa.0.0, -9223372036854775808
  br i1 %472, label %_ZN5read19read_file17h6af6fcbddb469649E.exit.thread, label %bb13.i

_ZN5read19read_file17h6af6fcbddb469649E.exit.thread: ; preds = %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit, %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244, %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread
  %_18.i93 = phi ptr [ %263, %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread ], [ %_4.i.sroa.7.0, %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit ], [ %_4.i.sroa.7.0.ph, %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit.thread244 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %_11.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %result.i)
  br label %bb31

bb13.i:                                           ; preds = %_RNvNvNtCsjrHSEGnQ3l9_3std2fs14read_to_string5inner.exit
  call void @llvm.lifetime.start.p0(ptr nonnull %reader.i), !noalias !1980
; call r7rs_wasm_reference::Reader::new
  call fastcc void @_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(32) %reader.i, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %_4.i.sroa.7.0, i64 noundef %_4.i.sroa.11.1) #64, !noalias !1168
  %473 = call noundef dereferenceable_or_null(2) ptr @malloc(i64 noundef 2) #64, !dbg !1113, !noalias !1982
  %474 = icmp eq ptr %473, null
  br i1 %474, label %bb17.i, label %bb18.i, !prof !961

bb17.i:                                           ; preds = %bb13.i
; call alloc::raw_vec::handle_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 2) #106, !noalias !1168
  unreachable

bb18.i:                                           ; preds = %bb13.i
  store i16 26147, ptr %473, align 1, !noalias !1168
  store i64 2, ptr %179, align 8, !noalias !1980
  store ptr %473, ptr %_10.sroa.4.0..sroa_idx.i, align 8, !noalias !1980
  store i64 2, ptr %_10.sroa.5.0..sroa_idx.i, align 8, !noalias !1980
  store i64 -9223372036854775808, ptr %result.i, align 8, !noalias !1980
  br label %bb4.i

bb4.i:                                            ; preds = %bb6.i, %bb18.i
  call void @llvm.experimental.noalias.scope.decl(metadata !1985)
; call r7rs_wasm_reference::Reader::skip_space
  %475 = call fastcc noundef zeroext i1 @_ZN19r7rs_wasm_reference6Reader10skip_space17h8f14cc2594bb2e68E(ptr noalias noundef nonnull align 8 dereferenceable(32) %reader.i) #64, !noalias !1988
  br i1 %475, label %_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit, label %_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit.thread

_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit.thread: ; preds = %bb4.i
  store i64 -9223372036854775801, ptr %_11.i, align 8, !alias.scope !1985, !noalias !1989
  br label %bb11.i

_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit: ; preds = %bb4.i
; call r7rs_wasm_reference::Reader::datum
  call fastcc void @_ZN19r7rs_wasm_reference6Reader5datum17h7ae745f2407c5577E(ptr noalias noundef nonnull align 8 captures(address) dereferenceable(32) %_11.i, ptr noalias noundef nonnull align 8 dereferenceable(32) %reader.i) #64, !noalias !1168
  %.pr94 = load i64, ptr %_11.i, align 8, !noalias !1980
  %.not.i = icmp eq i64 %.pr94, -9223372036854775801
  br i1 %.not.i, label %bb11.i, label %bb6.i

bb6.i:                                            ; preds = %_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef align 8 dereferenceable(32) %result.i) #64, !noalias !1168
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %result.i, ptr noundef nonnull align 8 dereferenceable(32) %_11.i, i64 32, i1 false), !noalias !1980
  br label %bb4.i

bb11.i:                                           ; preds = %_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit, %_ZN19r7rs_wasm_reference6Reader4read17h67f5f6e940df0826E.exit.thread
  %_16.sroa.0.0.copyload = load i64, ptr %result.i, align 8, !noalias !1991
  %_16.sroa.6.0.copyload = load ptr, ptr %179, align 8, !noalias !1991
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %_16.sroa.9, ptr noundef nonnull align 8 dereferenceable(16) %_10.sroa.4.0..sroa_idx.i, i64 16, i1 false), !noalias !1991
  %reader.val.i = load i64, ptr %reader.i, align 8, !range !595, !noalias !1980, !noundef !31
  %476 = icmp eq i64 %reader.val.i, 0
  br i1 %476, label %"_ZN4core3ptr48drop_in_place$LT$r7rs_wasm_reference..Reader$GT$17h65392a7452a7e4a1E.exit.i", label %bb2.i.i.i.i.i.i

bb2.i.i.i.i.i.i:                                  ; preds = %bb11.i
  %reader.val5.i = load ptr, ptr %180, align 8, !noalias !1980, !nonnull !31, !noundef !31
  call void @free(ptr noundef nonnull %reader.val5.i) #64, !dbg !581
  br label %"_ZN4core3ptr48drop_in_place$LT$r7rs_wasm_reference..Reader$GT$17h65392a7452a7e4a1E.exit.i"

"_ZN4core3ptr48drop_in_place$LT$r7rs_wasm_reference..Reader$GT$17h65392a7452a7e4a1E.exit.i": ; preds = %bb2.i.i.i.i.i.i, %bb11.i
  call void @llvm.lifetime.end.p0(ptr nonnull %reader.i), !noalias !1980
  %477 = icmp eq i64 %_4.i.sroa.0.0, 0
  br i1 %477, label %_ZN5read19read_file17h6af6fcbddb469649E.exit, label %bb2.i.i.i.i.i6.i

bb2.i.i.i.i.i6.i:                                 ; preds = %"_ZN4core3ptr48drop_in_place$LT$r7rs_wasm_reference..Reader$GT$17h65392a7452a7e4a1E.exit.i"
  call void @free(ptr noundef nonnull %_4.i.sroa.7.0) #64, !dbg !581
  br label %_ZN5read19read_file17h6af6fcbddb469649E.exit

_ZN5read19read_file17h6af6fcbddb469649E.exit:     ; preds = %"_ZN4core3ptr48drop_in_place$LT$r7rs_wasm_reference..Reader$GT$17h65392a7452a7e4a1E.exit.i", %bb2.i.i.i.i.i6.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_11.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %result.i)
  %478 = icmp eq i64 %_16.sroa.0.0.copyload, -9223372036854775801
  br i1 %478, label %bb31, label %bb32

bb30:                                             ; preds = %bb28
  %right_val = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 64
; call <r7rs_wasm_reference::Datum as core::cmp::PartialEq>::eq
  %_22 = call fastcc noundef zeroext i1 @"_ZN67_$LT$r7rs_wasm_reference..Datum$u20$as$u20$core..cmp..PartialEq$GT$2eq17hffb9da69538c0747E"(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %result, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %right_val) #100
  br i1 %_22, label %bb10, label %bb11, !prof !656

panic3:                                           ; preds = %bb28
; call core::panicking::panic_bounds_check
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 2, i64 noundef 2, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_7230d6a0828b84f6d8e25a2de0d124ee) #102
  unreachable

bb11:                                             ; preds = %bb30
; call core::panicking::assert_failed
  call fastcc void @_ZN4core9panicking13assert_failed17he3242427da90d541E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %result, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %right_val) #102
  unreachable

bb10:                                             ; preds = %bb30
  call void @llvm.lifetime.start.p0(ptr nonnull %result.i11)
  call void @llvm.lifetime.start.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %name.i)
  store ptr @alloc_8eca58e7543091d1f826a66a8cd73a6b, ptr %name.i, align 8, !noalias !1992
  %479 = getelementptr inbounds nuw i8, ptr %name.i, i64 8
  store i64 5, ptr %479, align 8, !noalias !1992
  store i64 %count, ptr %count.i, align 8, !noalias !1992
  store ptr %result, ptr %result.i11, align 8, !noalias !1992
  call void @llvm.lifetime.start.p0(ptr nonnull %seconds.i), !noalias !1992
; call <std::sys::pal::unix::time::Timespec>::now
  %480 = call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #64, !dbg !1995
  %481 = extractvalue { i64, i32 } %480, 0, !dbg !1999
  %482 = extractvalue { i64, i32 } %480, 1, !dbg !1999
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store i64 %481, ptr %2, align 8
  %483 = getelementptr inbounds nuw i8, ptr %2, i64 8
  store i32 %482, ptr %483, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %1), !noalias !2000
  store i64 %start.0, ptr %1, align 8, !noalias !2003
  %484 = getelementptr inbounds nuw i8, ptr %1, i64 8
  store i32 %start.1, ptr %484, align 8, !noalias !2003
  call void @llvm.lifetime.start.p0(ptr nonnull %0), !dbg !2006, !noalias !2016
; call <std::sys::pal::unix::time::Timespec>::sub_timespec
  call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec12sub_timespec(ptr noalias noundef align 8 captures(none) dereferenceable(24) %0, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %2, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %1) #64, !dbg !2020
  %485 = load i64, ptr %0, align 8, !dbg !2021, !range !816, !noalias !2016, !noundef !31
  %486 = trunc nuw i64 %485 to i1, !dbg !2024
  %487 = getelementptr inbounds nuw i8, ptr %0, i64 8, !dbg !2024
  %488 = load i64, ptr %487, align 8, !dbg !2024, !noalias !2016
  %489 = getelementptr inbounds nuw i8, ptr %0, i64 16, !dbg !2024
  %490 = load i32, ptr %489, align 8, !dbg !2024, !range !2025, !noalias !2016
  call void @llvm.lifetime.end.p0(ptr nonnull %0), !dbg !2026, !noalias !2016
  call void @llvm.lifetime.end.p0(ptr nonnull %1), !dbg !2027, !noalias !2000
  call void @llvm.lifetime.end.p0(ptr nonnull %2), !dbg !2028
  %491 = uitofp i64 %488 to double
  %492 = uitofp nneg i32 %490 to double
  %493 = fdiv double %492, 1.000000e+09
  %494 = fadd double %493, %491
  %495 = select i1 %486, double 0.000000e+00, double %494
  store double %495, ptr %seconds.i, align 8, !noalias !1992
  call void @llvm.lifetime.start.p0(ptr nonnull %args.i), !noalias !1992
  store ptr %result.i11, ptr %args.i, align 8, !noalias !1992
  %_12.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args.i, i64 8
  store ptr @"_ZN44_$LT$$RF$T$u20$as$u20$core..fmt..Display$GT$3fmt17h7b30da9459a4d0d8E", ptr %_12.sroa.4.0..sroa_idx.i, align 8, !noalias !1992
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_1411a66fb3eebd1e386b0f09aa6c2612, ptr noundef nonnull %args.i) #64
  call void @llvm.lifetime.end.p0(ptr nonnull %args.i), !noalias !1992
  call void @llvm.lifetime.start.p0(ptr nonnull %args2.i), !noalias !1992
  store ptr %name.i, ptr %args2.i, align 8, !noalias !1992
  %_20.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 8
  store ptr @"_ZN44_$LT$$RF$T$u20$as$u20$core..fmt..Display$GT$3fmt17h2fa3bdffe2d6980aE", ptr %_20.sroa.4.0..sroa_idx.i, align 8, !noalias !1992
  %496 = getelementptr inbounds nuw i8, ptr %args2.i, i64 16
  store ptr %count.i, ptr %496, align 8, !noalias !1992
  %_21.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 24
  store ptr @_RNvXsd_NtNtNtCsgEmfK2I1SDS_4core3fmt3num3impyNtB9_7Display3fmt, ptr %_21.sroa.4.0..sroa_idx.i, align 8, !noalias !1992
  %497 = getelementptr inbounds nuw i8, ptr %args2.i, i64 32
  store ptr %seconds.i, ptr %497, align 8, !noalias !1992
  %_22.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 40
  store ptr @_RNvXs7_NtNtCsgEmfK2I1SDS_4core3fmt5floatdNtB7_7Display3fmt, ptr %_22.sroa.4.0..sroa_idx.i, align 8, !noalias !1992
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_425ac0839427cedeadf73b1b30f184e4, ptr noundef nonnull %args2.i) #64
  call void @llvm.lifetime.end.p0(ptr nonnull %args2.i), !noalias !1992
  call void @llvm.lifetime.end.p0(ptr nonnull %seconds.i), !noalias !1992
  call void @llvm.lifetime.end.p0(ptr nonnull %result.i11)
  call void @llvm.lifetime.end.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %name.i)
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef align 8 dereferenceable(32) %result) #64
  call void @llvm.lifetime.end.p0(ptr nonnull %result)
  br label %bb2.i.i.i

bb2.i.i.i:                                        ; preds = %bb10, %bb2.i.i.i
  %_3.sroa.0.0.i2.i.i = phi i64 [ %498, %bb2.i.i.i ], [ 0, %bb10 ]
  %_6.i.i.i = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %_3.sroa.6.1, i64 %_3.sroa.0.0.i2.i.i
  %498 = add nuw i64 %_3.sroa.0.0.i2.i.i, 1
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef readonly align 8 dereferenceable(32) %_6.i.i.i) #64, !noalias !2029
  %_7.i.i.i = icmp eq i64 %498, %_3.sroa.9.1
  br i1 %_7.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i", label %bb2.i.i.i

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i": ; preds = %bb2.i.i.i
  %499 = icmp eq i64 %_3.sroa.0.1, 0
  br i1 %499, label %bb17, label %bb2.i.i.i.i

bb2.i.i.i.i:                                      ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i"
  call void @free(ptr noundef nonnull %_3.sroa.6.1) #64, !dbg !581
  br label %bb17

bb17:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i19", %bb2.i.i.i.i21, %bb2.i.i.i.i, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i"
  %_0.sroa.0.0 = phi ptr [ null, %bb2.i.i.i.i ], [ null, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i" ], [ %_16.sroa.6.031, %bb2.i.i.i.i21 ], [ %_16.sroa.6.031, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i19" ], [ %123, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread ], [ %_3.sroa.6.1, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit ]
  ret ptr %_0.sroa.0.0

bb31:                                             ; preds = %_ZN5read19read_file17h6af6fcbddb469649E.exit, %_ZN5read19read_file17h6af6fcbddb469649E.exit.thread
  %_16.sroa.6.031 = phi ptr [ %_18.i93, %_ZN5read19read_file17h6af6fcbddb469649E.exit.thread ], [ %_16.sroa.6.0.copyload, %_ZN5read19read_file17h6af6fcbddb469649E.exit ]
  %500 = icmp ne ptr %_16.sroa.6.031, null
  call void @llvm.assume(i1 %500)
  call void @llvm.lifetime.end.p0(ptr nonnull %_16.sroa.9)
  call void @llvm.lifetime.end.p0(ptr nonnull %_14)
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef align 8 dereferenceable(32) %result) #64
  call void @llvm.lifetime.end.p0(ptr nonnull %result)
  br label %bb2.i.i.i15

bb2.i.i.i15:                                      ; preds = %bb31, %bb2.i.i.i15
  %_3.sroa.0.0.i2.i.i16 = phi i64 [ %501, %bb2.i.i.i15 ], [ 0, %bb31 ]
  %_6.i.i.i17 = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %_3.sroa.6.1, i64 %_3.sroa.0.0.i2.i.i16
  %501 = add nuw i64 %_3.sroa.0.0.i2.i.i16, 1
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef readonly align 8 dereferenceable(32) %_6.i.i.i17) #64, !noalias !2032
  %_7.i.i.i18 = icmp eq i64 %501, %_3.sroa.9.1
  br i1 %_7.i.i.i18, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i19", label %bb2.i.i.i15

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i19": ; preds = %bb2.i.i.i15
  %502 = icmp eq i64 %_3.sroa.0.1, 0
  br i1 %502, label %bb17, label %bb2.i.i.i.i21

bb2.i.i.i.i21:                                    ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h910eb0c3714a3fb2E.exit.i19"
  call void @free(ptr noundef nonnull %_3.sroa.6.1) #64, !dbg !581
  br label %bb17

bb32:                                             ; preds = %_ZN5read19read_file17h6af6fcbddb469649E.exit
  %_63 = add nuw i64 %iter.sroa.0.035, 1
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %val1.sroa.3.0._14.sroa_idx, ptr noundef nonnull align 8 dereferenceable(16) %_16.sroa.9, i64 16, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %_16.sroa.9)
  store i64 %_16.sroa.0.0.copyload, ptr %_14, align 8
  store ptr %_16.sroa.6.0.copyload, ptr %val1.sroa.2.0._14.sroa_idx, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %_14) #64, !srcloc !30
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h4b09878f50751ee9E"(ptr noalias noundef align 8 dereferenceable(32) %result) #64
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %result, ptr noundef nonnull align 8 dereferenceable(32) %_14, i64 32, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %_14)
  %exitcond.not = icmp eq i64 %_63, %count
  br i1 %exitcond.not, label %bb28, label %bb27
}
