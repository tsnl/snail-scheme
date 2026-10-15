define internal noundef ptr @_ZN6matrix4main17h2be5f844019f6288E() unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %0 = alloca [24 x i8], align 8
  %1 = alloca [16 x i8], align 8
  %2 = alloca [16 x i8], align 8
  %3 = alloca [1 x i8], align 1
  %4 = alloca [24 x i8], align 8
  %5 = alloca [32 x i8], align 8
  %6 = alloca [24 x i8], align 8
  %7 = alloca [32 x i8], align 8
  %8 = alloca [24 x i8], align 8
  %9 = alloca [24 x i8], align 8
  %10 = alloca [24 x i8], align 8
  %11 = alloca [24 x i8], align 8
  %args2.i = alloca [48 x i8], align 8
  %args.i = alloca [16 x i8], align 8
  %seconds.i = alloca [8 x i8], align 8
  %result.i = alloca [8 x i8], align 8
  %count.i = alloca [8 x i8], align 8
  %name.i = alloca [16 x i8], align 8
  %_6.i.i = alloca [24 x i8], align 8
  %generated.i.i = alloca [8 x i8], align 8
  %primes.i.i.i = alloca [24 x i8], align 8
  %best.i = alloca [48 x i8], align 8
  %rows.i = alloca [8 x i8], align 8
  %field.i = alloca [32 x i8], align 8
  %12 = alloca [8 x i8], align 8
  %13 = alloca [8 x i8], align 8
  %_18 = alloca [32 x i8], align 8
  %_17 = alloca [32 x i8], align 8
  %result = alloca [32 x i8], align 8
  %expected = alloca [32 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %11), !noalias !1458
  store i64 0, ptr %11, align 8, !noalias !1458
  %14 = getelementptr inbounds nuw i8, ptr %11, i64 8
  store ptr inttoptr (i64 1 to ptr), ptr %14, align 8, !noalias !1458
  %15 = getelementptr inbounds nuw i8, ptr %11, i64 16
  store i64 0, ptr %15, align 8, !noalias !1458
  %16 = load atomic i32, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 48) acquire, align 8, !dbg !1461, !noalias !1458
  %17 = icmp eq i32 %16, 0, !dbg !1499
  br i1 %17, label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, label %18, !dbg !1499, !prof !1500

18:                                               ; preds = %start
; call <std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::initialize::<<std::sync::once_lock::OnceLock<std::sync::poison::mutex::Mutex<std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw>>>>::get_or_init<std::io::stdio::stdin::{closure#0}>::{closure#0}, !>
  tail call fastcc void @_RINvMNtNtCsjrHSEGnQ3l9_3std4sync9once_lockINtB3_8OnceLockINtNtNtB5_6poison5mutex5MutexINtNtNtNtB7_2io8buffered9bufreader9BufReaderNtNtB1t_5stdio8StdinRawEEE10initializeNCINvB2_11get_or_initNCNvB26_5stdin0E0zEB7_() #65, !dbg !1501, !noalias !1458
  br label %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i, !dbg !1502

_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i: ; preds = %18, %start
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1503)
  %19 = cmpxchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0, i32 1 acquire monotonic, align 4, !dbg !1506, !noalias !1528
  %20 = extractvalue { i32, i1 } %19, 1, !dbg !1533
  br i1 %20, label %22, label %21, !dbg !1534, !prof !1500

21:                                               ; preds = %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
; call <std::sys::sync::mutex::futex::Mutex>::lock_contended
  tail call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys4sync5mutex5futexNtB2_5Mutex14lock_contended(ptr noundef nonnull align 8 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE), !dbg !1535, !noalias !1528
  br label %22, !dbg !1535

22:                                               ; preds = %21, %_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin.exit.i
  %23 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1536, !noalias !1528
  %24 = and i64 %23, 9223372036854775807, !dbg !1561
  %25 = icmp eq i64 %24, 0, !dbg !1561
  br i1 %25, label %29, label %26, !dbg !1561, !prof !1500

26:                                               ; preds = %22
; call std::panicking::panic_count::is_zero_slow_path
  %27 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #106, !dbg !1562, !noalias !1528
  %28 = xor i1 %27, true, !dbg !1563
  br label %29, !dbg !1562

29:                                               ; preds = %26, %22
  %30 = phi i1 [ %28, %26 ], [ false, %22 ], !dbg !1564
  %31 = load atomic i8, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !1565, !noalias !1528
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1574), !dbg !1577
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1578), !dbg !1581
  %32 = load i64, ptr %15, align 8, !dbg !1585, !alias.scope !1605, !noalias !1606, !noundef !31
  %33 = icmp sgt i64 %32, -1, !dbg !1608
  tail call void @llvm.assume(i1 %33), !dbg !1610
  %34 = icmp eq i64 %32, 0, !dbg !1611
  br i1 %34, label %35, label %60, !dbg !1611

35:                                               ; preds = %29
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1612), !dbg !1615
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %36 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef nonnull align 8 dereferenceable(24) %11)
          to label %39 unwind label %37, !dbg !1616, !noalias !1458

37:                                               ; preds = %35
  %38 = landingpad { ptr, i32 }
          cleanup
  br label %52, !dbg !1624

39:                                               ; preds = %35
  %40 = extractvalue { i64, ptr } %36, 0, !dbg !1625
  %41 = extractvalue { i64, ptr } %36, 1, !dbg !1625
  %42 = load ptr, ptr %14, align 8, !dbg !1626, !alias.scope !1645, !noalias !1646, !nonnull !31, !noundef !31
  %43 = load i64, ptr %15, align 8, !dbg !1648, !alias.scope !1645, !noalias !1646, !noundef !31
  call void @llvm.lifetime.start.p0(ptr nonnull %8), !dbg !1649, !noalias !1651
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %8, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %42, i64 noundef %43), !dbg !1649, !noalias !1651
  %44 = load i64, ptr %8, align 8, !dbg !1652, !range !954, !noalias !1651, !noundef !31
  %45 = icmp eq i64 %44, 0, !dbg !1660
  call void @llvm.lifetime.end.p0(ptr nonnull %8), !dbg !1661, !noalias !1651
  br i1 %45, label %46, label %49, !dbg !1649

46:                                               ; preds = %39
  %47 = icmp sgt i64 %43, -1, !dbg !1662
  tail call void @llvm.assume(i1 %47), !dbg !1666
  %48 = trunc nuw i64 %40 to i1
  br label %55, !dbg !1667

49:                                               ; preds = %39
  %50 = trunc nuw i64 %40 to i1, !dbg !1668
  %51 = select i1 %50, ptr %41, ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50, !dbg !1668
  br label %55, !dbg !1668

52:                                               ; preds = %68, %64, %37
  %53 = phi { ptr, i32 } [ %38, %37 ], [ %65, %68 ], [ %65, %64 ]
  %54 = zext i1 %30 to i8, !dbg !1671
; call core::ptr::drop_in_place::<std::io::stdio::StdinLock>
  tail call fastcc void @_RINvNtCsgEmfK2I1SDS_4core3ptr13drop_in_placeNtNtNtCsjrHSEGnQ3l9_3std2io5stdio9StdinLockEBM_(ptr nonnull @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i8 %54) #107, !dbg !1672, !noalias !1673
  resume { ptr, i32 } %53, !dbg !1674

55:                                               ; preds = %49, %46
  %56 = phi ptr [ %41, %46 ], [ %51, %49 ], !dbg !1615
  %57 = phi i1 [ %48, %46 ], [ true, %49 ], !dbg !1615
  %58 = phi i64 [ %43, %46 ], [ 0, %49 ], !dbg !1675
  store i64 %58, ptr %15, align 8, !dbg !1676, !alias.scope !1645, !noalias !1684
  %59 = ptrtoint ptr %56 to i64, !dbg !1615
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !1687

60:                                               ; preds = %29
  call void @llvm.lifetime.start.p0(ptr nonnull %10), !dbg !1688, !noalias !1689
  store i64 0, ptr %10, align 8, !dbg !1690, !noalias !1689
  %61 = getelementptr inbounds nuw i8, ptr %10, i64 8, !dbg !1690
  store ptr inttoptr (i64 1 to ptr), ptr %61, align 8, !dbg !1690, !noalias !1689
  %62 = getelementptr inbounds nuw i8, ptr %10, i64 16, !dbg !1690
  store i64 0, ptr %62, align 8, !dbg !1690, !noalias !1689
; invoke <std::io::buffered::bufreader::BufReader<std::io::stdio::StdinRaw> as std::io::Read>::read_to_end
  %63 = invoke fastcc { i64, ptr } @_RNvXs3_NtNtNtCsjrHSEGnQ3l9_3std2io8buffered9bufreaderINtB5_9BufReaderNtNtB9_5stdio8StdinRawENtB9_4Read11read_to_endBb_(ptr noalias noundef nonnull align 8 dereferenceable(40) getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 8), ptr noalias noundef align 8 dereferenceable(24) %10)
          to label %70 unwind label %64, !dbg !1693, !noalias !1695

64:                                               ; preds = %90, %60
  %65 = landingpad { ptr, i32 }
          cleanup
  %66 = load i64, ptr %10, align 8, !dbg !1696, !range !1117, !alias.scope !1699, !noalias !1689, !noundef !31
  %67 = icmp eq i64 %66, 0, !dbg !1702
  br i1 %67, label %52, label %68, !dbg !1702

68:                                               ; preds = %64
  %69 = load ptr, ptr %61, align 8, !dbg !1696, !alias.scope !1699, !noalias !1689, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %69) #65, !dbg !1713, !noalias !1728
  br label %52, !dbg !1729

70:                                               ; preds = %60
  %71 = extractvalue { i64, ptr } %63, 0, !dbg !1730
  %72 = trunc nuw i64 %71 to i1, !dbg !1731
  br i1 %72, label %73, label %76, !dbg !1731

73:                                               ; preds = %70
  %74 = extractvalue { i64, ptr } %63, 1, !dbg !1730
  %75 = ptrtoint ptr %74 to i64, !dbg !1730
  br label %107, !dbg !1734

76:                                               ; preds = %70
  call void @llvm.lifetime.start.p0(ptr nonnull %9), !dbg !1737, !noalias !1689
  %77 = load ptr, ptr %61, align 8, !dbg !1738, !noalias !1689, !nonnull !31, !noundef !31
  %78 = load i64, ptr %62, align 8, !dbg !1751, !noalias !1689, !noundef !31
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %9, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %77, i64 noundef %78), !dbg !1737, !noalias !1689
  %79 = load i64, ptr %9, align 8, !dbg !1752, !range !954, !noalias !1689, !noundef !31
  %80 = trunc nuw i64 %79 to i1, !dbg !1755
  br i1 %80, label %81, label %82, !dbg !1755

81:                                               ; preds = %76
  call void @llvm.lifetime.end.p0(ptr nonnull %9), !dbg !1756, !noalias !1689
  br label %107, !dbg !1734

82:                                               ; preds = %76
  %83 = getelementptr inbounds nuw i8, ptr %9, i64 8, !dbg !1757
  %84 = load ptr, ptr %83, align 8, !dbg !1757, !noalias !1689, !nonnull !31, !align !68, !noundef !31
  %85 = getelementptr inbounds nuw i8, ptr %9, i64 16, !dbg !1757
  %86 = load i64, ptr %85, align 8, !dbg !1757, !noalias !1689, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %9), !dbg !1756, !noalias !1689
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1758), !dbg !1761
  %87 = load i64, ptr %11, align 8, !dbg !1776, !range !1117, !alias.scope !1790, !noalias !1606, !noundef !31
  %88 = sub nsw i64 %87, %32, !dbg !1793
  %89 = icmp ugt i64 %86, %88, !dbg !1799
  br i1 %89, label %90, label %94, !dbg !1800, !prof !1319

90:                                               ; preds = %82
; invoke <alloc::raw_vec::RawVecInner<_>>::reserve::do_reserve_and_handle::<alloc::alloc::Global>
  invoke fastcc void @_RINvNvMs2_NtCslNYArtu3iFV_5alloc7raw_vecINtB8_11RawVecInnerpE7reserve21do_reserve_and_handleNtNtBa_5alloc6GlobalECsjrHSEGnQ3l9_3std(ptr noalias noundef nonnull align 8 dereferenceable(24) %11, i64 noundef %32, i64 noundef %86, i64 noundef 1, i64 noundef 1)
          to label %91 unwind label %64, !dbg !1801, !noalias !1606

91:                                               ; preds = %90
  %92 = load i64, ptr %15, align 8, !dbg !1802, !alias.scope !1805, !noalias !1606, !noundef !31
  %93 = icmp sgt i64 %92, -1, !dbg !1806
  tail call void @llvm.assume(i1 %93), !dbg !1808
  br label %96, !dbg !1809

94:                                               ; preds = %82
  %95 = icmp eq i64 %86, 0, !dbg !1809
  br i1 %95, label %100, label %96, !dbg !1809

96:                                               ; preds = %94, %91
  %97 = phi i64 [ %92, %91 ], [ %32, %94 ]
  %98 = load ptr, ptr %14, align 8, !dbg !1811, !alias.scope !1805, !noalias !1606, !nonnull !31, !noundef !31
  %99 = getelementptr inbounds nuw i8, ptr %98, i64 %97, !dbg !1820
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %99, ptr nonnull readonly align 1 %84, i64 %86, i1 false), !dbg !1826, !noalias !1829
  br label %100, !dbg !1830

100:                                              ; preds = %96, %94
  %101 = phi i64 [ %97, %96 ], [ %32, %94 ]
  %102 = add i64 %101, %86, !dbg !1831
  store i64 %102, ptr %15, align 8, !dbg !1831, !alias.scope !1805, !noalias !1606
  %103 = load i64, ptr %10, align 8, !dbg !1832, !range !1117, !alias.scope !1834, !noalias !1689, !noundef !31
  %104 = icmp eq i64 %103, 0, !dbg !1837
  br i1 %104, label %106, label %105, !dbg !1837

105:                                              ; preds = %100
  tail call void @free(ptr noundef nonnull %77) #65, !dbg !1842, !noalias !1728
  br label %106, !dbg !1849

106:                                              ; preds = %105, %100
  call void @llvm.lifetime.end.p0(ptr nonnull %10), !dbg !1850, !noalias !1689
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !1687

107:                                              ; preds = %81, %73
  %108 = phi i64 [ %75, %73 ], [ ptrtoint (ptr @anon.eb89d4395b0ead844ef0b45b8b54da85.50 to i64), %81 ], !dbg !1851
  %109 = load i64, ptr %10, align 8, !dbg !1855, !range !1117, !alias.scope !1857, !noalias !1689, !noundef !31
  %110 = icmp eq i64 %109, 0, !dbg !1860
  br i1 %110, label %113, label %111, !dbg !1860

111:                                              ; preds = %107
  %112 = load ptr, ptr %61, align 8, !dbg !1855, !alias.scope !1857, !noalias !1689, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %112) #65, !dbg !1865, !noalias !1728
  br label %113, !dbg !1872

113:                                              ; preds = %111, %107
  call void @llvm.lifetime.end.p0(ptr nonnull %10), !dbg !1850, !noalias !1689
  br label %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i, !dbg !1873

_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i: ; preds = %113, %106, %55
  %114 = phi i64 [ %59, %55 ], [ %108, %113 ], [ %86, %106 ], !dbg !1874
  %115 = phi i1 [ %57, %55 ], [ true, %113 ], [ false, %106 ], !dbg !1874
  %116 = inttoptr i64 %114 to ptr, !dbg !1873
  br i1 %30, label %124, label %117, !dbg !1875

117:                                              ; preds = %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %118 = load atomic i64, ptr @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1885, !noalias !1673
  %119 = and i64 %118, 9223372036854775807, !dbg !1895
  %120 = icmp eq i64 %119, 0, !dbg !1895
  br i1 %120, label %124, label %121, !dbg !1895, !prof !1500

121:                                              ; preds = %117
; call std::panicking::panic_count::is_zero_slow_path
  %122 = tail call fastcc noundef zeroext i1 @_RNvNtNtCsjrHSEGnQ3l9_3std9panicking11panic_count17is_zero_slow_path() #106, !dbg !1896, !noalias !1673
  br i1 %122, label %124, label %123, !dbg !1897

123:                                              ; preds = %121
  store atomic i8 1, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i64 4) monotonic, align 4, !dbg !1898, !noalias !1673
  br label %124, !dbg !1903

124:                                              ; preds = %123, %121, %117, %_RNvXs6_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_9StdinLockNtB7_4Read14read_to_string.exit.i.i
  %125 = atomicrmw xchg ptr @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 0 release, align 4, !dbg !1904, !noalias !1673
  %126 = icmp eq i32 %125, 2, !dbg !1911
  br i1 %126, label %127, label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !1911, !prof !1319

127:                                              ; preds = %124
  %128 = tail call noundef i64 (i64, ...) @syscall(i64 noundef 202, ptr noundef nonnull align 4 @_RNvNvNtNtCsjrHSEGnQ3l9_3std2io5stdio5stdin8INSTANCE, i32 noundef 129, i32 noundef 1) #65, !dbg !1912, !noalias !1673
  br label %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i, !dbg !1923

_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i: ; preds = %127, %124
  br i1 %115, label %129, label %132

129:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %130 = load i64, ptr %11, align 8, !range !1117, !noalias !1458, !noundef !31
  %131 = icmp eq i64 %130, 0
  br i1 %131, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, label %298

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread: ; preds = %129
  call void @llvm.lifetime.end.p0(ptr nonnull %11), !noalias !1458
  br label %bb18

132:                                              ; preds = %_RNvXs3_NtNtCsjrHSEGnQ3l9_3std2io5stdioNtB5_5StdinNtB7_4Read14read_to_string.exit.i
  %133 = load ptr, ptr %14, align 8, !noalias !1458, !nonnull !31, !noundef !31
  %134 = load i64, ptr %15, align 8, !noalias !1458, !noundef !31
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1924)
  call void @llvm.lifetime.start.p0(ptr nonnull %7), !noalias !1927
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1929)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1932)
  %135 = getelementptr inbounds nuw i8, ptr %133, i64 %134
  call void @llvm.lifetime.start.p0(ptr nonnull %4), !noalias !1934
  %136 = icmp samesign eq i64 %134, 0
  br i1 %136, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %137

137:                                              ; preds = %132
  %138 = getelementptr inbounds nuw i8, ptr %133, i64 1
  %139 = load i8, ptr %133, align 1, !alias.scope !1937, !noalias !1938, !noundef !31
  %140 = icmp sgt i8 %139, -1
  br i1 %140, label %152, label %141

141:                                              ; preds = %137
  %142 = and i8 %139, 31
  %143 = zext nneg i8 %142 to i32
  %144 = icmp samesign ne i64 %134, 1
  tail call void @llvm.assume(i1 %144)
  %145 = getelementptr inbounds nuw i8, ptr %133, i64 2
  %146 = load i8, ptr %138, align 1, !alias.scope !1937, !noalias !1938, !noundef !31
  %147 = shl nuw nsw i32 %143, 6
  %148 = and i8 %146, 63
  %149 = zext nneg i8 %148 to i32
  %150 = or disjoint i32 %147, %149
  %151 = icmp samesign ugt i8 %139, -33
  br i1 %151, label %154, label %177

152:                                              ; preds = %137
  %153 = zext nneg i8 %139 to i32
  br label %177

154:                                              ; preds = %141
  %155 = icmp samesign ne i64 %134, 2
  tail call void @llvm.assume(i1 %155)
  %156 = getelementptr inbounds nuw i8, ptr %133, i64 3
  %157 = load i8, ptr %145, align 1, !alias.scope !1937, !noalias !1938, !noundef !31
  %158 = shl nuw nsw i32 %149, 6
  %159 = and i8 %157, 63
  %160 = zext nneg i8 %159 to i32
  %161 = or disjoint i32 %158, %160
  %162 = shl nuw nsw i32 %143, 12
  %163 = or disjoint i32 %161, %162
  %164 = icmp samesign ugt i8 %139, -17
  br i1 %164, label %165, label %177

165:                                              ; preds = %154
  %166 = icmp samesign ne i64 %134, 3
  tail call void @llvm.assume(i1 %166)
  %167 = getelementptr inbounds nuw i8, ptr %133, i64 4
  %168 = load i8, ptr %156, align 1, !alias.scope !1937, !noalias !1938, !noundef !31
  %169 = shl nuw nsw i32 %143, 18
  %170 = and i32 %169, 1835008
  %171 = shl nuw nsw i32 %161, 6
  %172 = and i8 %168, 63
  %173 = zext nneg i8 %172 to i32
  %174 = or disjoint i32 %171, %173
  %175 = or disjoint i32 %174, %170
  %176 = icmp eq i32 %175, 1114112
  br i1 %176, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %177

177:                                              ; preds = %165, %154, %152, %141
  %178 = phi i32 [ %175, %165 ], [ %163, %154 ], [ %150, %141 ], [ %153, %152 ]
  %179 = phi ptr [ %167, %165 ], [ %156, %154 ], [ %145, %141 ], [ %138, %152 ]
  %180 = ptrtoint ptr %135 to i64
  %181 = ptrtoint ptr %179 to i64
  %182 = sub nuw i64 %180, %181
  %183 = lshr i64 %182, 2
  %184 = and i64 %182, 3
  %185 = icmp ne i64 %184, 0
  %186 = zext i1 %185 to i64
  %187 = add nuw nsw i64 %183, %186
  %188 = tail call i64 @llvm.umax.i64(i64 %187, i64 3)
  %189 = add nuw nsw i64 %188, 1
  %190 = shl i64 %189, 2
  %191 = icmp samesign ugt i64 %187, 4611686018427387902
  %192 = icmp ugt i64 %190, 9223372036854775804
  %193 = select i1 %191, i1 true, i1 %192, !prof !1219
  br i1 %193, label %.split.i.i.i, label %194, !prof !1219

.split.i.i.i:                                     ; preds = %177
; call alloc::raw_vec::capacity_overflow
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #108, !dbg !1943, !noalias !1945
  unreachable, !dbg !1943

194:                                              ; preds = %177
  %195 = icmp eq i64 %190, 0
  br i1 %195, label %198, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i: ; preds = %194
  %196 = tail call noundef ptr @malloc(i64 noundef range(i64 0, -9223372036854775808) %190) #65, !dbg !1250, !noalias !1946
  %197 = icmp eq ptr %196, null
  br i1 %197, label %.split1.i.i.i, label %198

.split1.i.i.i:                                    ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 4, i64 %190) #105, !noalias !1945
  unreachable

198:                                              ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i, %194
  %199 = phi i64 [ 0, %194 ], [ %189, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i ]
  %200 = phi ptr [ inttoptr (i64 4 to ptr), %194 ], [ %196, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit.i.i.i ]
  %201 = icmp samesign ult i64 %188, %199
  tail call void @llvm.assume(i1 %201)
  store i32 %178, ptr %200, align 4, !noalias !1945
  store i64 %199, ptr %4, align 8, !noalias !1934
  %202 = getelementptr inbounds nuw i8, ptr %4, i64 8
  store ptr %200, ptr %202, align 8, !noalias !1934
  %203 = getelementptr inbounds nuw i8, ptr %4, i64 16
  store i64 1, ptr %203, align 8, !noalias !1934
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1949)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1952)
  %204 = icmp eq ptr %179, %135
  br i1 %204, label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i, label %.preheader409

.preheader409:                                    ; preds = %198, %263
  %205 = phi ptr [ %264, %263 ], [ %200, %198 ]
  %206 = phi i64 [ %266, %263 ], [ 1, %198 ]
  %207 = phi ptr [ %249, %263 ], [ %179, %198 ]
  %208 = getelementptr inbounds nuw i8, ptr %207, i64 1
  %209 = load i8, ptr %207, align 1, !alias.scope !1937, !noalias !1955, !noundef !31
  %210 = icmp sgt i8 %209, -1
  br i1 %210, label %222, label %211

211:                                              ; preds = %.preheader409
  %212 = and i8 %209, 31
  %213 = zext nneg i8 %212 to i32
  %214 = icmp ne ptr %208, %135
  tail call void @llvm.assume(i1 %214)
  %215 = getelementptr inbounds nuw i8, ptr %207, i64 2
  %216 = load i8, ptr %208, align 1, !alias.scope !1937, !noalias !1955, !noundef !31
  %217 = shl nuw nsw i32 %213, 6
  %218 = and i8 %216, 63
  %219 = zext nneg i8 %218 to i32
  %220 = or disjoint i32 %217, %219
  %221 = icmp samesign ugt i8 %209, -33
  br i1 %221, label %224, label %247

222:                                              ; preds = %.preheader409
  %223 = zext nneg i8 %209 to i32
  br label %247

224:                                              ; preds = %211
  %225 = icmp ne ptr %215, %135
  tail call void @llvm.assume(i1 %225)
  %226 = getelementptr inbounds nuw i8, ptr %207, i64 3
  %227 = load i8, ptr %215, align 1, !alias.scope !1937, !noalias !1955, !noundef !31
  %228 = shl nuw nsw i32 %219, 6
  %229 = and i8 %227, 63
  %230 = zext nneg i8 %229 to i32
  %231 = or disjoint i32 %228, %230
  %232 = shl nuw nsw i32 %213, 12
  %233 = or disjoint i32 %231, %232
  %234 = icmp samesign ugt i8 %209, -17
  br i1 %234, label %235, label %247

235:                                              ; preds = %224
  %236 = icmp ne ptr %226, %135
  tail call void @llvm.assume(i1 %236)
  %237 = getelementptr inbounds nuw i8, ptr %207, i64 4
  %238 = load i8, ptr %226, align 1, !alias.scope !1937, !noalias !1955, !noundef !31
  %239 = shl nuw nsw i32 %213, 18
  %240 = and i32 %239, 1835008
  %241 = shl nuw nsw i32 %231, 6
  %242 = and i8 %238, 63
  %243 = zext nneg i8 %242 to i32
  %244 = or disjoint i32 %241, %243
  %245 = or disjoint i32 %244, %240
  %246 = icmp eq i32 %245, 1114112
  br i1 %246, label %268, label %247

247:                                              ; preds = %235, %224, %222, %211
  %248 = phi i32 [ %245, %235 ], [ %233, %224 ], [ %220, %211 ], [ %223, %222 ]
  %249 = phi ptr [ %237, %235 ], [ %226, %224 ], [ %215, %211 ], [ %208, %222 ]
  %250 = icmp samesign ult i64 %206, 2305843009213693952
  tail call void @llvm.assume(i1 %250)
  %251 = load i64, ptr %4, align 8, !range !1117, !alias.scope !1960, !noalias !1934, !noundef !31
  %252 = icmp eq i64 %206, %251
  br i1 %252, label %253, label %263

253:                                              ; preds = %247
  %254 = ptrtoint ptr %249 to i64
  %255 = sub nuw i64 %180, %254
  %256 = lshr i64 %255, 2
  %257 = and i64 %255, 3
  %258 = icmp ne i64 %257, 0
  %259 = zext i1 %258 to i64
  %260 = add nuw nsw i64 %256, 1
  %261 = add nuw nsw i64 %260, %259
; call alloc::raw_vec::RawVecInner<A>::reserve::do_reserve_and_handle
  call fastcc void @"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$7reserve21do_reserve_and_handle17h9d2eedb01691c0ccE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %4, i64 noundef %206, i64 noundef range(i64 1, 0) %261, i64 noundef 4, i64 noundef 4) #65, !noalias !1945
  %262 = load ptr, ptr %202, align 8, !alias.scope !1960, !noalias !1934
  br label %263

263:                                              ; preds = %253, %247
  %264 = phi ptr [ %262, %253 ], [ %205, %247 ]
  %265 = getelementptr inbounds nuw i32, ptr %264, i64 %206
  store i32 %248, ptr %265, align 4, !noalias !1961
  %266 = add nuw nsw i64 %206, 1
  store i64 %266, ptr %203, align 8, !alias.scope !1960, !noalias !1934
  %267 = icmp eq ptr %249, %135
  br i1 %267, label %268, label %.preheader409

268:                                              ; preds = %263, %235
  %269 = phi i64 [ %206, %235 ], [ %266, %263 ]
  %270 = load i64, ptr %4, align 8, !noalias !1962
  %271 = load ptr, ptr %202, align 8, !noalias !1962
  br label %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i

_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i: ; preds = %268, %198, %165, %132
  %272 = phi i64 [ 0, %132 ], [ 0, %165 ], [ %269, %268 ], [ 1, %198 ]
  %273 = phi ptr [ inttoptr (i64 4 to ptr), %132 ], [ inttoptr (i64 4 to ptr), %165 ], [ %271, %268 ], [ %200, %198 ]
  %274 = phi i64 [ 0, %132 ], [ 0, %165 ], [ %270, %268 ], [ %199, %198 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %4), !noalias !1934
  store i64 %274, ptr %7, align 8, !alias.scope !1929, !noalias !1963
  %275 = getelementptr inbounds nuw i8, ptr %7, i64 8
  store ptr %273, ptr %275, align 8, !alias.scope !1929, !noalias !1963
  %276 = getelementptr inbounds nuw i8, ptr %7, i64 16
  store i64 %272, ptr %276, align 8, !alias.scope !1929, !noalias !1963
  %277 = getelementptr inbounds nuw i8, ptr %7, i64 24
  store i64 0, ptr %277, align 8, !alias.scope !1929, !noalias !1963
  call void @llvm.lifetime.start.p0(ptr nonnull %6), !noalias !1927
  store i64 0, ptr %6, align 8, !noalias !1927
  %278 = getelementptr inbounds nuw i8, ptr %6, i64 8
  store ptr inttoptr (i64 8 to ptr), ptr %278, align 8, !noalias !1927
  %279 = getelementptr inbounds nuw i8, ptr %6, i64 16
  store i64 0, ptr %279, align 8, !noalias !1927
  br label %280

280:                                              ; preds = %292, %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i
  %_3.sroa.6.0.copyload = phi ptr [ %293, %292 ], [ inttoptr (i64 8 to ptr), %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i ]
  %_3.sroa.9.0.copyload = phi i64 [ %295, %292 ], [ 0, %_ZN19r7rs_wasm_reference6Reader3new17hd76e5763e74b7b21E.exit.i.i ]
; call r7rs_wasm_reference::Reader::skip_space
  %281 = call fastcc noundef zeroext i1 @_ZN19r7rs_wasm_reference6Reader10skip_space17h8f14cc2594bb2e68E(ptr noalias noundef align 8 dereferenceable(32) %7) #65, !noalias !1964
  br i1 %281, label %287, label %282

282:                                              ; preds = %280
  %_3.sroa.6.0.copyload.lcssa = phi ptr [ %_3.sroa.6.0.copyload, %280 ]
  %_3.sroa.9.0.copyload.lcssa = phi i64 [ %_3.sroa.9.0.copyload, %280 ]
  %_3.sroa.0.0.copyload = load i64, ptr %6, align 8, !noalias !1924
  call void @llvm.lifetime.end.p0(ptr nonnull %6), !noalias !1927
  %283 = load i64, ptr %7, align 8, !range !1117, !noalias !1927, !noundef !31
  %284 = icmp eq i64 %283, 0
  br i1 %284, label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, label %285

285:                                              ; preds = %282
  %286 = load ptr, ptr %275, align 8, !noalias !1927, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %286) #65, !dbg !1104, !noalias !1964
  br label %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i

287:                                              ; preds = %280
  call void @llvm.lifetime.start.p0(ptr nonnull %5), !noalias !1927
; call r7rs_wasm_reference::Reader::datum
  call fastcc void @_ZN19r7rs_wasm_reference6Reader5datum17h7ae745f2407c5577E(ptr noalias noundef align 8 captures(address) dereferenceable(32) %5, ptr noalias noundef align 8 dereferenceable(32) %7) #65, !noalias !1964
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1965)
  %288 = load i64, ptr %6, align 8, !range !1117, !alias.scope !1965, !noalias !1968, !noundef !31
  %289 = icmp eq i64 %_3.sroa.9.0.copyload, %288
  br i1 %289, label %290, label %292

290:                                              ; preds = %287
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h93d0dd34c8f30447E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %6) #103, !noalias !1970
  %291 = load ptr, ptr %278, align 8, !alias.scope !1965, !noalias !1968
  br label %292

292:                                              ; preds = %290, %287
  %293 = phi ptr [ %_3.sroa.6.0.copyload, %287 ], [ %291, %290 ]
  %294 = getelementptr inbounds nuw { i64, [3 x i64] }, ptr %293, i64 %_3.sroa.9.0.copyload
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %294, ptr noundef nonnull readonly align 8 dereferenceable(32) %5, i64 32, i1 false), !noalias !1971
  %295 = add i64 %_3.sroa.9.0.copyload, 1
  store i64 %295, ptr %279, align 8, !alias.scope !1965, !noalias !1968
  call void @llvm.lifetime.end.p0(ptr nonnull %5), !noalias !1927
  br label %280

_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i: ; preds = %285, %282
  call void @llvm.lifetime.end.p0(ptr nonnull %7), !noalias !1927
  %296 = load i64, ptr %11, align 8, !range !1117, !noalias !1458, !noundef !31
  %297 = icmp eq i64 %296, 0
  br i1 %297, label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, label %298

298:                                              ; preds = %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, %129
  %_3.sroa.9.0 = phi i64 [ undef, %129 ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.0 = phi ptr [ %116, %129 ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.0 = phi i64 [ -9223372036854775808, %129 ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %299 = load ptr, ptr %14, align 8, !noalias !1458, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %299) #65, !dbg !1104, !noalias !1458
  br label %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit

_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit: ; preds = %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i, %298
  %_3.sroa.9.1 = phi i64 [ %_3.sroa.9.0, %298 ], [ %_3.sroa.9.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.6.1 = phi ptr [ %_3.sroa.6.0, %298 ], [ %_3.sroa.6.0.copyload.lcssa, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  %_3.sroa.0.1 = phi i64 [ %_3.sroa.0.0, %298 ], [ %_3.sroa.0.0.copyload, %_ZN19r7rs_wasm_reference8read_all17hf96ecfb4d8fe3e14E.exit.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %11), !noalias !1458
  %300 = icmp eq i64 %_3.sroa.0.1, -9223372036854775808
  br i1 %300, label %bb18, label %bb20

bb20:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit
  %_36.not = icmp eq i64 %_3.sroa.9.1, 0
  br i1 %_36.not, label %panic, label %bb21

bb21:                                             ; preds = %bb20
  %301 = icmp ne ptr %_3.sroa.6.1, null
  tail call void @llvm.assume(i1 %301)
; call r7rs_wasm_reference::Datum::number
  %count = tail call fastcc noundef i64 @_ZN19r7rs_wasm_reference5Datum6number17h11d92c433e08e7b1E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %_3.sroa.6.1) #65
  %_44.not = icmp eq i64 %_3.sroa.9.1, 1
  br i1 %_44.not, label %panic1, label %bb22

panic:                                            ; preds = %bb20
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 0, i64 noundef 0, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_5606db56d7e94188a07e3afdc5ee7df8) #104
  unreachable

bb22:                                             ; preds = %bb21
  %_9 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 32
; call r7rs_wasm_reference::Datum::number
  %columns = tail call fastcc noundef i64 @_ZN19r7rs_wasm_reference5Datum6number17h11d92c433e08e7b1E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %_9) #65
  %_49 = icmp ugt i64 %_3.sroa.9.1, 2
  br i1 %_49, label %bb23, label %panic2

panic1:                                           ; preds = %bb21
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 1, i64 noundef 1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_525c3ffbb3f0a811dd0b0ff1cd39e316) #104
  unreachable

bb23:                                             ; preds = %bb22
  %_11 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 64
; call r7rs_wasm_reference::Datum::number
  %inv_size = tail call fastcc noundef i64 @_ZN19r7rs_wasm_reference5Datum6number17h11d92c433e08e7b1E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %_11) #65
  call void @llvm.lifetime.start.p0(ptr nonnull %expected)
  %_54.not = icmp eq i64 %_3.sroa.9.1, 3
  br i1 %_54.not, label %panic3, label %bb24

panic2:                                           ; preds = %bb22
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 2, i64 noundef 2, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_04a966d2cacba0668ab41a18edaf758f) #104
  unreachable

bb24:                                             ; preds = %bb23
  %_13 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 96
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1972)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1975)
  %302 = load i64, ptr %_13, align 8, !range !1103, !alias.scope !1975, !noalias !1972, !noundef !31
  %303 = icmp ne i64 %302, -9223372036854775805
  tail call void @llvm.assume(i1 %303), !noalias !1972
  %304 = xor i64 %302, -9223372036854775808
  %305 = icmp slt i64 %302, 0
  %306 = select i1 %305, i64 %304, i64 3
  switch i64 %306, label %307 [
    i64 2, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit
    i64 4, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit
  ], !prof !1978

307:                                              ; preds = %bb24
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.24, ptr noundef nonnull inttoptr (i64 51 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.25) #104, !noalias !1979
  unreachable

_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit: ; preds = %bb24, %bb24
  %308 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 112
  %309 = load ptr, ptr %308, align 8, !alias.scope !1975, !noalias !1972, !nonnull !31, !noundef !31
  %310 = getelementptr inbounds nuw i8, ptr %_3.sroa.6.1, i64 120
  %311 = load i64, ptr %310, align 8, !alias.scope !1975, !noalias !1972, !noundef !31
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1980)
  %312 = shl nuw nsw i64 %311, 4
  %313 = icmp eq i64 %311, 0
  br i1 %313, label %_ZN6matrix8expected17ha0f4d82318fbb241E.exit, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit:  ; preds = %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit
  %314 = tail call noundef ptr @malloc(i64 noundef range(i64 0, 9223372036854775801) %312) #65, !dbg !1250, !noalias !1983
  %315 = icmp eq ptr %314, null
  br i1 %315, label %bb3.i.i.i.i.i, label %bb8.i.i.i.i.i.i.i.i.i

bb3.i.i.i.i.i:                                    ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 8, i64 %312) #105, !noalias !1990
  unreachable

bb8.i.i.i.i.i.i.i.i.i:                            ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit, %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i"
  %316 = phi i64 [ %459, %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i" ], [ 0, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit ]
  %_45.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %309, i64 %316
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1991)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1994)
  %317 = load i64, ptr %_45.i.i.i.i.i.i.i.i.i, align 8, !range !1103, !alias.scope !1997, !noalias !1998, !noundef !31
  %318 = icmp ne i64 %317, -9223372036854775805
  tail call void @llvm.assume(i1 %318)
  %319 = icmp eq i64 %317, -9223372036854775807
  %320 = getelementptr inbounds nuw i8, ptr %_45.i.i.i.i.i.i.i.i.i, i64 24
  %_14.i.i.i.i.i.i.i.i.i.i.i = load i64, ptr %320, align 8, !alias.scope !1997, !noalias !1998
  %_19.i.i.i.i.i.i.i.i.i.i.i = icmp eq i64 %_14.i.i.i.i.i.i.i.i.i.i.i, 3
  %or.cond.i.i.i.i.i.i.i.i.i.i.i = select i1 %319, i1 %_19.i.i.i.i.i.i.i.i.i.i.i, i1 false
  br i1 %or.cond.i.i.i.i.i.i.i.i.i.i.i, label %bb7.i.i.i.i.i.i.i.i.i.i.i, label %bb1.i.i.i.i.i.i.i.i.i.i.i

bb1.i.i.i.i.i.i.i.i.i.i.i:                        ; preds = %bb7.i.i.i.i.i.i.i.i.i.i.i, %bb8.i.i.i.i.i.i.i.i.i
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2010)
  %321 = xor i64 %317, -9223372036854775808
  %322 = icmp slt i64 %317, 0
  %323 = select i1 %322, i64 %321, i64 3
  switch i64 %323, label %324 [
    i64 2, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235
    i64 4, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235
  ], !prof !1978

324:                                              ; preds = %bb1.i.i.i.i.i.i.i.i.i.i.i
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.24, ptr noundef nonnull inttoptr (i64 51 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.25) #104, !noalias !2013
  unreachable

_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235: ; preds = %bb1.i.i.i.i.i.i.i.i.i.i.i, %bb1.i.i.i.i.i.i.i.i.i.i.i
  %325 = getelementptr inbounds nuw i8, ptr %_45.i.i.i.i.i.i.i.i.i, i64 16
  %326 = load ptr, ptr %325, align 8, !alias.scope !2010, !noalias !1998, !nonnull !31, !noundef !31
  %327 = icmp eq i64 %_14.i.i.i.i.i.i.i.i.i.i.i, 0
  br i1 %327, label %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i", label %bb3.i.preheader.i.i.i.i.i.i.i.i.i.i.i.i

bb3.i.preheader.i.i.i.i.i.i.i.i.i.i.i.i:          ; preds = %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235
  %_8.idx.i.i.i.i.i.i.i.i.i.i.i.i = shl nuw nsw i64 %_14.i.i.i.i.i.i.i.i.i.i.i, 5
  %_8.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %326, i64 %_8.idx.i.i.i.i.i.i.i.i.i.i.i.i
  br label %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i

bb3.i.i.i.i.i.i.i.i.i.i.i.i.i:                    ; preds = %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i", %bb3.i.preheader.i.i.i.i.i.i.i.i.i.i.i.i
  %accum.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ %454, %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i" ], [ null, %bb3.i.preheader.i.i.i.i.i.i.i.i.i.i.i.i ]
  %self.sroa.2.010.i.i.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i, %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i" ], [ %_8.i.i.i.i.i.i.i.i.i.i.i.i, %bb3.i.preheader.i.i.i.i.i.i.i.i.i.i.i.i ]
  %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds i8, ptr %self.sroa.2.010.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 -32
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2014)
  %328 = load i64, ptr %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !range !1103, !alias.scope !2014, !noalias !1998, !noundef !31
  %329 = icmp ne i64 %328, -9223372036854775805
  tail call void @llvm.assume(i1 %329), !noalias !1998
  %330 = xor i64 %328, -9223372036854775808
  %331 = icmp slt i64 %328, 0
  %332 = select i1 %331, i64 %330, i64 3
  switch i64 %332, label %333 [
    i64 2, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236
    i64 4, label %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236
  ], !prof !1978

333:                                              ; preds = %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.24, ptr noundef nonnull inttoptr (i64 51 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.25) #104, !noalias !2017
  unreachable

_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236: ; preds = %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i, %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i
  %334 = getelementptr inbounds i8, ptr %self.sroa.2.010.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 -16
  %335 = load ptr, ptr %334, align 8, !alias.scope !2014, !noalias !1998, !nonnull !31, !noundef !31
  %336 = getelementptr inbounds i8, ptr %self.sroa.2.010.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 -8
  %337 = load i64, ptr %336, align 8, !alias.scope !2014, !noalias !1998, !noundef !31
  %338 = shl nuw i64 %337, 3
  %339 = icmp eq i64 %337, 0
  br i1 %339, label %_ZN6matrix8row_from17h788ec0d1828b6a6eE.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238: ; preds = %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236
  %340 = tail call noundef ptr @malloc(i64 noundef range(i64 0, 9223372036854775801) %338) #65, !dbg !1250, !noalias !2018
  %341 = icmp eq ptr %340, null
  br i1 %341, label %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %bb8.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i

bb3.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i:              ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238
  %.lcssa659 = phi i64 [ %338, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238 ]
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 8, i64 %.lcssa659) #105, !noalias !2023
  unreachable

bb8.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i:      ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238, %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit
  %342 = phi i64 [ %449, %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit ], [ 0, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit238 ]
  %_45.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %335, i64 %342
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2024)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2027), !noalias !2030
  %343 = load i64, ptr %_45.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !range !1103, !alias.scope !2043, !noalias !2030, !noundef !31
  %344 = icmp ne i64 %343, -9223372036854775805
  tail call void @llvm.assume(i1 %344), !noalias !2030
  %345 = icmp slt i64 %343, -9223372036854775806
  br i1 %345, label %347, label %346, !prof !2044

346:                                              ; preds = %bb8.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i
; call core::panicking::panic_fmt
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.d3ffb10234040c548dbe347741c6fc8a.21, ptr noundef nonnull inttoptr (i64 53 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.23) #104, !noalias !2045
  unreachable

347:                                              ; preds = %bb8.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  %348 = getelementptr inbounds nuw i8, ptr %_45.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 16
  %349 = load ptr, ptr %348, align 8, !alias.scope !2043, !noalias !2030, !nonnull !31, !noundef !31
  %350 = getelementptr inbounds nuw i8, ptr %_45.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 24
  %351 = load i64, ptr %350, align 8, !alias.scope !2043, !noalias !2030, !noundef !31
  switch i64 %351, label %354 [
    i64 0, label %.loopexit
    i64 1, label %352
  ]

352:                                              ; preds = %347
  %353 = load i8, ptr %349, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  switch i8 %353, label %356 [
    i8 43, label %.loopexit
    i8 45, label %.loopexit
  ]

354:                                              ; preds = %347
  %355 = load i8, ptr %349, align 1, !alias.scope !2046, !noalias !2049
  br label %356

356:                                              ; preds = %354, %352
  %357 = phi i8 [ %355, %354 ], [ %353, %352 ]
  switch i8 %357, label %401 [
    i8 43, label %358
    i8 45, label %361
  ]

358:                                              ; preds = %356
  %359 = getelementptr inbounds nuw i8, ptr %349, i64 1
  %360 = add nsw i64 %351, -1
  br label %401

361:                                              ; preds = %356
  %362 = getelementptr inbounds nuw i8, ptr %349, i64 1
  %363 = add nsw i64 %351, -1
  %364 = icmp samesign ult i64 %351, 17
  br i1 %364, label %365, label %.preheader402

365:                                              ; preds = %361
  %366 = icmp eq i64 %363, 0
  br i1 %366, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader399

.preheader402:                                    ; preds = %361, %384
  %367 = phi ptr [ %370, %384 ], [ %362, %361 ]
  %368 = phi i64 [ %371, %384 ], [ %363, %361 ]
  %369 = phi i64 [ %385, %384 ], [ 0, %361 ]
  %370 = getelementptr inbounds nuw i8, ptr %367, i64 1
  %371 = add nsw i64 %368, -1
  %372 = tail call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %369, i64 10)
  %373 = extractvalue { i64, i1 } %372, 0
  %374 = extractvalue { i64, i1 } %372, 1
  br i1 %374, label %.loopexit396, label %375, !prof !1319

375:                                              ; preds = %.preheader402
  %376 = load i8, ptr %367, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  %377 = zext i8 %376 to i32
  %378 = add nsw i32 %377, -48
  %379 = icmp ult i32 %378, 10
  br i1 %379, label %380, label %.loopexit

380:                                              ; preds = %375
  %381 = zext nneg i32 %378 to i64
  %382 = tail call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 %373, i64 %381)
  %383 = extractvalue { i64, i1 } %382, 1
  br i1 %383, label %.loopexit, label %384, !prof !1319

384:                                              ; preds = %380
  %385 = extractvalue { i64, i1 } %382, 0
  %386 = icmp eq i64 %371, 0
  br i1 %386, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader402

.preheader399:                                    ; preds = %365, %394
  %387 = phi ptr [ %397, %394 ], [ %362, %365 ]
  %388 = phi i64 [ %396, %394 ], [ %363, %365 ]
  %389 = phi i64 [ %399, %394 ], [ 0, %365 ]
  %390 = load i8, ptr %387, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  %391 = zext i8 %390 to i32
  %392 = add nsw i32 %391, -48
  %393 = icmp ult i32 %392, 10
  br i1 %393, label %394, label %.loopexit

394:                                              ; preds = %.preheader399
  %395 = mul i64 %389, 10
  %396 = add nsw i64 %388, -1
  %397 = getelementptr inbounds nuw i8, ptr %387, i64 1
  %398 = zext nneg i32 %392 to i64
  %399 = sub i64 %395, %398
  %400 = icmp eq i64 %396, 0
  br i1 %400, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader399

401:                                              ; preds = %358, %356
  %402 = phi i64 [ %360, %358 ], [ %351, %356 ]
  %403 = phi ptr [ %359, %358 ], [ %349, %356 ]
  %404 = icmp samesign ult i64 %402, 16
  br i1 %404, label %405, label %.preheader395

405:                                              ; preds = %401
  %406 = icmp eq i64 %402, 0
  br i1 %406, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader

.preheader395:                                    ; preds = %401, %424
  %407 = phi ptr [ %410, %424 ], [ %403, %401 ]
  %408 = phi i64 [ %411, %424 ], [ %402, %401 ]
  %409 = phi i64 [ %425, %424 ], [ 0, %401 ]
  %410 = getelementptr inbounds nuw i8, ptr %407, i64 1
  %411 = add nsw i64 %408, -1
  %412 = tail call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %409, i64 10)
  %413 = extractvalue { i64, i1 } %412, 0
  %414 = extractvalue { i64, i1 } %412, 1
  br i1 %414, label %.loopexit396, label %415, !prof !1319

415:                                              ; preds = %.preheader395
  %416 = load i8, ptr %407, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  %417 = zext i8 %416 to i32
  %418 = add nsw i32 %417, -48
  %419 = icmp ult i32 %418, 10
  br i1 %419, label %420, label %.loopexit

420:                                              ; preds = %415
  %421 = zext nneg i32 %418 to i64
  %422 = tail call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %413, i64 %421)
  %423 = extractvalue { i64, i1 } %422, 1
  br i1 %423, label %.loopexit, label %424, !prof !1319

424:                                              ; preds = %420
  %425 = extractvalue { i64, i1 } %422, 0
  %426 = icmp eq i64 %411, 0
  br i1 %426, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader395

.preheader:                                       ; preds = %405, %434
  %427 = phi ptr [ %437, %434 ], [ %403, %405 ]
  %428 = phi i64 [ %436, %434 ], [ %402, %405 ]
  %429 = phi i64 [ %439, %434 ], [ 0, %405 ]
  %430 = load i8, ptr %427, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  %431 = zext i8 %430 to i32
  %432 = add nsw i32 %431, -48
  %433 = icmp ult i32 %432, 10
  br i1 %433, label %434, label %.loopexit

434:                                              ; preds = %.preheader
  %435 = mul i64 %429, 10
  %436 = add nsw i64 %428, -1
  %437 = getelementptr inbounds nuw i8, ptr %427, i64 1
  %438 = zext nneg i32 %432 to i64
  %439 = add i64 %435, %438
  %440 = icmp eq i64 %436, 0
  br i1 %440, label %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit, label %.preheader

.loopexit396:                                     ; preds = %.preheader402, %.preheader395
  %441 = phi ptr [ %407, %.preheader395 ], [ %367, %.preheader402 ]
  %442 = phi i8 [ 2, %.preheader395 ], [ 3, %.preheader402 ]
  %443 = load i8, ptr %441, align 1, !alias.scope !2046, !noalias !2049, !noundef !31
  %444 = add i8 %443, -48
  %445 = icmp ult i8 %444, 10
  %446 = select i1 %445, i8 %442, i8 1
  br label %.loopexit

.loopexit:                                        ; preds = %352, %352, %347, %380, %375, %.preheader399, %420, %415, %.preheader, %.loopexit396
  %447 = phi i8 [ 3, %380 ], [ %446, %.loopexit396 ], [ 2, %420 ], [ 1, %.preheader399 ], [ 1, %.preheader ], [ 1, %415 ], [ 1, %375 ], [ 1, %352 ], [ 0, %347 ], [ 1, %352 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %3), !noalias !2051
  store i8 %447, ptr %3, align 1, !noalias !2051
; call core::result::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6result13unwrap_failed(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @anon.d3ffb10234040c548dbe347741c6fc8a.30, i64 noundef 19, ptr noundef nonnull align 1 %3, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) @anon.d3ffb10234040c548dbe347741c6fc8a.100, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @anon.d3ffb10234040c548dbe347741c6fc8a.31) #104, !noalias !2051
  unreachable

_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit: ; preds = %384, %394, %424, %434, %365, %405
  %448 = phi i64 [ %439, %434 ], [ %399, %394 ], [ %425, %424 ], [ 0, %405 ], [ 0, %365 ], [ %385, %384 ]
  %_3.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i64, ptr %340, i64 %342
  store i64 %448, ptr %_3.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !2054
  %449 = add nuw i64 %342, 1
  %_28.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = icmp eq i64 %449, %337
  br i1 %_28.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h7dfea6774dde3d73E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i", label %bb8.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i

"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h7dfea6774dde3d73E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i": ; preds = %_ZN19r7rs_wasm_reference5Datum7integer17h31f269bb5b01cdcdE.exit
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2059)
  %_7.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %340, i64 %338
  br label %bb3.i.i2.i.i.i.i.i.i.i.i.i.i.i.i.i.i

bb3.i.i2.i.i.i.i.i.i.i.i.i.i.i.i.i.i:             ; preds = %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i", %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h7dfea6774dde3d73E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i"
  %accum.sroa.0.06.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ %450, %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ], [ null, %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h7dfea6774dde3d73E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %self.sroa.2.05.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ], [ %_7.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h7dfea6774dde3d73E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds i8, ptr %self.sroa.2.05.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, i64 -8
  %.val.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = load i64, ptr %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !alias.scope !2059, !noalias !1998, !noundef !31
  %450 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2062
  %451 = icmp eq ptr %450, null
  br i1 %451, label %bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i", !prof !1319

bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i:        ; preds = %bb3.i.i2.i.i.i.i.i.i.i.i.i.i.i.i.i.i
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2062
  unreachable

"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i": ; preds = %bb3.i.i2.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  store i64 1, ptr %450, align 8, !noalias !2065
  %_7.sroa.4.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %450, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !2065
  %_7.sroa.5.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %450, i64 16
  store i64 %.val.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, ptr %_7.sroa.5.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !2065
  %_7.sroa.6.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %450, i64 24
  store ptr %accum.sroa.0.06.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, ptr %_7.sroa.6.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !2065
  %452 = icmp eq ptr %340, %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  br i1 %452, label %_ZN6matrix8row_from17h788ec0d1828b6a6eE.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %bb3.i.i2.i.i.i.i.i.i.i.i.i.i.i.i.i.i

_ZN6matrix8row_from17h788ec0d1828b6a6eE.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i: ; preds = %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i", %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236
  %453 = phi ptr [ inttoptr (i64 8 to ptr), %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236 ], [ %340, %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %accum.sroa.0.0.lcssa.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ null, %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit236 ], [ %450, %"_ZN6matrix8row_from28_$u7b$$u7b$closure$u7d$$u7d$17h630dc1ec684d42a9E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %454 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2066
  %455 = icmp eq ptr %454, null
  br i1 %455, label %bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i, !prof !1319

bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i:              ; preds = %_ZN6matrix8row_from17h788ec0d1828b6a6eE.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2066
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i: ; preds = %_ZN6matrix8row_from17h788ec0d1828b6a6eE.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  store i64 1, ptr %454, align 8, !noalias !1998
  %_7.sroa.4.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %454, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !1998
  %_7.sroa.5.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %454, i64 16
  store ptr %accum.sroa.0.0.lcssa.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, ptr %_7.sroa.5.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !1998
  %_7.sroa.6.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %454, i64 24
  store ptr %accum.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i.i.i, ptr %_7.sroa.6.0..sroa_idx.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !1998
  br i1 %339, label %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i", label %bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i:          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  tail call void @free(ptr noundef nonnull %453) #65, !dbg !1104
  br label %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i"

"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i": ; preds = %bb2.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i.i, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  %456 = icmp eq ptr %326, %_23.i.i.i.i.i.i.i.i.i.i.i.i.i.i
  br i1 %456, label %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i", label %bb3.i.i.i.i.i.i.i.i.i.i.i.i.i

bb7.i.i.i.i.i.i.i.i.i.i.i:                        ; preds = %bb8.i.i.i.i.i.i.i.i.i
  %457 = getelementptr inbounds nuw i8, ptr %_45.i.i.i.i.i.i.i.i.i, i64 16
  %_15.i.i.i.i.i.i.i.i.i.i.i = load ptr, ptr %457, align 8, !alias.scope !1997, !noalias !1998, !nonnull !31, !noundef !31
  %bcmp.i.i.i.i.i.i.i.i.i.i.i = tail call i32 @bcmp(ptr noundef nonnull dereferenceable(3) %_15.i.i.i.i.i.i.i.i.i.i.i, ptr noundef nonnull dereferenceable(3) @anon.5e37b2a355f3f40f4a08b3a945a506d5.102, i64 3), !noalias !2069
  %_6.i.i.i.i.i.i.i.i.i.i.i = icmp eq i32 %bcmp.i.i.i.i.i.i.i.i.i.i.i, 0
  br i1 %_6.i.i.i.i.i.i.i.i.i.i.i, label %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i", label %bb1.i.i.i.i.i.i.i.i.i.i.i

"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i": ; preds = %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i", %bb7.i.i.i.i.i.i.i.i.i.i.i, %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235
  %_0.sroa.3.0.i.i.i.i.i.i.i.i.i.i.i = phi ptr [ undef, %bb7.i.i.i.i.i.i.i.i.i.i.i ], [ null, %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235 ], [ %454, %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %_0.sroa.0.0.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ 1, %bb7.i.i.i.i.i.i.i.i.i.i.i ], [ 0, %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit235 ], [ 0, %"_ZN6matrix12parse_matrix28_$u7b$$u7b$closure$u7d$$u7d$17h99b07918dd7ac560E.exit.i.i.i.i.i.i.i.i.i.i.i.i.i" ]
  %_3.i.i.i.i.i.i.i.i.i.i.i.i = getelementptr inbounds nuw %Answer, ptr %314, i64 %316
  store i64 %_0.sroa.0.0.i.i.i.i.i.i.i.i.i.i.i, ptr %_3.i.i.i.i.i.i.i.i.i.i.i.i, align 8, !noalias !2070
  %458 = getelementptr inbounds nuw i8, ptr %_3.i.i.i.i.i.i.i.i.i.i.i.i, i64 8
  store ptr %_0.sroa.3.0.i.i.i.i.i.i.i.i.i.i.i, ptr %458, align 8, !noalias !2070
  %459 = add nuw i64 %316, 1
  %_28.i.i.i.i.i.i.i.i.i = icmp eq i64 %459, %311
  br i1 %_28.i.i.i.i.i.i.i.i.i, label %_ZN6matrix8expected17ha0f4d82318fbb241E.exit, label %bb8.i.i.i.i.i.i.i.i.i

_ZN6matrix8expected17ha0f4d82318fbb241E.exit:     ; preds = %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i", %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit
  %460 = phi ptr [ inttoptr (i64 8 to ptr), %_ZN19r7rs_wasm_reference5Datum4list17h5ac791937d525c31E.exit ], [ %314, %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h7357694e1217f3ecE.exit.i.i.i.i.i.i.i.i.i" ]
  %461 = getelementptr inbounds nuw i8, ptr %expected, i64 16
  store i64 0, ptr %461, align 8, !alias.scope !2075, !noalias !2076
  %462 = getelementptr inbounds nuw i8, ptr %expected, i64 24
  store i64 %311, ptr %462, align 8, !alias.scope !2075, !noalias !2076
  store i64 %311, ptr %expected, align 8, !alias.scope !2075, !noalias !2076
  %463 = getelementptr inbounds nuw i8, ptr %expected, i64 8
  store ptr %460, ptr %463, align 8, !alias.scope !2075, !noalias !2076
; call <std::sys::pal::unix::time::Timespec>::now
  %464 = tail call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #65, !dbg !2078
  %start.0 = extractvalue { i64, i32 } %464, 0
  %start.1 = extractvalue { i64, i32 } %464, 1
  call void @llvm.lifetime.start.p0(ptr nonnull %result)
  store i64 0, ptr %result, align 8
  %_16.sroa.2.0.result.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 8
  store ptr inttoptr (i64 8 to ptr), ptr %_16.sroa.2.0.result.sroa_idx, align 8
  %_16.sroa.3.0.result.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 16
  %_16.sroa.4.0.result.sroa_idx = getelementptr inbounds nuw i8, ptr %result, i64 24
  %_5547.not = icmp eq i64 %count, 0
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %_16.sroa.3.0.result.sroa_idx, i8 0, i64 16, i1 false)
  br i1 %_5547.not, label %bb26, label %bb25.lr.ph

bb25.lr.ph:                                       ; preds = %_ZN6matrix8expected17ha0f4d82318fbb241E.exit
  %_4.sroa.2.0.primes.sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %primes.i.i.i, i64 8
  %_4.sroa.3.0.primes.sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %primes.i.i.i, i64 16
  %465 = getelementptr inbounds nuw i8, ptr %field.i, i64 24
  %_4.sroa.4.0._0.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %field.i, i64 8
  %_4.sroa.5.0._0.sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %field.i, i64 16
  %466 = getelementptr inbounds nuw i8, ptr %_6.i.i, i64 8
  %467 = getelementptr inbounds nuw i8, ptr %_6.i.i, i64 16
  %468 = getelementptr inbounds nuw i8, ptr %best.i, i64 32
  %469 = getelementptr inbounds nuw i8, ptr %best.i, i64 40
  %_11.sroa.4.0.best.sroa_idx.i = getelementptr inbounds nuw i8, ptr %best.i, i64 8
  %_11.sroa.5.0.best.sroa_idx.i = getelementptr inbounds nuw i8, ptr %best.i, i64 16
  br label %bb25

panic3:                                           ; preds = %bb23
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef 3, i64 noundef 3, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_5b3735abcb2a34fe43311271dbfb3574) #104
  unreachable

bb26.loopexit:                                    ; preds = %_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit
  %_4.i.pre = load i64, ptr %_16.sroa.4.0.result.sroa_idx, align 8, !alias.scope !2089, !noalias !2092
  br label %bb26

bb26:                                             ; preds = %bb26.loopexit, %_ZN6matrix8expected17ha0f4d82318fbb241E.exit
  %_4.i = phi i64 [ %_4.i.pre, %bb26.loopexit ], [ 0, %_ZN6matrix8expected17ha0f4d82318fbb241E.exit ]
  call void @llvm.experimental.noalias.scope.decl(metadata !2089)
  %_3.not.i = icmp eq i64 %_4.i, %311
  br i1 %_3.not.i, label %bb2.i, label %bb13, !prof !2094

bb2.i:                                            ; preds = %bb26
  br i1 %313, label %bb12, label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$12slice_ranges17hbde585cf9cb83bbaE.exit25.i"

"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$12slice_ranges17hbde585cf9cb83bbaE.exit25.i": ; preds = %bb2.i
  %self.val.i = load i64, ptr %result, align 8, !alias.scope !2089, !noalias !2092
  %self.val14.i = load i64, ptr %_16.sroa.3.0.result.sroa_idx, align 8, !alias.scope !2089, !noalias !2092
  %_27.not.i.i = icmp ult i64 %self.val14.i, %self.val.i
  %470 = select i1 %_27.not.i.i, i64 0, i64 %self.val.i
  %wrapped_start.sroa.0.0.i.i = sub nuw i64 %self.val14.i, %470
  %head_len.i.i = sub i64 %self.val.i, %wrapped_start.sroa.0.0.i.i
  %_13.not.i.i = icmp ult i64 %head_len.i.i, %311
  %_16.i.i = add i64 %wrapped_start.sroa.0.0.i.i, %311
  %_61.sroa.11.0.ph.i = call i64 @llvm.usub.sat.i64(i64 %311, i64 %head_len.i.i)
  %_61.sroa.5.0.ph.i = select i1 %_13.not.i.i, i64 %self.val.i, i64 %_16.i.i
  %_7056.i = load ptr, ptr %_16.sroa.2.0.result.sroa_idx, align 8, !alias.scope !2089, !noalias !2092, !nonnull !31, !noundef !31
  %_6757.i = getelementptr inbounds nuw %Answer, ptr %_7056.i, i64 %wrapped_start.sroa.0.0.i.i
  %front58.i = sub i64 %_61.sroa.5.0.ph.i, %wrapped_start.sroa.0.0.i.i
  %_6.i = icmp eq i64 %front58.i, %311
  br i1 %_6.i, label %bb2.i239, label %bb7.i

bb2.i239:                                         ; preds = %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$12slice_ranges17hbde585cf9cb83bbaE.exit25.i", %bb5.i
  %idx.sroa.0.024.i = phi i64 [ %489, %bb5.i ], [ 0, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$12slice_ranges17hbde585cf9cb83bbaE.exit25.i" ]
  %_9.i = getelementptr inbounds nuw %Answer, ptr %_6757.i, i64 %idx.sroa.0.024.i
  %_12.i240 = getelementptr inbounds nuw %Answer, ptr %460, i64 %idx.sroa.0.024.i
  %_9.val.i = load i64, ptr %_9.i, align 8, !range !954, !noalias !2095, !noundef !31
  %471 = getelementptr i8, ptr %_9.i, i64 8
  %_9.val5.i = load ptr, ptr %471, align 8, !noalias !2095
  %_12.val.i = load i64, ptr %_12.i240, align 8, !range !954, !noalias !2095, !noundef !31
  %472 = getelementptr i8, ptr %_12.i240, i64 8
  %_12.val6.i = load ptr, ptr %472, align 8, !noalias !2095
  %_5.i.i.i = icmp eq i64 %_9.val.i, %_12.val.i
  br i1 %_5.i.i.i, label %bb1.i.i.i242, label %bb13

bb1.i.i.i242:                                     ; preds = %bb2.i239
  %or.cond.not.i.i.i = icmp eq i64 %_9.val.i, 0
  br i1 %or.cond.not.i.i.i, label %bb5.i.i.i243, label %bb5.i

bb5.i.i.i243:                                     ; preds = %bb1.i.i.i242
  %.not.i.i.i = icmp eq ptr %_9.val5.i, null
  %473 = icmp eq ptr %_12.val6.i, null
  %brmerge.i.i.i = select i1 %.not.i.i.i, i1 true, i1 %473
  br i1 %brmerge.i.i.i, label %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i, label %bb12.i.i.i

bb12.i.i.i:                                       ; preds = %bb5.i.i.i243
  %_11.i.i.i244 = icmp eq ptr %_9.val5.i, %_12.val6.i
  br i1 %_11.i.i.i244, label %bb5.i, label %tailrecurse.i.i.i.i

tailrecurse.i.i.i.i:                              ; preds = %bb12.i.i.i, %bb17.i.i.i.i
  %self.8.val.pn.i.i.i = phi ptr [ %485, %bb17.i.i.i.i ], [ %_9.val5.i, %bb12.i.i.i ]
  %other.8.val.pn.i.i.i = phi ptr [ %487, %bb17.i.i.i.i ], [ %_12.val6.i, %bb12.i.i.i ]
  %other.tr.i.i.i.i = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i, i64 16
  %self.tr.i.i.i.i = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i, i64 16
  %474 = load ptr, ptr %self.tr.i.i.i.i, align 8, !noalias !2096, !noundef !31
  %.not.i.i.i.i245 = icmp eq ptr %474, null
  %475 = load ptr, ptr %other.tr.i.i.i.i, align 8, !noalias !2099, !noundef !31
  %476 = icmp eq ptr %475, null
  br i1 %.not.i.i.i.i245, label %bb4.i.i.i.i, label %bb6.i.i.i.i

bb6.i.i.i.i:                                      ; preds = %tailrecurse.i.i.i.i
  br i1 %476, label %bb13, label %bb9.i.i.i.i

bb4.i.i.i.i:                                      ; preds = %tailrecurse.i.i.i.i
  br i1 %476, label %bb1.i.i.i.i249, label %bb13

bb9.i.i.i.i:                                      ; preds = %bb6.i.i.i.i
  %_7.i.i.i.i246 = icmp eq ptr %474, %475
  br i1 %_7.i.i.i.i246, label %bb1.i.i.i.i249, label %bb11.i.i.i.i247

bb11.i.i.i.i247:                                  ; preds = %bb9.i.i.i.i
  %_8.i.i.i.i = getelementptr inbounds nuw i8, ptr %474, i64 16
  %_9.i.i.i.i = getelementptr inbounds nuw i8, ptr %475, i64 16
  call void @llvm.experimental.noalias.scope.decl(metadata !2101), !noalias !2095
  call void @llvm.experimental.noalias.scope.decl(metadata !2104), !noalias !2095
  %_44.i.i.i.i.i = load i64, ptr %_8.i.i.i.i, align 8, !alias.scope !2101, !noalias !2106, !noundef !31
  %_55.i.i.i.i.i = load i64, ptr %_9.i.i.i.i, align 8, !alias.scope !2104, !noalias !2107, !noundef !31
  %_36.i.i.i.i.i = icmp eq i64 %_44.i.i.i.i.i, %_55.i.i.i.i.i
  br i1 %_36.i.i.i.i.i, label %bb1.i.i.i.i.i, label %bb13

bb1.i.i.i.i.i:                                    ; preds = %bb11.i.i.i.i247, %bb11.i.i.i.i.i
  %477 = phi ptr [ %482, %bb11.i.i.i.i.i ], [ %475, %bb11.i.i.i.i247 ]
  %478 = phi ptr [ %480, %bb11.i.i.i.i.i ], [ %474, %bb11.i.i.i.i247 ]
  %479 = getelementptr inbounds nuw i8, ptr %478, i64 24
  %480 = load ptr, ptr %479, align 8, !noalias !2106, !noundef !31
  %.not.i.i.i.i.i248 = icmp eq ptr %480, null
  %481 = getelementptr inbounds nuw i8, ptr %477, i64 24
  %482 = load ptr, ptr %481, align 8, !noalias !2107, !noundef !31
  %483 = icmp eq ptr %482, null
  br i1 %.not.i.i.i.i.i248, label %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i", label %bb6.i.i.i.i.i

bb6.i.i.i.i.i:                                    ; preds = %bb1.i.i.i.i.i
  br i1 %483, label %bb13, label %bb9.i.i.i.i.i

bb9.i.i.i.i.i:                                    ; preds = %bb6.i.i.i.i.i
  %_9.i.i.i.i.i = icmp eq ptr %480, %482
  br i1 %_9.i.i.i.i.i, label %bb1.i.i.i.i249, label %bb11.i.i.i.i.i

bb11.i.i.i.i.i:                                   ; preds = %bb9.i.i.i.i.i
  %_10.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %480, i64 16
  %_11.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %482, i64 16
  %_4.i.i.i.i.i = load i64, ptr %_10.i.i.i.i.i, align 8, !noalias !2108, !noundef !31
  %_5.i.i.i.i.i = load i64, ptr %_11.i.i.i.i.i, align 8, !noalias !2108, !noundef !31
  %_3.i.i.i.i.i = icmp eq i64 %_4.i.i.i.i.i, %_5.i.i.i.i.i
  br i1 %_3.i.i.i.i.i, label %bb1.i.i.i.i.i, label %bb13

"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i": ; preds = %bb1.i.i.i.i.i
  br i1 %483, label %bb1.i.i.i.i249, label %bb13

bb1.i.i.i.i249:                                   ; preds = %bb9.i.i.i.i.i, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i", %bb9.i.i.i.i, %bb4.i.i.i.i
  %484 = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i, i64 24
  %485 = load ptr, ptr %484, align 8, !noalias !2096, !noundef !31
  %.not5.i.i.i.i = icmp eq ptr %485, null
  %486 = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i, i64 24
  %487 = load ptr, ptr %486, align 8, !noalias !2099, !noundef !31
  %488 = icmp eq ptr %487, null
  br i1 %.not5.i.i.i.i, label %bb15.i.i.i.i250, label %bb14.i.i.i.i

bb14.i.i.i.i:                                     ; preds = %bb1.i.i.i.i249
  br i1 %488, label %bb13, label %bb17.i.i.i.i

bb15.i.i.i.i250:                                  ; preds = %bb1.i.i.i.i249
  br i1 %488, label %bb5.i, label %bb13

bb17.i.i.i.i:                                     ; preds = %bb14.i.i.i.i
  %_19.i.i.i.i = icmp eq ptr %485, %487
  br i1 %_19.i.i.i.i, label %bb5.i, label %tailrecurse.i.i.i.i

_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i: ; preds = %bb5.i.i.i243
  %.mux.i.i.i = select i1 %.not.i.i.i, i1 %473, i1 false
  br i1 %.mux.i.i.i, label %bb5.i, label %bb13

bb5.i:                                            ; preds = %bb17.i.i.i.i, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i, %bb15.i.i.i.i250, %bb12.i.i.i, %bb1.i.i.i242
  %489 = add nuw i64 %idx.sroa.0.024.i, 1
  %exitcond.not.i = icmp eq i64 %489, %311
  br i1 %exitcond.not.i, label %bb3.i, label %bb2.i239

bb7.i:                                            ; preds = %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$12slice_ranges17hbde585cf9cb83bbaE.exit25.i"
  %_12.i = icmp ult i64 %front58.i, %311
  br i1 %_12.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$8split_at17h6d8d762edb74345bE.exit42.i", label %bb3.i33.i

bb3.i:                                            ; preds = %bb5.i
  %.not = icmp ugt i64 %311, %head_len.i.i
  br i1 %.not, label %bb13, label %bb12, !prof !2109

bb3.i33.i:                                        ; preds = %bb7.i
; call core::panicking::panic_fmt
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.eb89d4395b0ead844ef0b45b8b54da85.153, ptr noundef nonnull inttoptr (i64 19 to ptr), ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_8ace4a25485a756132703324c6846033) #104, !noalias !2110
  unreachable

"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$8split_at17h6d8d762edb74345bE.exit42.i": ; preds = %bb7.i
  %mid8.i = sub nuw i64 %311, %front58.i
  %data.i.i36.i = getelementptr inbounds nuw %Answer, ptr %460, i64 %front58.i
  %_6.not.i43.i = icmp ugt i64 %mid8.i, %_61.sroa.11.0.ph.i
  br i1 %_6.not.i43.i, label %bb3.i49.i, label %bb31.i, !prof !1319

bb3.i49.i:                                        ; preds = %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$8split_at17h6d8d762edb74345bE.exit42.i"
; call core::panicking::panic_fmt
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking9panic_fmt(ptr noundef nonnull @anon.eb89d4395b0ead844ef0b45b8b54da85.153, ptr noundef nonnull inttoptr (i64 19 to ptr), ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_6161ee33fc47ffa1bed32b7848b37ed6) #104, !noalias !2114
  unreachable

bb31.i:                                           ; preds = %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$8split_at17h6d8d762edb74345bE.exit42.i"
  %_523.i253 = icmp eq i64 %_61.sroa.5.0.ph.i, %wrapped_start.sroa.0.0.i.i
  br i1 %_523.i253, label %bb2.i312.preheader, label %bb2.i254

bb2.i254:                                         ; preds = %bb31.i, %bb5.i267
  %idx.sroa.0.024.i255 = phi i64 [ %508, %bb5.i267 ], [ 0, %bb31.i ]
  %_9.i256 = getelementptr inbounds nuw %Answer, ptr %_6757.i, i64 %idx.sroa.0.024.i255
  %_12.i257 = getelementptr inbounds nuw %Answer, ptr %460, i64 %idx.sroa.0.024.i255
  %_9.val.i258 = load i64, ptr %_9.i256, align 8, !range !954, !noalias !2095, !noundef !31
  %490 = getelementptr i8, ptr %_9.i256, i64 8
  %_9.val5.i259 = load ptr, ptr %490, align 8, !noalias !2095
  %_12.val.i260 = load i64, ptr %_12.i257, align 8, !range !954, !noalias !2095, !noundef !31
  %491 = getelementptr i8, ptr %_12.i257, i64 8
  %_12.val6.i261 = load ptr, ptr %491, align 8, !noalias !2095
  %_5.i.i.i262 = icmp eq i64 %_9.val.i258, %_12.val.i260
  br i1 %_5.i.i.i262, label %bb1.i.i.i265, label %bb13, !prof !2094

bb1.i.i.i265:                                     ; preds = %bb2.i254
  %or.cond.not.i.i.i266 = icmp eq i64 %_9.val.i258, 0
  br i1 %or.cond.not.i.i.i266, label %bb5.i.i.i269, label %bb5.i267

bb5.i.i.i269:                                     ; preds = %bb1.i.i.i265
  %.not.i.i.i270 = icmp eq ptr %_9.val5.i259, null
  %492 = icmp eq ptr %_12.val6.i261, null
  %brmerge.i.i.i271 = select i1 %.not.i.i.i270, i1 true, i1 %492
  br i1 %brmerge.i.i.i271, label %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i308, label %bb12.i.i.i272

bb12.i.i.i272:                                    ; preds = %bb5.i.i.i269
  %_11.i.i.i273 = icmp eq ptr %_9.val5.i259, %_12.val6.i261
  br i1 %_11.i.i.i273, label %bb5.i267, label %tailrecurse.i.i.i.i274

tailrecurse.i.i.i.i274:                           ; preds = %bb12.i.i.i272, %bb17.i.i.i.i303
  %self.8.val.pn.i.i.i275 = phi ptr [ %504, %bb17.i.i.i.i303 ], [ %_9.val5.i259, %bb12.i.i.i272 ]
  %other.8.val.pn.i.i.i276 = phi ptr [ %506, %bb17.i.i.i.i303 ], [ %_12.val6.i261, %bb12.i.i.i272 ]
  %other.tr.i.i.i.i277 = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i276, i64 16
  %self.tr.i.i.i.i278 = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i275, i64 16
  %493 = load ptr, ptr %self.tr.i.i.i.i278, align 8, !noalias !2118, !noundef !31
  %.not.i.i.i.i279 = icmp eq ptr %493, null
  %494 = load ptr, ptr %other.tr.i.i.i.i277, align 8, !noalias !2121, !noundef !31
  %495 = icmp eq ptr %494, null
  br i1 %.not.i.i.i.i279, label %bb4.i.i.i.i307, label %bb6.i.i.i.i280

bb6.i.i.i.i280:                                   ; preds = %tailrecurse.i.i.i.i274
  br i1 %495, label %bb13, label %bb9.i.i.i.i281, !prof !2123

bb4.i.i.i.i307:                                   ; preds = %tailrecurse.i.i.i.i274
  br i1 %495, label %bb1.i.i.i.i300, label %bb13, !prof !2094

bb9.i.i.i.i281:                                   ; preds = %bb6.i.i.i.i280
  %_7.i.i.i.i282 = icmp eq ptr %493, %494
  br i1 %_7.i.i.i.i282, label %bb1.i.i.i.i300, label %bb11.i.i.i.i283

bb11.i.i.i.i283:                                  ; preds = %bb9.i.i.i.i281
  %_8.i.i.i.i284 = getelementptr inbounds nuw i8, ptr %493, i64 16
  %_9.i.i.i.i285 = getelementptr inbounds nuw i8, ptr %494, i64 16
  call void @llvm.experimental.noalias.scope.decl(metadata !2124), !noalias !2095
  call void @llvm.experimental.noalias.scope.decl(metadata !2127), !noalias !2095
  %_44.i.i.i.i.i286 = load i64, ptr %_8.i.i.i.i284, align 8, !alias.scope !2124, !noalias !2129, !noundef !31
  %_55.i.i.i.i.i287 = load i64, ptr %_9.i.i.i.i285, align 8, !alias.scope !2127, !noalias !2130, !noundef !31
  %_36.i.i.i.i.i288 = icmp eq i64 %_44.i.i.i.i.i286, %_55.i.i.i.i.i287
  br i1 %_36.i.i.i.i.i288, label %bb1.i.i.i.i.i289, label %bb13, !prof !2094

bb1.i.i.i.i.i289:                                 ; preds = %bb11.i.i.i.i283, %bb11.i.i.i.i.i294
  %496 = phi ptr [ %501, %bb11.i.i.i.i.i294 ], [ %494, %bb11.i.i.i.i283 ]
  %497 = phi ptr [ %499, %bb11.i.i.i.i.i294 ], [ %493, %bb11.i.i.i.i283 ]
  %498 = getelementptr inbounds nuw i8, ptr %497, i64 24
  %499 = load ptr, ptr %498, align 8, !noalias !2129, !noundef !31
  %.not.i.i.i.i.i290 = icmp eq ptr %499, null
  %500 = getelementptr inbounds nuw i8, ptr %496, i64 24
  %501 = load ptr, ptr %500, align 8, !noalias !2130, !noundef !31
  %502 = icmp eq ptr %501, null
  br i1 %.not.i.i.i.i.i290, label %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i306", label %bb6.i.i.i.i.i291

bb6.i.i.i.i.i291:                                 ; preds = %bb1.i.i.i.i.i289
  br i1 %502, label %bb13, label %bb9.i.i.i.i.i292, !prof !2123

bb9.i.i.i.i.i292:                                 ; preds = %bb6.i.i.i.i.i291
  %_9.i.i.i.i.i293 = icmp eq ptr %499, %501
  br i1 %_9.i.i.i.i.i293, label %bb1.i.i.i.i300, label %bb11.i.i.i.i.i294

bb11.i.i.i.i.i294:                                ; preds = %bb9.i.i.i.i.i292
  %_10.i.i.i.i.i295 = getelementptr inbounds nuw i8, ptr %499, i64 16
  %_11.i.i.i.i.i296 = getelementptr inbounds nuw i8, ptr %501, i64 16
  %_4.i.i.i.i.i297 = load i64, ptr %_10.i.i.i.i.i295, align 8, !noalias !2131, !noundef !31
  %_5.i.i.i.i.i298 = load i64, ptr %_11.i.i.i.i.i296, align 8, !noalias !2131, !noundef !31
  %_3.i.i.i.i.i299 = icmp eq i64 %_4.i.i.i.i.i297, %_5.i.i.i.i.i298
  br i1 %_3.i.i.i.i.i299, label %bb1.i.i.i.i.i289, label %bb13, !prof !2094

"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i306": ; preds = %bb1.i.i.i.i.i289
  br i1 %502, label %bb1.i.i.i.i300, label %bb13, !prof !2094

bb1.i.i.i.i300:                                   ; preds = %bb9.i.i.i.i.i292, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i306", %bb9.i.i.i.i281, %bb4.i.i.i.i307
  %503 = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i275, i64 24
  %504 = load ptr, ptr %503, align 8, !noalias !2118, !noundef !31
  %.not5.i.i.i.i301 = icmp eq ptr %504, null
  %505 = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i276, i64 24
  %506 = load ptr, ptr %505, align 8, !noalias !2121, !noundef !31
  %507 = icmp eq ptr %506, null
  br i1 %.not5.i.i.i.i301, label %bb15.i.i.i.i305, label %bb14.i.i.i.i302

bb14.i.i.i.i302:                                  ; preds = %bb1.i.i.i.i300
  br i1 %507, label %bb13, label %bb17.i.i.i.i303, !prof !2123

bb15.i.i.i.i305:                                  ; preds = %bb1.i.i.i.i300
  br i1 %507, label %bb5.i267, label %bb13, !prof !2094

bb17.i.i.i.i303:                                  ; preds = %bb14.i.i.i.i302
  %_19.i.i.i.i304 = icmp eq ptr %504, %506
  br i1 %_19.i.i.i.i304, label %bb5.i267, label %tailrecurse.i.i.i.i274

_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i308: ; preds = %bb5.i.i.i269
  %.mux.i.i.i309 = select i1 %.not.i.i.i270, i1 %492, i1 false
  br i1 %.mux.i.i.i309, label %bb5.i267, label %bb13, !prof !2094

bb5.i267:                                         ; preds = %bb17.i.i.i.i303, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i308, %bb15.i.i.i.i305, %bb12.i.i.i272, %bb1.i.i.i265
  %508 = add nuw i64 %idx.sroa.0.024.i255, 1
  %exitcond.not.i268 = icmp eq i64 %508, %front58.i
  br i1 %exitcond.not.i268, label %bb2.i312.preheader, label %bb2.i254

bb2.i312.preheader:                               ; preds = %bb5.i267, %bb31.i
  br label %bb2.i312

bb2.i312:                                         ; preds = %bb2.i312.preheader, %bb5.i325
  %idx.sroa.0.024.i313 = phi i64 [ %527, %bb5.i325 ], [ 0, %bb2.i312.preheader ]
  %_9.i314 = getelementptr inbounds nuw %Answer, ptr %_7056.i, i64 %idx.sroa.0.024.i313
  %_12.i315 = getelementptr inbounds nuw %Answer, ptr %data.i.i36.i, i64 %idx.sroa.0.024.i313
  %_9.val.i316 = load i64, ptr %_9.i314, align 8, !range !954, !noalias !2095, !noundef !31
  %509 = getelementptr i8, ptr %_9.i314, i64 8
  %_9.val5.i317 = load ptr, ptr %509, align 8, !noalias !2095
  %_12.val.i318 = load i64, ptr %_12.i315, align 8, !range !954, !noalias !2095, !noundef !31
  %510 = getelementptr i8, ptr %_12.i315, i64 8
  %_12.val6.i319 = load ptr, ptr %510, align 8, !noalias !2095
  %_5.i.i.i320 = icmp eq i64 %_9.val.i316, %_12.val.i318
  br i1 %_5.i.i.i320, label %bb1.i.i.i323, label %bb13

bb1.i.i.i323:                                     ; preds = %bb2.i312
  %or.cond.not.i.i.i324 = icmp eq i64 %_9.val.i316, 0
  br i1 %or.cond.not.i.i.i324, label %bb5.i.i.i327, label %bb5.i325

bb5.i.i.i327:                                     ; preds = %bb1.i.i.i323
  %.not.i.i.i328 = icmp eq ptr %_9.val5.i317, null
  %511 = icmp eq ptr %_12.val6.i319, null
  %brmerge.i.i.i329 = select i1 %.not.i.i.i328, i1 true, i1 %511
  br i1 %brmerge.i.i.i329, label %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i366, label %bb12.i.i.i330

bb12.i.i.i330:                                    ; preds = %bb5.i.i.i327
  %_11.i.i.i331 = icmp eq ptr %_9.val5.i317, %_12.val6.i319
  br i1 %_11.i.i.i331, label %bb5.i325, label %tailrecurse.i.i.i.i332

tailrecurse.i.i.i.i332:                           ; preds = %bb12.i.i.i330, %bb17.i.i.i.i361
  %self.8.val.pn.i.i.i333 = phi ptr [ %523, %bb17.i.i.i.i361 ], [ %_9.val5.i317, %bb12.i.i.i330 ]
  %other.8.val.pn.i.i.i334 = phi ptr [ %525, %bb17.i.i.i.i361 ], [ %_12.val6.i319, %bb12.i.i.i330 ]
  %other.tr.i.i.i.i335 = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i334, i64 16
  %self.tr.i.i.i.i336 = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i333, i64 16
  %512 = load ptr, ptr %self.tr.i.i.i.i336, align 8, !noalias !2132, !noundef !31
  %.not.i.i.i.i337 = icmp eq ptr %512, null
  %513 = load ptr, ptr %other.tr.i.i.i.i335, align 8, !noalias !2135, !noundef !31
  %514 = icmp eq ptr %513, null
  br i1 %.not.i.i.i.i337, label %bb4.i.i.i.i365, label %bb6.i.i.i.i338

bb6.i.i.i.i338:                                   ; preds = %tailrecurse.i.i.i.i332
  br i1 %514, label %bb13, label %bb9.i.i.i.i339

bb4.i.i.i.i365:                                   ; preds = %tailrecurse.i.i.i.i332
  br i1 %514, label %bb1.i.i.i.i358, label %bb13

bb9.i.i.i.i339:                                   ; preds = %bb6.i.i.i.i338
  %_7.i.i.i.i340 = icmp eq ptr %512, %513
  br i1 %_7.i.i.i.i340, label %bb1.i.i.i.i358, label %bb11.i.i.i.i341

bb11.i.i.i.i341:                                  ; preds = %bb9.i.i.i.i339
  %_8.i.i.i.i342 = getelementptr inbounds nuw i8, ptr %512, i64 16
  %_9.i.i.i.i343 = getelementptr inbounds nuw i8, ptr %513, i64 16
  call void @llvm.experimental.noalias.scope.decl(metadata !2137), !noalias !2095
  call void @llvm.experimental.noalias.scope.decl(metadata !2140), !noalias !2095
  %_44.i.i.i.i.i344 = load i64, ptr %_8.i.i.i.i342, align 8, !alias.scope !2137, !noalias !2142, !noundef !31
  %_55.i.i.i.i.i345 = load i64, ptr %_9.i.i.i.i343, align 8, !alias.scope !2140, !noalias !2143, !noundef !31
  %_36.i.i.i.i.i346 = icmp eq i64 %_44.i.i.i.i.i344, %_55.i.i.i.i.i345
  br i1 %_36.i.i.i.i.i346, label %bb1.i.i.i.i.i347, label %bb13

bb1.i.i.i.i.i347:                                 ; preds = %bb11.i.i.i.i341, %bb11.i.i.i.i.i352
  %515 = phi ptr [ %520, %bb11.i.i.i.i.i352 ], [ %513, %bb11.i.i.i.i341 ]
  %516 = phi ptr [ %518, %bb11.i.i.i.i.i352 ], [ %512, %bb11.i.i.i.i341 ]
  %517 = getelementptr inbounds nuw i8, ptr %516, i64 24
  %518 = load ptr, ptr %517, align 8, !noalias !2142, !noundef !31
  %.not.i.i.i.i.i348 = icmp eq ptr %518, null
  %519 = getelementptr inbounds nuw i8, ptr %515, i64 24
  %520 = load ptr, ptr %519, align 8, !noalias !2143, !noundef !31
  %521 = icmp eq ptr %520, null
  br i1 %.not.i.i.i.i.i348, label %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i364", label %bb6.i.i.i.i.i349

bb6.i.i.i.i.i349:                                 ; preds = %bb1.i.i.i.i.i347
  br i1 %521, label %bb13, label %bb9.i.i.i.i.i350

bb9.i.i.i.i.i350:                                 ; preds = %bb6.i.i.i.i.i349
  %_9.i.i.i.i.i351 = icmp eq ptr %518, %520
  br i1 %_9.i.i.i.i.i351, label %bb1.i.i.i.i358, label %bb11.i.i.i.i.i352

bb11.i.i.i.i.i352:                                ; preds = %bb9.i.i.i.i.i350
  %_10.i.i.i.i.i353 = getelementptr inbounds nuw i8, ptr %518, i64 16
  %_11.i.i.i.i.i354 = getelementptr inbounds nuw i8, ptr %520, i64 16
  %_4.i.i.i.i.i355 = load i64, ptr %_10.i.i.i.i.i353, align 8, !noalias !2144, !noundef !31
  %_5.i.i.i.i.i356 = load i64, ptr %_11.i.i.i.i.i354, align 8, !noalias !2144, !noundef !31
  %_3.i.i.i.i.i357 = icmp eq i64 %_4.i.i.i.i.i355, %_5.i.i.i.i.i356
  br i1 %_3.i.i.i.i.i357, label %bb1.i.i.i.i.i347, label %bb13

"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i364": ; preds = %bb1.i.i.i.i.i347
  br i1 %521, label %bb1.i.i.i.i358, label %bb13

bb1.i.i.i.i358:                                   ; preds = %bb9.i.i.i.i.i350, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i364", %bb9.i.i.i.i339, %bb4.i.i.i.i365
  %522 = getelementptr inbounds nuw i8, ptr %self.8.val.pn.i.i.i333, i64 24
  %523 = load ptr, ptr %522, align 8, !noalias !2132, !noundef !31
  %.not5.i.i.i.i359 = icmp eq ptr %523, null
  %524 = getelementptr inbounds nuw i8, ptr %other.8.val.pn.i.i.i334, i64 24
  %525 = load ptr, ptr %524, align 8, !noalias !2135, !noundef !31
  %526 = icmp eq ptr %525, null
  br i1 %.not5.i.i.i.i359, label %bb15.i.i.i.i363, label %bb14.i.i.i.i360

bb14.i.i.i.i360:                                  ; preds = %bb1.i.i.i.i358
  br i1 %526, label %bb13, label %bb17.i.i.i.i361

bb15.i.i.i.i363:                                  ; preds = %bb1.i.i.i.i358
  br i1 %526, label %bb5.i325, label %bb13

bb17.i.i.i.i361:                                  ; preds = %bb14.i.i.i.i360
  %_19.i.i.i.i362 = icmp eq ptr %523, %525
  br i1 %_19.i.i.i.i362, label %bb5.i325, label %tailrecurse.i.i.i.i332

_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i366: ; preds = %bb5.i.i.i327
  %.mux.i.i.i367 = select i1 %.not.i.i.i328, i1 %511, i1 false
  br i1 %.mux.i.i.i367, label %bb5.i325, label %bb13

bb5.i325:                                         ; preds = %bb17.i.i.i.i361, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i366, %bb15.i.i.i.i363, %bb12.i.i.i330, %bb1.i.i.i323
  %527 = add nuw i64 %idx.sroa.0.024.i313, 1
  %exitcond.not.i326 = icmp eq i64 %527, %mid8.i
  br i1 %exitcond.not.i326, label %"_ZN63_$LT$A$u20$as$u20$core..slice..cmp..SlicePartialEq$LT$B$GT$$GT$17equal_same_length17hc2049eaf5f41d90eE.exit368", label %bb2.i312

"_ZN63_$LT$A$u20$as$u20$core..slice..cmp..SlicePartialEq$LT$B$GT$$GT$17equal_same_length17hc2049eaf5f41d90eE.exit368": ; preds = %bb5.i325
  %_120.i = icmp eq i64 %_61.sroa.11.0.ph.i, %mid8.i
  br i1 %_120.i, label %bb12, label %bb13, !prof !2145

bb25:                                             ; preds = %bb25.lr.ph, %_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit
  %iter.sroa.0.048 = phi i64 [ 0, %bb25.lr.ph ], [ %_56, %_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit ]
  %_56 = add nuw i64 %iter.sroa.0.048, 1
  call void @llvm.lifetime.start.p0(ptr nonnull %_17)
  call void @llvm.lifetime.start.p0(ptr nonnull %_18)
  call void @llvm.lifetime.start.p0(ptr nonnull %13)
  store i64 %columns, ptr %13, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %13) #65, !srcloc !30
  %_19 = load i64, ptr %13, align 8, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %13)
  call void @llvm.lifetime.start.p0(ptr nonnull %12)
  store i64 %inv_size, ptr %12, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %12) #65, !srcloc !30
  %_20 = load i64, ptr %12, align 8, !noundef !31
  call void @llvm.lifetime.end.p0(ptr nonnull %12)
  %_3.i = icmp ne i64 %_19, 0
  %_4.i8 = icmp ugt i64 %_20, 1
  %or.cond.i = and i1 %_3.i, %_4.i8
  br i1 %or.cond.i, label %bb2.i10, label %bb3.i9, !prof !2146

bb3.i9:                                           ; preds = %bb25
; call core::panicking::panic
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking5panic(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @alloc_698a8c253bc44aa3a7028b6ef7f20b33, i64 noundef 46, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_f0801d69dd6ca78f53618dbbd3a40715) #104, !noalias !2147
  unreachable

bb2.i10:                                          ; preds = %bb25
  call void @llvm.lifetime.start.p0(ptr nonnull %field.i), !noalias !2147
  call void @llvm.experimental.noalias.scope.decl(metadata !2150)
  %_54.i.i.i = lshr i64 %_20, 1
  %_4.i.i.i = trunc i64 %_54.i.i.i to i32
  %528 = icmp eq i32 %_4.i.i.i, 0
  br i1 %528, label %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i, label %bb15.i.i.i.i

bb15.i.i.i.i:                                     ; preds = %bb2.i10, %bb21.i.i.i.i
  %acc.sroa.0.1.i.i.i.i = phi i64 [ %acc.sroa.0.2.i.i.i.i, %bb21.i.i.i.i ], [ 1, %bb2.i10 ]
  %exp.sroa.0.0.i.i.i.i = phi i32 [ %530, %bb21.i.i.i.i ], [ %_4.i.i.i, %bb2.i10 ]
  %self.sroa.0.0.i.i.i.i = phi i64 [ %_21.0.i.i.i.i, %bb21.i.i.i.i ], [ %_20, %bb2.i10 ]
  %_15.i.i.i.i = and i32 %exp.sroa.0.0.i.i.i.i, 1
  %.not.i.i.i.i = icmp eq i32 %_15.i.i.i.i, 0
  br i1 %.not.i.i.i.i, label %bb21.i.i.i.i, label %bb16.i.i.i.i

bb16.i.i.i.i:                                     ; preds = %bb15.i.i.i.i
  %_18.0.i.i.i.i = mul i64 %self.sroa.0.0.i.i.i.i, %acc.sroa.0.1.i.i.i.i
  %529 = icmp eq i32 %exp.sroa.0.0.i.i.i.i, 1
  br i1 %529, label %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i, label %bb21.i.i.i.i

bb21.i.i.i.i:                                     ; preds = %bb16.i.i.i.i, %bb15.i.i.i.i
  %acc.sroa.0.2.i.i.i.i = phi i64 [ %_18.0.i.i.i.i, %bb16.i.i.i.i ], [ %acc.sroa.0.1.i.i.i.i, %bb15.i.i.i.i ]
  %530 = lshr i32 %exp.sroa.0.0.i.i.i.i, 1
  %_21.0.i.i.i.i = mul i64 %self.sroa.0.0.i.i.i.i, %self.sroa.0.0.i.i.i.i
  br label %bb15.i.i.i.i

_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i: ; preds = %bb16.i.i.i.i, %bb2.i10
  %acc.sroa.0.0.i.i.i.i = phi i64 [ 1, %bb2.i10 ], [ %_18.0.i.i.i.i, %bb16.i.i.i.i ]
  %_12.i.i.i = and i64 %_20, 1
  %_6.i.i.i = icmp eq i64 %_12.i.i.i, 0
  br i1 %_6.i.i.i, label %_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i, label %bb4.i.i.i

bb4.i.i.i:                                        ; preds = %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i, %bb4.i.i.i
  %root.sroa.0.0.i.i.i = phi i64 [ %531, %bb4.i.i.i ], [ 0, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i ]
  %_9.i.i.i = mul i64 %root.sroa.0.0.i.i.i, %root.sroa.0.0.i.i.i
  %_8.i.i.i = icmp slt i64 %_9.i.i.i, %_20
  %531 = add i64 %root.sroa.0.0.i.i.i, 1
  br i1 %_8.i.i.i, label %bb4.i.i.i, label %bb6.i.i.i

bb6.i.i.i:                                        ; preds = %bb4.i.i.i
  %root.sroa.0.0.i.i.i.lcssa = phi i64 [ %root.sroa.0.0.i.i.i, %bb4.i.i.i ]
  %532 = mul i64 %root.sroa.0.0.i.i.i.lcssa, %acc.sroa.0.0.i.i.i.i
  br label %_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i

_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i: ; preds = %bb6.i.i.i, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i
  %_0.sroa.0.0.i.i.i = phi i64 [ %532, %bb6.i.i.i ], [ %acc.sroa.0.0.i.i.i.i, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx3pow.exit.i.i.i ]
  %_2.i.i.i = icmp slt i64 %_0.sroa.0.0.i.i.i, 2
  br i1 %_2.i.i.i, label %_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i, label %bb2.i.i.i

bb2.i.i.i:                                        ; preds = %_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i
  %533 = call noundef dereferenceable_or_null(8) ptr @malloc(i64 noundef 8) #65, !dbg !1250, !noalias !2153
  %534 = icmp eq ptr %533, null
  br i1 %534, label %bb2.i.i3.i.i, label %_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i, !prof !1319

bb2.i.i3.i.i:                                     ; preds = %bb2.i.i.i
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 8) #105, !noalias !2153
  unreachable

_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i: ; preds = %bb2.i.i.i
  store i64 2, ptr %533, align 8, !noalias !2153
  call void @llvm.lifetime.start.p0(ptr nonnull %primes.i.i.i), !noalias !2153
  store i64 1, ptr %primes.i.i.i, align 8, !noalias !2153
  store ptr %533, ptr %_4.sroa.2.0.primes.sroa_idx.i.i.i, align 8, !noalias !2153
  store i64 1, ptr %_4.sroa.3.0.primes.sroa_idx.i.i.i, align 8, !noalias !2153
  br label %bb3.i.i.i

bb3.i.i.i:                                        ; preds = %bb9.i.i.i, %_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i
  %_30.pre24.i.i.i = phi ptr [ %533, %_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i ], [ %_30.pre.i.i.i, %bb9.i.i.i ]
  %_29.i.i.i = phi i64 [ 1, %_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i ], [ %_2921.i.i.i, %bb9.i.i.i ]
  %trial.sroa.0.0.i.i.i = phi i64 [ 3, %_RNvNtCslNYArtu3iFV_5alloc5boxed14box_new_uninit.exit.i.i.i ], [ %538, %bb9.i.i.i ]
  call void @llvm.experimental.noalias.scope.decl(metadata !2154)
  %_18.i.i.i.i = getelementptr inbounds nuw i64, ptr %_30.pre24.i.i.i, i64 %_29.i.i.i
  %_11.i.i.i.i = icmp eq i64 %trial.sroa.0.0.i.i.i, -9223372036854775808
  br i1 %_11.i.i.i.i, label %bb1.i.i.i.i, label %bb1.us.i.i.i.i

bb1.us.i.i.i.i:                                   ; preds = %bb3.i.i.i, %bb4.us.i.i.i.i
  %iter.sroa.0.0.us.i.i.i.i = phi ptr [ %_31.us.i.i.i.i, %bb4.us.i.i.i.i ], [ %_30.pre24.i.i.i, %bb3.i.i.i ]
  %_25.us.i.i.i.i = icmp eq ptr %iter.sroa.0.0.us.i.i.i.i, %_18.i.i.i.i
  br i1 %_25.us.i.i.i.i, label %bb5.i.i.i, label %bb11.us.i.i.i.i

bb11.us.i.i.i.i:                                  ; preds = %bb1.us.i.i.i.i
  %_31.us.i.i.i.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.0.us.i.i.i.i, i64 8
  %prime.us.i.i.i.i = load i64, ptr %iter.sroa.0.0.us.i.i.i.i, align 8, !alias.scope !2154, !noalias !2153, !noundef !31
  %_7.us.i.i.i.i = mul i64 %prime.us.i.i.i.i, %prime.us.i.i.i.i
  %_6.us.i.i.i.i = icmp slt i64 %trial.sroa.0.0.i.i.i, %_7.us.i.i.i.i
  br i1 %_6.us.i.i.i.i, label %bb5.i.i.i, label %bb3.us.i.i.i.i

bb3.us.i.i.i.i:                                   ; preds = %bb11.us.i.i.i.i
  %_9.us.i.i.i.i = icmp eq i64 %prime.us.i.i.i.i, 0
  br i1 %_9.us.i.i.i.i, label %panic.i.i.i.i, label %bb4.us.i.i.i.i

bb4.us.i.i.i.i:                                   ; preds = %bb3.us.i.i.i.i
  %_8.us.i.i.i.i = srem i64 %trial.sroa.0.0.i.i.i, %prime.us.i.i.i.i
  %535 = icmp eq i64 %_8.us.i.i.i.i, 0
  br i1 %535, label %bb9.i.i.i, label %bb1.us.i.i.i.i

bb1.i.i.i.i:                                      ; preds = %bb3.i.i.i, %bb5.i.i.i.i
  %iter.sroa.0.0.i.i.i.i = phi ptr [ %_31.i.i.i.i, %bb5.i.i.i.i ], [ %_30.pre24.i.i.i, %bb3.i.i.i ]
  %_25.i.i.i.i = icmp eq ptr %iter.sroa.0.0.i.i.i.i, %_18.i.i.i.i
  br i1 %_25.i.i.i.i, label %bb5.i.i.i, label %bb11.i.i.i.i

bb11.i.i.i.i:                                     ; preds = %bb1.i.i.i.i
  %_31.i.i.i.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.0.i.i.i.i, i64 8
  %prime.i.i.i.i = load i64, ptr %iter.sroa.0.0.i.i.i.i, align 8, !alias.scope !2154, !noalias !2153, !noundef !31
  %_7.i.i.i.i = mul i64 %prime.i.i.i.i, %prime.i.i.i.i
  %_6.not.i.i.i.i = icmp eq i64 %_7.i.i.i.i, -9223372036854775808
  br i1 %_6.not.i.i.i.i, label %bb3.i.i.i.i, label %bb5.i.i.i

bb3.i.i.i.i:                                      ; preds = %bb11.i.i.i.i
  switch i64 %prime.i.i.i.i, label %bb5.i.i.i.i [
    i64 0, label %panic.i.i.i.i
    i64 -1, label %panic1.i.i.i.i
  ]

panic.i.i.i.i:                                    ; preds = %bb3.us.i.i.i.i, %bb3.i.i.i.i
; call core::panicking::panic_const::panic_const_rem_by_zero
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const23panic_const_rem_by_zero(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_3e75c329d79208ee74dcc1abd7cd8953) #104, !noalias !2157
  unreachable

bb5.i.i.i.i:                                      ; preds = %bb3.i.i.i.i
  %_8.i.i2.i.i = srem i64 -9223372036854775808, %prime.i.i.i.i
  %536 = icmp eq i64 %_8.i.i2.i.i, 0
  br i1 %536, label %bb9.i.i.i, label %bb1.i.i.i.i

panic1.i.i.i.i:                                   ; preds = %bb3.i.i.i.i
; call core::panicking::panic_const::panic_const_rem_overflow
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const24panic_const_rem_overflow(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_3e75c329d79208ee74dcc1abd7cd8953) #104, !noalias !2157
  unreachable

bb5.i.i.i:                                        ; preds = %bb11.us.i.i.i.i, %bb1.us.i.i.i.i, %bb11.i.i.i.i, %bb1.i.i.i.i
  %self1.i.i.i.i = load i64, ptr %primes.i.i.i, align 8, !range !1117, !alias.scope !2158, !noalias !2153, !noundef !31
  %_4.i.i.i.i = icmp eq i64 %_29.i.i.i, %self1.i.i.i.i
  br i1 %_4.i.i.i.i, label %bb1.i6.i.i.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i"

bb1.i6.i.i.i:                                     ; preds = %bb5.i.i.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1a919c860bf3f0ecE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %primes.i.i.i) #103, !noalias !2153
  %_14.i.pre.i.i.i = load ptr, ptr %_4.sroa.2.0.primes.sroa_idx.i.i.i, align 8, !alias.scope !2158, !noalias !2153
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i": ; preds = %bb1.i6.i.i.i, %bb5.i.i.i
  %_14.i.i.i.i = phi ptr [ %_30.pre24.i.i.i, %bb5.i.i.i ], [ %_14.i.pre.i.i.i, %bb1.i6.i.i.i ]
  %end.i.i.i.i = getelementptr inbounds nuw i64, ptr %_14.i.i.i.i, i64 %_29.i.i.i
  store i64 %trial.sroa.0.0.i.i.i, ptr %end.i.i.i.i, align 8, !noalias !2153
  %537 = add i64 %_29.i.i.i, 1
  store i64 %537, ptr %_4.sroa.3.0.primes.sroa_idx.i.i.i, align 8, !alias.scope !2158, !noalias !2153
  %_11.i.i.i = icmp sgt i64 %trial.sroa.0.0.i.i.i, %_0.sroa.0.0.i.i.i
  br i1 %_11.i.i.i, label %bb6.i1.i.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.bb9_crit_edge.i.i.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.bb9_crit_edge.i.i.i": ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i"
  %_30.pre.pre.i.i.i = load ptr, ptr %_4.sroa.2.0.primes.sroa_idx.i.i.i, align 8, !noalias !2153
  br label %bb9.i.i.i

bb9.i.i.i:                                        ; preds = %bb4.us.i.i.i.i, %bb5.i.i.i.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.bb9_crit_edge.i.i.i"
  %_30.pre.i.i.i = phi ptr [ %_30.pre24.i.i.i, %bb5.i.i.i.i ], [ %_30.pre.pre.i.i.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.bb9_crit_edge.i.i.i" ], [ %_30.pre24.i.i.i, %bb4.us.i.i.i.i ]
  %_2921.i.i.i = phi i64 [ %_29.i.i.i, %bb5.i.i.i.i ], [ %537, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.bb9_crit_edge.i.i.i" ], [ %_29.i.i.i, %bb4.us.i.i.i.i ]
  %538 = add i64 %trial.sroa.0.0.i.i.i, 2
  br label %bb3.i.i.i

bb6.i1.i.i:                                       ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i"
  %trial.sroa.0.0.i.i.i.lcssa630 = phi i64 [ %trial.sroa.0.0.i.i.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i.i.i" ]
  %primes.val.i.i.i = load i64, ptr %primes.i.i.i, align 8, !range !1117, !noalias !2153, !noundef !31
  %539 = icmp eq i64 %primes.val.i.i.i, 0
  br i1 %539, label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i.i", label %bb2.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i:                                ; preds = %bb6.i1.i.i
  %primes.val5.i.i.i = load ptr, ptr %_4.sroa.2.0.primes.sroa_idx.i.i.i, align 8, !noalias !2153, !nonnull !31, !noundef !31
  call void @free(ptr noundef nonnull %primes.val5.i.i.i) #65, !dbg !1104
  br label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i.i"

"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i.i": ; preds = %bb2.i.i.i.i.i.i.i, %bb6.i1.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %primes.i.i.i), !noalias !2153
  br label %_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i

_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i: ; preds = %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i.i", %_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i
  %trial.sroa.0.1.i.i.i = phi i64 [ %trial.sroa.0.0.i.i.i.lcssa630, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i.i" ], [ 2, %_ZN6matrix17determinant_bound17h98fd7f089a38f113E.exit.i.i ]
  %540 = call i64 @llvm.smax.i64(i64 %trial.sroa.0.1.i.i.i, i64 1)
  %spec.select.i.i.i.i.i = add nsw i64 %540, -1
  %_33.0.i.i.i.i.i = shl i64 %spec.select.i.i.i.i.i, 3
  %_33.1.i.i.i.i.i = icmp sgt i64 %trial.sroa.0.1.i.i.i, 2305843009213693952
  %_38.i.i.i.i.i = icmp ugt i64 %_33.0.i.i.i.i.i, 9223372036854775800
  %or.cond.not.i.i.i.i.i = or i1 %_33.1.i.i.i.i.i, %_38.i.i.i.i.i
  br i1 %or.cond.not.i.i.i.i.i, label %_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i.split, label %bb18.i.i.i.i.i, !prof !1219

_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i.split: ; preds = %_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i
; call alloc::raw_vec::capacity_overflow
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #108, !dbg !1943, !noalias !2161
  unreachable, !dbg !1943

bb18.i.i.i.i.i:                                   ; preds = %_ZN6matrix10find_prime17h0a3fcf515010af79E.exit.i.i
  %541 = icmp eq i64 %_33.0.i.i.i.i.i, 0
  br i1 %541, label %bb3.i.i.i.i.i.i.preheader.i.i, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit374

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit374: ; preds = %bb18.i.i.i.i.i
  %542 = call noundef ptr @malloc(i64 noundef range(i64 0, 9223372036854775801) %_33.0.i.i.i.i.i) #65, !dbg !1250, !noalias !2165
  %543 = icmp eq ptr %542, null
  br i1 %543, label %_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.i.i.i.i.split, label %bb10.i.i.i.i.i

_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.i.i.i.i.split: ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit374
  %_33.0.i.i.i.i.i.lcssa637 = phi i64 [ %_33.0.i.i.i.i.i, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit374 ]
; call alloc::raw_vec::handle_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 8, i64 %_33.0.i.i.i.i.i.lcssa637) #105, !noalias !2161
  unreachable

bb10.i.i.i.i.i:                                   ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit374
  %544 = ptrtoint ptr %542 to i64
  br label %bb3.i.i.i.i.i.i.preheader.i.i

bb3.i.i.i.i.i.i.preheader.i.i:                    ; preds = %bb10.i.i.i.i.i, %bb18.i.i.i.i.i
  %_4.sroa.4.0.i.i.i.i = phi i64 [ %spec.select.i.i.i.i.i, %bb10.i.i.i.i.i ], [ 0, %bb18.i.i.i.i.i ]
  %_4.sroa.10.0.i.i.i.i = phi i64 [ %544, %bb10.i.i.i.i.i ], [ 8, %bb18.i.i.i.i.i ]
  %545 = inttoptr i64 %_4.sroa.10.0.i.i.i.i to ptr
  %_7.i.i5.i.i = icmp samesign ule i64 %spec.select.i.i.i.i.i, %_4.sroa.4.0.i.i.i.i
  call void @llvm.assume(i1 %_7.i.i5.i.i)
  %546 = add nsw i64 %trial.sroa.0.1.i.i.i, -1
  br label %bb3.i.i.i.i.i.i.i.i

bb3.i.i.i.i.i.i.i.i:                              ; preds = %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i", %bb3.i.i.i.i.i.i.preheader.i.i
  %547 = phi i64 [ %554, %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i" ], [ 0, %bb3.i.i.i.i.i.i.preheader.i.i ]
  %self.sroa.0.010.i.i.i.i.i.i.i.i = phi i64 [ %548, %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i" ], [ 1, %bb3.i.i.i.i.i.i.preheader.i.i ]
  %548 = add nuw nsw i64 %self.sroa.0.010.i.i.i.i.i.i.i.i, 1
  br label %bb2.i.i.i.i.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i.i.i.i.i:                        ; preds = %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i, %bb3.i.i.i.i.i.i.i.i
  %p.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i ], [ %self.sroa.0.010.i.i.i.i.i.i.i.i, %bb3.i.i.i.i.i.i.i.i ]
  %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ %551, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i ], [ %trial.sroa.0.1.i.i.i, %bb3.i.i.i.i.i.i.i.i ]
  %pa.sroa.0.09.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i ], [ 1, %bb3.i.i.i.i.i.i.i.i ]
  %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ %552, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i ], [ 0, %bb3.i.i.i.i.i.i.i.i ]
  %_5.i.i.i.i.i.i.i.i.i.i.i.i = icmp eq i64 %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i, -1
  %_6.i.i.i.i.i.i.i.i.i.i.i.i = icmp eq i64 %p.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i, -9223372036854775808
  %_7.i.i.i.i.i.i.i.i.i.i.i.i = and i1 %_6.i.i.i.i.i.i.i.i.i.i.i.i, %_5.i.i.i.i.i.i.i.i.i.i.i.i
  br i1 %_7.i.i.i.i.i.i.i.i.i.i.i.i, label %panic1.i.i.i.i.i.i.i.i.i.i.i.i, label %bb2.i.i.i.i.i.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i.i.i.i.i.i:                      ; preds = %bb2.i.i.i.i.i.i.i.i.i.i.i
  %q.i.i.i.i.i.i.i.i.i.i.i.i = sdiv i64 %p.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i, %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i
  %_9.i.i.i.i.i.i.i.i.i.i.i.i = srem i64 %p.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i, %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i
  %_8.i.i.i.i.i.i.i.i.i.i.i.i11 = icmp slt i64 %_9.i.i.i.i.i.i.i.i.i.i.i.i, 0
  br i1 %_8.i.i.i.i.i.i.i.i.i.i.i.i11, label %bb3.i.i.i.i.i.i.i.i.i.i.i.i, label %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i

panic1.i.i.i.i.i.i.i.i.i.i.i.i:                   ; preds = %bb2.i.i.i.i.i.i.i.i.i.i.i
; call core::panicking::panic_const::panic_const_div_overflow
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const24panic_const_div_overflow() #104
  unreachable

bb3.i.i.i.i.i.i.i.i.i.i.i.i:                      ; preds = %bb2.i.i.i.i.i.i.i.i.i.i.i.i
  %_10.i.i.i.i.i.i.i.i.i.i.i.i = icmp sgt i64 %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i, 0
  br i1 %_10.i.i.i.i.i.i.i.i.i.i.i.i, label %bb4.i.i.i.i.i.i.i.i.i.i.i.i, label %bb5.i.i.i.i.i.i.i.i.i.i.i.i

bb5.i.i.i.i.i.i.i.i.i.i.i.i:                      ; preds = %bb3.i.i.i.i.i.i.i.i.i.i.i.i
  %549 = add i64 %q.i.i.i.i.i.i.i.i.i.i.i.i, 1
  br label %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i

bb4.i.i.i.i.i.i.i.i.i.i.i.i:                      ; preds = %bb3.i.i.i.i.i.i.i.i.i.i.i.i
  %550 = add i64 %q.i.i.i.i.i.i.i.i.i.i.i.i, -1
  br label %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i

_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i: ; preds = %bb4.i.i.i.i.i.i.i.i.i.i.i.i, %bb5.i.i.i.i.i.i.i.i.i.i.i.i, %bb2.i.i.i.i.i.i.i.i.i.i.i.i
  %_0.sroa.0.0.i.i.i.i.i.i.i.i.i.i.i.i = phi i64 [ %550, %bb4.i.i.i.i.i.i.i.i.i.i.i.i ], [ %549, %bb5.i.i.i.i.i.i.i.i.i.i.i.i ], [ %q.i.i.i.i.i.i.i.i.i.i.i.i, %bb2.i.i.i.i.i.i.i.i.i.i.i.i ]
  %_8.i.i.i.i.i.i.i.i.i.i.i = mul i64 %_0.sroa.0.0.i.i.i.i.i.i.i.i.i.i.i.i, %q.sroa.0.010.i.i.i.i.i.i.i.i.i.i.i
  %551 = sub i64 %p.sroa.0.011.i.i.i.i.i.i.i.i.i.i.i, %_8.i.i.i.i.i.i.i.i.i.i.i
  %_11.i.i.i.i.i.i.i.i.i.i.i = mul i64 %_0.sroa.0.0.i.i.i.i.i.i.i.i.i.i.i.i, %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i
  %552 = sub i64 %pa.sroa.0.09.i.i.i.i.i.i.i.i.i.i.i, %_11.i.i.i.i.i.i.i.i.i.i.i
  %553 = icmp eq i64 %551, 0
  br i1 %553, label %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i", label %bb2.i.i.i.i.i.i.i.i.i.i.i

"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i": ; preds = %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i
  %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i.lcssa631 = phi i64 [ %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i, %_RNvMs1_NtCsgEmfK2I1SDS_4core3numx10div_euclid.exit.i.i.i.i.i.i.i.i.i.i.i ]
  %_3.i.i.i4.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i64, ptr %545, i64 %547
  store i64 %qa.sroa.0.08.i.i.i.i.i.i.i.i.i.i.i.lcssa631, ptr %_3.i.i.i4.i.i.i.i.i.i.i.i, align 8, !noalias !2168
  %554 = add nuw nsw i64 %547, 1
  %exitcond.not.i.i = icmp eq i64 %554, %546
  br i1 %exitcond.not.i.i, label %_ZN6matrix5Field3new17hce8c9cbe0897abe2E.exit.i, label %bb3.i.i.i.i.i.i.i.i

_ZN6matrix5Field3new17hce8c9cbe0897abe2E.exit.i:  ; preds = %"_ZN4core4iter8adapters3map8map_fold28_$u7b$$u7b$closure$u7d$$u7d$17h5991af03c7cf24f7E.exit.i.i.i.i.i.i.i.i"
  store i64 %trial.sroa.0.1.i.i.i, ptr %465, align 8, !alias.scope !2150, !noalias !2147
  store i64 %_4.sroa.4.0.i.i.i.i, ptr %field.i, align 8, !alias.scope !2150, !noalias !2147
  store ptr %545, ptr %_4.sroa.4.0._0.sroa_idx.i.i, align 8, !alias.scope !2150, !noalias !2147
  store i64 %546, ptr %_4.sroa.5.0._0.sroa_idx.i.i, align 8, !alias.scope !2150, !noalias !2147
  call void @llvm.lifetime.start.p0(ptr nonnull %rows.i), !noalias !2147
  call void @llvm.lifetime.start.p0(ptr nonnull %generated.i.i), !noalias !2147
  store ptr null, ptr %generated.i.i, align 8, !noalias !2147
  %_4.i.i = add i64 %_19, -1
  call void @llvm.lifetime.start.p0(ptr nonnull %_6.i.i), !noalias !2147
  store i64 0, ptr %_6.i.i, align 8, !noalias !2147
  store ptr inttoptr (i64 8 to ptr), ptr %466, align 8, !noalias !2147
  store i64 0, ptr %467, align 8, !noalias !2147
; call matrix::generate_tails
  call fastcc void @_ZN6matrix14generate_tails17h16365d1af0040580E(i64 noundef %_4.i.i, ptr noalias noundef align 8 dereferenceable(24) %_6.i.i, ptr noalias noundef align 8 dereferenceable(8) %generated.i.i) #65, !noalias !2147
  %_6.val.i.i = load i64, ptr %_6.i.i, align 8, !range !1117, !noalias !2147, !noundef !31
  %555 = icmp eq i64 %_6.val.i.i, 0
  br i1 %555, label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i", label %bb2.i.i.i.i.i.i

bb2.i.i.i.i.i.i:                                  ; preds = %_ZN6matrix5Field3new17hce8c9cbe0897abe2E.exit.i
  %_6.val3.i.i = load ptr, ptr %466, align 8, !noalias !2147, !nonnull !31, !noundef !31
  call void @free(ptr noundef nonnull %_6.val3.i.i) #65, !dbg !1104
  br label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i"

"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i": ; preds = %bb2.i.i.i.i.i.i, %_ZN6matrix5Field3new17hce8c9cbe0897abe2E.exit.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_6.i.i), !noalias !2147
  %556 = load ptr, ptr %generated.i.i, align 8, !noalias !2147, !noundef !31
  %.not11.i.i = icmp eq ptr %556, null
  br i1 %.not11.i.i, label %bb11.i, label %bb4.i.i

bb4.i.i:                                          ; preds = %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i", %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i
  %557 = phi ptr [ %567, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], [ %556, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i" ]
  %rows.sroa.0.012.i.i = phi ptr [ %564, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], [ null, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i" ]
  %558 = getelementptr inbounds nuw i8, ptr %557, i64 16
  %559 = load ptr, ptr %558, align 8, !noalias !2147, !noundef !31
  %.not2.i.i = icmp eq ptr %559, null
  br i1 %.not2.i.i, label %bb9.i.i, label %bb12.i.i

bb7.i.i:                                          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i
  %.lcssa674 = phi ptr [ %564, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ]
  %.lcssa634 = phi ptr [ %562, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], !dbg !1250
  %_7.sroa.5.0..sroa_idx.i5.i.i.le = getelementptr inbounds nuw i8, ptr %.lcssa674, i64 16
  %_7.sroa.6.0..sroa_idx.i6.i.i.le = getelementptr inbounds nuw i8, ptr %.lcssa674, i64 24
  %_8.i.i.i5.i = load i64, ptr %556, align 8, !noalias !2189, !noundef !31
  %val.i.i.i.i = add i64 %_8.i.i.i5.i, -1
  store i64 %val.i.i.i.i, ptr %556, align 8, !noalias !2189
  %560 = icmp eq i64 %val.i.i.i.i, 0
  br i1 %560, label %bb1.i.i.i6.i, label %bb12.i

bb1.i.i.i6.i:                                     ; preds = %bb7.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %generated.i.i) #103, !noalias !2147
  %.pre.i = load ptr, ptr %_7.sroa.5.0..sroa_idx.i5.i.i.le, align 8, !noalias !2147
  br label %bb12.i

bb12.i.i:                                         ; preds = %bb4.i.i
  %_21.i.i = load i64, ptr %559, align 8, !noalias !2147, !noundef !31
  %_22.i.i = icmp ne i64 %_21.i.i, 0
  call void @llvm.assume(i1 %_22.i.i)
  %_23.i.i = add i64 %_21.i.i, 1
  store i64 %_23.i.i, ptr %559, align 8, !noalias !2147
  %561 = icmp eq i64 %_23.i.i, 0
  br i1 %561, label %bb13.i.i, label %bb15.i.i, !prof !1319

bb9.i.i:                                          ; preds = %bb15.i.i, %bb4.i.i
  %_12.sroa.0.0.i.i = phi ptr [ %_18.i.i, %bb15.i.i ], [ null, %bb4.i.i ]
  %562 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2194
  %563 = icmp eq ptr %562, null
  br i1 %563, label %bb2.i.i.i7.i, label %_ZN6matrix6number17heeef4114a060e7afE.exit.i.i, !prof !1319

bb2.i.i.i7.i:                                     ; preds = %bb9.i.i
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2194
  unreachable

_ZN6matrix6number17heeef4114a060e7afE.exit.i.i:   ; preds = %bb9.i.i
  store i64 1, ptr %562, align 8, !noalias !2147
  %_7.sroa.4.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %562, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i.i, align 8, !noalias !2147
  %_7.sroa.5.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %562, i64 16
  store i64 1, ptr %_7.sroa.5.0..sroa_idx.i.i.i, align 8, !noalias !2147
  %_7.sroa.6.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %562, i64 24
  store ptr %_12.sroa.0.0.i.i, ptr %_7.sroa.6.0..sroa_idx.i.i.i, align 8, !noalias !2147
  %564 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2197
  %565 = icmp eq ptr %564, null
  br i1 %565, label %bb2.i.i7.i.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i, !prof !1319

bb2.i.i7.i.i:                                     ; preds = %_ZN6matrix6number17heeef4114a060e7afE.exit.i.i
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2197
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i:   ; preds = %_ZN6matrix6number17heeef4114a060e7afE.exit.i.i
  store i64 1, ptr %564, align 8, !noalias !2147
  %_7.sroa.4.0..sroa_idx.i4.i.i = getelementptr inbounds nuw i8, ptr %564, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i4.i.i, align 8, !noalias !2147
  %_7.sroa.5.0..sroa_idx.i5.i.i = getelementptr inbounds nuw i8, ptr %564, i64 16
  store ptr %562, ptr %_7.sroa.5.0..sroa_idx.i5.i.i, align 8, !noalias !2147
  %_7.sroa.6.0..sroa_idx.i6.i.i = getelementptr inbounds nuw i8, ptr %564, i64 24
  store ptr %rows.sroa.0.012.i.i, ptr %_7.sroa.6.0..sroa_idx.i6.i.i, align 8, !noalias !2147
  %566 = getelementptr inbounds nuw i8, ptr %557, i64 24
  %567 = load ptr, ptr %566, align 8, !noalias !2147, !noundef !31
  %.not.i.i = icmp eq ptr %567, null
  br i1 %.not.i.i, label %bb7.i.i, label %bb4.i.i

bb13.i.i:                                         ; preds = %bb12.i.i
  call void @llvm.trap()
  unreachable

bb15.i.i:                                         ; preds = %bb12.i.i
  %_18.i.i = load ptr, ptr %558, align 8, !noalias !2147, !nonnull !31, !noundef !31
  br label %bb9.i.i

bb12.i:                                           ; preds = %bb1.i.i.i6.i, %bb7.i.i
  %568 = phi ptr [ %.pre.i, %bb1.i.i.i6.i ], [ %.lcssa634, %bb7.i.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %generated.i.i), !noalias !2147
  store ptr %.lcssa674, ptr %rows.i, align 8, !noalias !2147
  call void @llvm.lifetime.start.p0(ptr nonnull %best.i), !noalias !2147
  store i64 -1, ptr %468, align 8, !noalias !2147
  store i64 0, ptr %469, align 8, !noalias !2147
  store i64 0, ptr %best.i, align 8, !noalias !2147
  store ptr inttoptr (i64 8 to ptr), ptr %_11.sroa.4.0.best.sroa_idx.i, align 8, !noalias !2147
  %.not1.i = icmp eq ptr %568, null
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %_11.sroa.5.0.best.sroa_idx.i, i8 0, i64 16, i1 false), !noalias !2147
  br i1 %.not1.i, label %bb13.i, label %bb15.i

bb11.i:                                           ; preds = %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit.i.i"
  call void @llvm.lifetime.end.p0(ptr nonnull %generated.i.i), !noalias !2147
; call core::option::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_333d7a08163f471ada98a08cf0b91484) #104, !noalias !2147
  unreachable

bb15.i:                                           ; preds = %bb12.i
  %_28.i = load i64, ptr %568, align 8, !noalias !2147, !noundef !31
  %_29.i12 = icmp ne i64 %_28.i, 0
  call void @llvm.assume(i1 %_29.i12)
  %_30.i = add i64 %_28.i, 1
  store i64 %_30.i, ptr %568, align 8, !noalias !2147
  %569 = icmp eq i64 %_30.i, 0
  br i1 %569, label %bb16.i, label %bb18.i, !prof !1319

bb13.i:                                           ; preds = %bb18.i, %bb12.i
  %_15.sroa.0.0.i = phi ptr [ %_25.i, %bb18.i ], [ null, %bb12.i ]
  %570 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2200
  %571 = icmp eq ptr %570, null
  br i1 %571, label %bb2.i.i8.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i, !prof !1319

bb2.i.i8.i:                                       ; preds = %bb13.i
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2200
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i:     ; preds = %bb13.i
  store i64 1, ptr %570, align 8, !noalias !2147
  %_7.sroa.4.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %570, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i, align 8, !noalias !2147
  %_7.sroa.5.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %570, i64 16
  store ptr %_15.sroa.0.0.i, ptr %_7.sroa.5.0..sroa_idx.i.i, align 8, !noalias !2147
  %_7.sroa.6.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %570, i64 24
  store ptr null, ptr %_7.sroa.6.0..sroa_idx.i.i, align 8, !noalias !2147
  %572 = load ptr, ptr %_7.sroa.6.0..sroa_idx.i6.i.i.le, align 8, !noalias !2147, !noundef !31
  %.not2.i = icmp eq ptr %572, null
  br i1 %.not2.i, label %bb2.i.i, label %bb21.i

bb16.i:                                           ; preds = %bb15.i
  call void @llvm.trap()
  unreachable

bb18.i:                                           ; preds = %bb15.i
  %_25.i = load ptr, ptr %_7.sroa.5.0..sroa_idx.i5.i.i.le, align 8, !noalias !2147, !nonnull !31, !noundef !31
  br label %bb13.i

bb21.i:                                           ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i
  %_42.i = load i64, ptr %572, align 8, !noalias !2147, !noundef !31
  %_43.i = icmp ne i64 %_42.i, 0
  call void @llvm.assume(i1 %_43.i)
  %_44.i = add i64 %_42.i, 1
  store i64 %_44.i, ptr %572, align 8, !noalias !2147
  %573 = icmp eq i64 %_44.i, 0
  br i1 %573, label %bb22.i, label %bb24.i, !prof !1319

bb2.i.i:                                          ; preds = %bb24.i, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i
  %_16.sroa.0.0.i = phi ptr [ %_39.i, %bb24.i ], [ null, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i ]
; call matrix::search
  call fastcc void @_ZN6matrix6search17hc085af21f9aa784aE(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field.i, i64 noundef %_20, i64 noundef 1, ptr noundef nonnull %570, ptr noundef %_16.sroa.0.0.i, ptr noalias noundef align 8 dereferenceable(48) %best.i) #65, !noalias !2147
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %_18, ptr noundef nonnull align 8 dereferenceable(32) %best.i, i64 32, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %best.i), !noalias !2147
  %_8.i.i9.i = load i64, ptr %.lcssa674, align 8, !noalias !2203, !noundef !31
  %val.i.i.i = add i64 %_8.i.i9.i, -1
  store i64 %val.i.i.i, ptr %.lcssa674, align 8, !noalias !2203
  %574 = icmp eq i64 %val.i.i.i, 0
  br i1 %574, label %bb1.i.i.i, label %_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit

bb1.i.i.i:                                        ; preds = %bb2.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %rows.i) #103, !noalias !2147
  br label %_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit

bb22.i:                                           ; preds = %bb21.i
  call void @llvm.trap()
  unreachable

bb24.i:                                           ; preds = %bb21.i
  %_39.i = load ptr, ptr %_7.sroa.6.0..sroa_idx.i6.i.i.le, align 8, !noalias !2147, !nonnull !31, !noundef !31
  br label %bb2.i.i

_ZN6matrix9really_go17h606f3b2a1fbb209eE.exit:    ; preds = %bb2.i.i, %bb1.i.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %rows.i), !noalias !2147
  call void @free(ptr noundef nonnull %545) #65, !dbg !1104
  call void @llvm.lifetime.end.p0(ptr nonnull %field.i), !noalias !2147
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %_17, ptr noundef nonnull align 8 dereferenceable(32) %_18, i64 32, i1 false)
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %_17) #65, !srcloc !30
  call void @llvm.lifetime.end.p0(ptr nonnull %_18)
; call core::ptr::drop_in_place<alloc::collections::vec_deque::VecDeque<matrix::Answer>>
  call fastcc void @"_ZN4core3ptr82drop_in_place$LT$alloc..collections..vec_deque..VecDeque$LT$matrix..Answer$GT$$GT$17h02813d3d402b9506E"(ptr noalias noundef align 8 dereferenceable(32) %result) #65
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(32) %result, ptr noundef nonnull align 8 dereferenceable(32) %_17, i64 32, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %_17)
  %exitcond.not = icmp eq i64 %_56, %count
  br i1 %exitcond.not, label %bb26.loopexit, label %bb25

bb13:                                             ; preds = %bb15.i.i.i.i305, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i308, %bb2.i254, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i306", %bb14.i.i.i.i302, %bb4.i.i.i.i307, %bb6.i.i.i.i280, %bb11.i.i.i.i283, %bb6.i.i.i.i.i291, %bb11.i.i.i.i.i294, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i366, %bb2.i312, %bb15.i.i.i.i363, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i364", %bb14.i.i.i.i360, %bb4.i.i.i.i365, %bb6.i.i.i.i338, %bb11.i.i.i.i341, %bb6.i.i.i.i.i349, %bb11.i.i.i.i.i352, %_ZN4core3cmp9PartialEq2ne17hd6762637742c8e6fE.exit.i, %bb2.i239, %bb15.i.i.i.i250, %"_ZN55_$LT$matrix..Number$u20$as$u20$core..cmp..PartialEq$GT$2eq17h634466f3fa9bdf2fE.exit.i.i.i.i", %bb14.i.i.i.i, %bb4.i.i.i.i, %bb6.i.i.i.i, %bb11.i.i.i.i247, %bb6.i.i.i.i.i, %bb11.i.i.i.i.i, %"_ZN63_$LT$A$u20$as$u20$core..slice..cmp..SlicePartialEq$LT$B$GT$$GT$17equal_same_length17hc2049eaf5f41d90eE.exit368", %bb3.i, %bb26
; call core::panicking::assert_failed
  call fastcc void @_ZN4core9panicking13assert_failed17h9f6e58448afdc9bfE(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %result, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %expected) #104
  unreachable

bb12:                                             ; preds = %bb2.i, %bb3.i, %"_ZN63_$LT$A$u20$as$u20$core..slice..cmp..SlicePartialEq$LT$B$GT$$GT$17equal_same_length17hc2049eaf5f41d90eE.exit368"
  call void @llvm.lifetime.start.p0(ptr nonnull %result.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %name.i)
  store ptr @alloc_76dcdf6735f0b66add99f993d9488ecf, ptr %name.i, align 8, !noalias !2208
  %575 = getelementptr inbounds nuw i8, ptr %name.i, i64 8
  store i64 6, ptr %575, align 8, !noalias !2208
  store i64 %count, ptr %count.i, align 8, !noalias !2208
  store ptr %result, ptr %result.i, align 8, !noalias !2208
  call void @llvm.lifetime.start.p0(ptr nonnull %seconds.i), !noalias !2208
; call <std::sys::pal::unix::time::Timespec>::now
  %576 = call fastcc { i64, i32 } @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec3now() #65, !dbg !2211
  %577 = extractvalue { i64, i32 } %576, 0, !dbg !2215
  %578 = extractvalue { i64, i32 } %576, 1, !dbg !2215
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store i64 %577, ptr %2, align 8
  %579 = getelementptr inbounds nuw i8, ptr %2, i64 8
  store i32 %578, ptr %579, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %1), !noalias !2216
  store i64 %start.0, ptr %1, align 8, !noalias !2219
  %580 = getelementptr inbounds nuw i8, ptr %1, i64 8
  store i32 %start.1, ptr %580, align 8, !noalias !2219
  call void @llvm.lifetime.start.p0(ptr nonnull %0), !dbg !2222, !noalias !2232
; call <std::sys::pal::unix::time::Timespec>::sub_timespec
  call fastcc void @_RNvMNtNtNtNtCsjrHSEGnQ3l9_3std3sys3pal4unix4timeNtB2_8Timespec12sub_timespec(ptr noalias noundef align 8 captures(none) dereferenceable(24) %0, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %2, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %1) #65, !dbg !2236
  %581 = load i64, ptr %0, align 8, !dbg !2237, !range !954, !noalias !2232, !noundef !31
  %582 = trunc nuw i64 %581 to i1, !dbg !2240
  %583 = getelementptr inbounds nuw i8, ptr %0, i64 8, !dbg !2240
  %584 = load i64, ptr %583, align 8, !dbg !2240, !noalias !2232
  %585 = getelementptr inbounds nuw i8, ptr %0, i64 16, !dbg !2240
  %586 = load i32, ptr %585, align 8, !dbg !2240, !range !2241, !noalias !2232
  call void @llvm.lifetime.end.p0(ptr nonnull %0), !dbg !2242, !noalias !2232
  call void @llvm.lifetime.end.p0(ptr nonnull %1), !dbg !2243, !noalias !2216
  call void @llvm.lifetime.end.p0(ptr nonnull %2), !dbg !2244
  %587 = uitofp i64 %584 to double
  %588 = uitofp nneg i32 %586 to double
  %589 = fdiv double %588, 1.000000e+09
  %590 = fadd double %589, %587
  %591 = select i1 %582, double 0.000000e+00, double %590
  store double %591, ptr %seconds.i, align 8, !noalias !2208
  call void @llvm.lifetime.start.p0(ptr nonnull %args.i), !noalias !2208
  store ptr %result.i, ptr %args.i, align 8, !noalias !2208
  %_12.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args.i, i64 8
  store ptr @"_ZN54_$LT$matrix..Results$u20$as$u20$core..fmt..Display$GT$3fmt17h776dc9917b9d3e68E", ptr %_12.sroa.4.0..sroa_idx.i, align 8, !noalias !2208
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_1411a66fb3eebd1e386b0f09aa6c2612, ptr noundef nonnull %args.i) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %args.i), !noalias !2208
  call void @llvm.lifetime.start.p0(ptr nonnull %args2.i), !noalias !2208
  store ptr %name.i, ptr %args2.i, align 8, !noalias !2208
  %_20.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 8
  store ptr @"_ZN44_$LT$$RF$T$u20$as$u20$core..fmt..Display$GT$3fmt17h01e2ab774ae21dacE", ptr %_20.sroa.4.0..sroa_idx.i, align 8, !noalias !2208
  %592 = getelementptr inbounds nuw i8, ptr %args2.i, i64 16
  store ptr %count.i, ptr %592, align 8, !noalias !2208
  %_21.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 24
  store ptr @_RNvXsd_NtNtNtCsgEmfK2I1SDS_4core3fmt3num3impyNtB9_7Display3fmt, ptr %_21.sroa.4.0..sroa_idx.i, align 8, !noalias !2208
  %593 = getelementptr inbounds nuw i8, ptr %args2.i, i64 32
  store ptr %seconds.i, ptr %593, align 8, !noalias !2208
  %_22.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %args2.i, i64 40
  store ptr @_RNvXs7_NtNtCsgEmfK2I1SDS_4core3fmt5floatdNtB7_7Display3fmt, ptr %_22.sroa.4.0..sroa_idx.i, align 8, !noalias !2208
; call std::io::stdio::_print
  call fastcc void @_RNvNtNtCsjrHSEGnQ3l9_3std2io5stdio6__print(ptr noundef nonnull @alloc_425ac0839427cedeadf73b1b30f184e4, ptr noundef nonnull %args2.i) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %args2.i), !noalias !2208
  call void @llvm.lifetime.end.p0(ptr nonnull %seconds.i), !noalias !2208
  call void @llvm.lifetime.end.p0(ptr nonnull %result.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %count.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %name.i)
; call core::ptr::drop_in_place<alloc::collections::vec_deque::VecDeque<matrix::Answer>>
  call fastcc void @"_ZN4core3ptr82drop_in_place$LT$alloc..collections..vec_deque..VecDeque$LT$matrix..Answer$GT$$GT$17h02813d3d402b9506E"(ptr noalias noundef align 8 dereferenceable(32) %result) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %result)
; call core::ptr::drop_in_place<alloc::collections::vec_deque::VecDeque<matrix::Answer>>
  call fastcc void @"_ZN4core3ptr82drop_in_place$LT$alloc..collections..vec_deque..VecDeque$LT$matrix..Answer$GT$$GT$17h02813d3d402b9506E"(ptr noalias noundef align 8 dereferenceable(32) %expected) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %expected)
  br label %bb2.i.i13

bb2.i.i13:                                        ; preds = %bb12, %bb2.i.i13
  %_3.sroa.0.04.i.i = phi i64 [ %594, %bb2.i.i13 ], [ 0, %bb12 ]
  %_6.i.i14 = getelementptr inbounds nuw %"r7rs_wasm_reference::Datum", ptr %_3.sroa.6.1, i64 %_3.sroa.0.04.i.i
  %594 = add nuw i64 %_3.sroa.0.04.i.i, 1
; call core::ptr::drop_in_place<r7rs_wasm_reference::Datum>
  call fastcc void @"_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17hd7f91847157f5d4fE"(ptr noalias noundef readonly align 8 dereferenceable(32) %_6.i.i14) #65, !noalias !2245
  %_7.i.i = icmp eq i64 %594, %_3.sroa.9.1
  br i1 %_7.i.i, label %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17hdf48e952c6ebe50eE.exit.i", label %bb2.i.i13

"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17hdf48e952c6ebe50eE.exit.i": ; preds = %bb2.i.i13
  %595 = icmp eq i64 %_3.sroa.0.1, 0
  br i1 %595, label %bb18, label %bb2.i.i.i.i15

bb2.i.i.i.i15:                                    ; preds = %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17hdf48e952c6ebe50eE.exit.i"
  call void @free(ptr noundef nonnull %_3.sroa.6.1) #65, !dbg !1104
  br label %bb18

bb18:                                             ; preds = %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread, %bb2.i.i.i.i15, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17hdf48e952c6ebe50eE.exit.i"
  %_0.sroa.0.0 = phi ptr [ null, %bb2.i.i.i.i15 ], [ null, %"_ZN4core3ptr57drop_in_place$LT$$u5b$r7rs_wasm_reference..Datum$u5d$$GT$17hdf48e952c6ebe50eE.exit.i" ], [ %116, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit.thread ], [ %_3.sroa.6.1, %_ZN19r7rs_wasm_reference5input17hc399d3c69a252ce0E.exit ]
  ret ptr %_0.sroa.0.0
}
