define internal fastcc void @_ZN6matrix6search17hc085af21f9aa784aE(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, i64 noundef range(i64 2, 0) %inv_size, i64 noundef %count, ptr noundef nonnull %0, ptr noundef %1, ptr noalias noundef nonnull align 8 captures(none) dereferenceable(48) %best) unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %cursor.i = alloca [24 x i8], align 8
  %_20.i115 = alloca [24 x i8], align 8
  %_11.i = alloca [24 x i8], align 8
  %first.i = alloca [16 x i8], align 8
  %rows.i = alloca [8 x i8], align 8
  %reversed.i = alloca [8 x i8], align 8
  %_18.i = alloca [24 x i8], align 8
  %tests.i = alloca [32 x i8], align 8
  %_24 = alloca [8 x i8], align 8
  %candidate = alloca [8 x i8], align 8
  %next = alloca [8 x i8], align 8
  %_12 = alloca [32 x i8], align 8
  %future = alloca [8 x i8], align 8
  %rows = alloca [8 x i8], align 8
  store ptr %0, ptr %rows, align 8
  store ptr %1, ptr %future, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %tests.i)
  %_5.i = icmp ult i64 %count, %inv_size
  br i1 %_5.i, label %bb10.i, label %bb15.i

bb15.i:                                           ; preds = %start
  %2 = getelementptr inbounds nuw i8, ptr %tests.i, i64 16
  store i64 0, ptr %tests.i, align 8, !noalias !2369
  %3 = getelementptr inbounds nuw i8, ptr %tests.i, i64 8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %2, i8 0, i64 16, i1 false), !noalias !2369
  store ptr inttoptr (i64 8 to ptr), ptr %3, align 8, !noalias !2369
  %_12.i = getelementptr inbounds nuw i8, ptr %0, i64 16
  %_13.i = getelementptr inbounds nuw i8, ptr %0, i64 24
  %_14.i = add i64 %inv_size, -2
  %4 = load ptr, ptr %_13.i, align 8, !noalias !2369, !noundef !31
  %.not21.i = icmp eq ptr %4, null
  br i1 %.not21.i, label %bb16.i, label %bb18.i

bb18.i:                                           ; preds = %bb15.i, %bb18.i
  %5 = phi ptr [ %8, %bb18.i ], [ %4, %bb15.i ]
  %_15.sroa.0.02.i = phi i64 [ %6, %bb18.i ], [ 0, %bb15.i ]
  %6 = add i64 %_15.sroa.0.02.i, 1
  %7 = getelementptr inbounds nuw i8, ptr %5, i64 24
  %8 = load ptr, ptr %7, align 8, !noalias !2369, !noundef !31
  %.not2.i = icmp eq ptr %8, null
  br i1 %.not2.i, label %bb16.i, label %bb18.i

bb16.i:                                           ; preds = %bb18.i, %bb15.i
  %_15.sroa.0.0.lcssa.i = phi i64 [ 0, %bb15.i ], [ %6, %bb18.i ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_18.i), !noalias !2369
  store i64 0, ptr %_18.i, align 8, !noalias !2369
  %9 = getelementptr inbounds nuw i8, ptr %_18.i, i64 8
  store ptr inttoptr (i64 8 to ptr), ptr %9, align 8, !noalias !2369
  %10 = getelementptr inbounds nuw i8, ptr %_18.i, i64 16
  store i64 0, ptr %10, align 8, !noalias !2369
; call matrix::collect_tests
  call fastcc void @_ZN6matrix13collect_tests17h1cc028c08694081aE(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_12.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_13.i, i64 noundef %_14.i, i64 noundef %_15.sroa.0.0.lcssa.i, ptr noalias noundef align 8 dereferenceable(24) %_18.i, ptr noalias noundef align 8 dereferenceable(32) %tests.i) #65, !noalias !2373
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2374)
  %_1.val.i.i = load ptr, ptr %9, align 8, !alias.scope !2374, !noalias !2369, !nonnull !31, !noundef !31
  %_1.val1.i.i = load i64, ptr %10, align 8, !alias.scope !2374, !noalias !2369, !noundef !31
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2377)
  %_73.i.i.i.i = icmp eq i64 %_1.val1.i.i, 0
  br i1 %_73.i.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h7dca6b94bcf64764E.exit.i.i", label %bb2.i.i.i.i

bb2.i.i.i.i:                                      ; preds = %bb16.i, %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i"
  %_3.sroa.0.04.i.i.i.i = phi i64 [ %11, %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i" ], [ 0, %bb16.i ]
  %_6.i.i.i.i = getelementptr inbounds nuw ptr, ptr %_1.val.i.i, i64 %_3.sroa.0.04.i.i.i.i
  %11 = add nuw i64 %_3.sroa.0.04.i.i.i.i, 1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2380)
  %12 = load ptr, ptr %_6.i.i.i.i, align 8, !alias.scope !2383, !noalias !2384, !noundef !31
  %13 = icmp eq ptr %12, null
  br i1 %13, label %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i", label %bb2.i.i.i.i.i

bb2.i.i.i.i.i:                                    ; preds = %bb2.i.i.i.i
  %_8.i.i.i.i.i.i = load i64, ptr %12, align 8, !noalias !2385, !noundef !31
  %val.i.i.i.i.i.i = add i64 %_8.i.i.i.i.i.i, -1
  store i64 %val.i.i.i.i.i.i, ptr %12, align 8, !noalias !2385
  %14 = icmp eq i64 %val.i.i.i.i.i.i, 0
  br i1 %14, label %bb1.i.i.i.i.i.i, label %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i"

bb1.i.i.i.i.i.i:                                  ; preds = %bb2.i.i.i.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  tail call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0947af3e06b231f7E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_6.i.i.i.i) #103, !noalias !2384
  br label %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i"

"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i": ; preds = %bb1.i.i.i.i.i.i, %bb2.i.i.i.i.i, %bb2.i.i.i.i
  %_7.i.i.i.i = icmp eq i64 %11, %_1.val1.i.i
  br i1 %_7.i.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h7dca6b94bcf64764E.exit.i.i", label %bb2.i.i.i.i

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h7dca6b94bcf64764E.exit.i.i": ; preds = %"_ZN4core3ptr84drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$17h664ee56c6d7c1bd8E.exit.i.i.i.i", %bb16.i
  %_1.val2.i.i = load i64, ptr %_18.i, align 8, !range !1117, !alias.scope !2374, !noalias !2369, !noundef !31
  %15 = icmp eq i64 %_1.val2.i.i, 0
  br i1 %15, label %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i", label %bb2.i.i.i4.i.i

bb2.i.i.i4.i.i:                                   ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h7dca6b94bcf64764E.exit.i.i"
  tail call void @free(ptr noundef nonnull %_1.val.i.i) #65, !dbg !1104
  br label %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i"

"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i": ; preds = %bb2.i.i.i4.i.i, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h7dca6b94bcf64764E.exit.i.i"
  call void @llvm.lifetime.end.p0(ptr nonnull %_18.i), !noalias !2369
  %tester.sroa.0.0.copyload149 = load i64, ptr %tests.i, align 8, !noalias !2388
  %tester.sroa.7.0.copyload150 = load ptr, ptr %3, align 8, !noalias !2388
  %tester.sroa.9.0.copyload151 = load i64, ptr %2, align 8, !noalias !2388
  %tester.sroa.10.0.tests.i.sroa_idx = getelementptr inbounds nuw i8, ptr %tests.i, i64 24
  %tester.sroa.10.0.copyload152 = load i64, ptr %tester.sroa.10.0.tests.i.sroa_idx, align 8, !noalias !2388
  br label %_ZN6matrix11make_tester17hfad29fce983c4295E.exit

bb10.i:                                           ; preds = %start
  %_25.i = load i64, ptr %0, align 8, !noalias !2369, !noundef !31
  %_26.i = icmp ne i64 %_25.i, 0
  tail call void @llvm.assume(i1 %_26.i)
  %_27.i = add i64 %_25.i, 1
  store i64 %_27.i, ptr %0, align 8, !noalias !2369
  %16 = icmp eq i64 %_27.i, 0
  br i1 %16, label %bb11.i, label %bb7.i, !prof !1319

bb7.i:                                            ; preds = %bb10.i
; call matrix::row_reduce
  %_6.i430 = tail call fastcc noundef ptr @_ZN6matrix10row_reduce17h00edd7e88ae65d79E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noundef nonnull %0) #65, !noalias !2373
  br label %_ZN6matrix11make_tester17hfad29fce983c4295E.exit

bb11.i:                                           ; preds = %bb10.i
  tail call void @llvm.trap()
  unreachable

_ZN6matrix11make_tester17hfad29fce983c4295E.exit: ; preds = %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i", %bb7.i
  %tester.sroa.10.0 = phi i64 [ undef, %bb7.i ], [ %tester.sroa.10.0.copyload152, %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i" ]
  %tester.sroa.9.0 = phi i64 [ undef, %bb7.i ], [ %tester.sroa.9.0.copyload151, %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i" ]
  %tester.sroa.7.0 = phi ptr [ %_6.i430, %bb7.i ], [ %tester.sroa.7.0.copyload150, %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i" ]
  %tester.sroa.0.0 = phi i64 [ -9223372036854775808, %bb7.i ], [ %tester.sroa.0.0.copyload149, %"_ZN4core3ptr107drop_in_place$LT$alloc..vec..Vec$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17h0ce578703d75ba70E.exit.i" ]
  call void @llvm.lifetime.end.p0(ptr nonnull %tests.i)
  %17 = getelementptr inbounds nuw i8, ptr %field, i64 24
  %field.val = load i64, ptr %17, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %reversed.i), !noalias !2389
  store ptr null, ptr %reversed.i, align 8, !noalias !2389
  %.not21.i7 = icmp eq ptr %1, null
  br i1 %.not21.i7, label %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit, label %bb2.lr.ph.i

bb2.lr.ph.i:                                      ; preds = %_ZN6matrix11make_tester17hfad29fce983c4295E.exit
  %.not.i.i = icmp eq i64 %tester.sroa.0.0, -9223372036854775808
  %18 = icmp eq i64 %tester.sroa.10.0, 0
  %_27.not.i.i.i.i = icmp ult i64 %tester.sroa.9.0, %tester.sroa.0.0
  %19 = select i1 %_27.not.i.i.i.i, i64 0, i64 %tester.sroa.0.0
  %wrapped_start.sroa.0.0.i.i.i.i = sub nuw i64 %tester.sroa.9.0, %19
  %head_len.i.i.i.i = sub i64 %tester.sroa.0.0, %wrapped_start.sroa.0.0.i.i.i.i
  %_13.not.i.i.i.i = icmp ult i64 %head_len.i.i.i.i, %tester.sroa.10.0
  %_16.i.i.i.i = add i64 %wrapped_start.sroa.0.0.i.i.i.i, %tester.sroa.10.0
  %tail_len.i.i.i.i = sub nuw i64 %tester.sroa.10.0, %head_len.i.i.i.i
  %20 = shl nuw nsw i64 %tail_len.i.i.i.i, 3
  %_4.sroa.5.0.i.i.i = select i1 %_13.not.i.i.i.i, i64 %tester.sroa.0.0, i64 %_16.i.i.i.i
  %_4.sroa.11.0.i.i.i = select i1 %_13.not.i.i.i.i, i64 %20, i64 0
  %_10.i.i.i = getelementptr inbounds nuw ptr, ptr %tester.sroa.7.0, i64 %wrapped_start.sroa.0.0.i.i.i.i
  %_25.i.i.i = getelementptr inbounds nuw ptr, ptr %tester.sroa.7.0, i64 %_4.sroa.5.0.i.i.i
  %_33.i.i.i = getelementptr inbounds nuw i8, ptr %tester.sroa.7.0, i64 %_4.sroa.11.0.i.i.i
  %_6.i.not.not.not.i.not.us.i.i.i = icmp samesign eq i64 %wrapped_start.sroa.0.0.i.i.i.i, %_4.sroa.5.0.i.i.i
  %_6.i.not.not.not.i7.not.us.not.i.i.i = icmp samesign eq i64 %_4.sroa.11.0.i.i.i, 0
  br i1 %.not.i.i, label %bb2.lr.ph.split.us.i, label %bb2.i

bb2.lr.ph.split.us.i:                             ; preds = %bb2.lr.ph.i
  %.not1.i.i = icmp eq ptr %tester.sroa.7.0, null
  br i1 %.not1.i.i, label %bb2.us.us.i, label %bb2.us.i

bb2.us.us.i:                                      ; preds = %bb2.lr.ph.split.us.i, %bb6.us.us.i
  %21 = phi ptr [ %31, %bb6.us.us.i ], [ %1, %bb2.lr.ph.split.us.i ]
  %22 = phi ptr [ %29, %bb6.us.us.i ], [ null, %bb2.lr.ph.split.us.i ]
  %_8.us.us.i = getelementptr inbounds nuw i8, ptr %21, i64 16
  %_8.val.us.us.i = load ptr, ptr %_8.us.us.i, align 8, !noalias !2389
  %.fr.i.i.us.us.i = freeze ptr %_8.val.us.us.i
  %.not2.i.us.us.i = icmp eq ptr %.fr.i.i.us.us.i, null
  br i1 %.not2.i.us.us.i, label %bb6.us.us.i, label %bb15.i.us.us.i

bb15.i.us.us.i:                                   ; preds = %bb2.us.us.i
  %_29.i.us.us.i = load i64, ptr %.fr.i.i.us.us.i, align 8, !noundef !31
  %_30.i.us.us.i = icmp ne i64 %_29.i.us.us.i, 0
  tail call void @llvm.assume(i1 %_30.i.us.us.i)
  %_31.i.us.us.i = add i64 %_29.i.us.us.i, 1
  store i64 %_31.i.us.us.i, ptr %.fr.i.i.us.us.i, align 8
  %23 = icmp eq i64 %_31.i.us.us.i, 0
  br i1 %23, label %bb16.i.i, label %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.us.i, !prof !1319

_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.us.i: ; preds = %bb15.i.us.us.i
; call matrix::in_row_space
  %24 = tail call fastcc noundef zeroext i1 @_ZN6matrix12in_row_space17h77f24828cb07760aE(i64 %field.val, ptr noundef null, ptr noundef nonnull %.fr.i.i.us.us.i) #65
  br i1 %24, label %bb6.us.us.i, label %bb4.us.us.i

bb4.us.us.i:                                      ; preds = %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.us.i
  %25 = load ptr, ptr %_8.us.us.i, align 8, !noalias !2389, !noundef !31
  %.not1.us.us.i = icmp eq ptr %25, null
  br i1 %.not1.us.us.i, label %bb10.us.us.i, label %bb13.us.us.i

bb13.us.us.i:                                     ; preds = %bb4.us.us.i
  %_20.us.us.i = load i64, ptr %25, align 8, !noalias !2389, !noundef !31
  %_21.us.us.i = icmp ne i64 %_20.us.us.i, 0
  tail call void @llvm.assume(i1 %_21.us.us.i)
  %_22.us.us.i = add i64 %_20.us.us.i, 1
  store i64 %_22.us.us.i, ptr %25, align 8, !noalias !2389
  %26 = icmp eq i64 %_22.us.us.i, 0
  br i1 %26, label %bb14.i12, label %bb16.us.us.i, !prof !1319

bb16.us.us.i:                                     ; preds = %bb13.us.us.i
  %_17.us.us.i = load ptr, ptr %_8.us.us.i, align 8, !noalias !2389, !nonnull !31, !noundef !31
  br label %bb10.us.us.i

bb10.us.us.i:                                     ; preds = %bb16.us.us.i, %bb4.us.us.i
  %_10.sroa.0.0.us.us.i = phi ptr [ %_17.us.us.i, %bb16.us.us.i ], [ null, %bb4.us.us.i ]
  %27 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2393
  %28 = icmp eq ptr %27, null
  br i1 %28, label %bb2.i.i.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.us.i, !prof !1319

_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.us.i: ; preds = %bb10.us.us.i
  store i64 1, ptr %27, align 8, !noalias !2389
  %_7.sroa.4.0..sroa_idx.i.us.us.i = getelementptr inbounds nuw i8, ptr %27, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.us.us.i, align 8, !noalias !2389
  %_7.sroa.5.0..sroa_idx.i.us.us.i = getelementptr inbounds nuw i8, ptr %27, i64 16
  store ptr %_10.sroa.0.0.us.us.i, ptr %_7.sroa.5.0..sroa_idx.i.us.us.i, align 8, !noalias !2389
  %_7.sroa.6.0..sroa_idx.i.us.us.i = getelementptr inbounds nuw i8, ptr %27, i64 24
  store ptr %22, ptr %_7.sroa.6.0..sroa_idx.i.us.us.i, align 8, !noalias !2389
  store ptr %27, ptr %reversed.i, align 8, !noalias !2389
  br label %bb6.us.us.i

bb6.us.us.i:                                      ; preds = %bb2.us.us.i, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.us.i, %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.us.i
  %29 = phi ptr [ %27, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.us.i ], [ %22, %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.us.i ], [ %22, %bb2.us.us.i ]
  %30 = getelementptr inbounds nuw i8, ptr %21, i64 24
  %31 = load ptr, ptr %30, align 8, !noalias !2389, !noundef !31
  %.not.us.us.i = icmp eq ptr %31, null
  br i1 %.not.us.us.i, label %bb7.i8, label %bb2.us.us.i

bb2.us.i:                                         ; preds = %bb2.lr.ph.split.us.i, %bb6.us.i
  %32 = phi ptr [ %43, %bb6.us.i ], [ %1, %bb2.lr.ph.split.us.i ]
  %33 = phi ptr [ %41, %bb6.us.i ], [ null, %bb2.lr.ph.split.us.i ]
  %_8.us.i = getelementptr inbounds nuw i8, ptr %32, i64 16
  %_8.val.us.i = load ptr, ptr %_8.us.i, align 8, !noalias !2389
  %.fr.i.i.us.i = freeze ptr %_8.val.us.i
  %_16.i.us.i = load i64, ptr %tester.sroa.7.0, align 8, !noalias !2396, !noundef !31
  %_17.i.us.i = icmp ne i64 %_16.i.us.i, 0
  tail call void @llvm.assume(i1 %_17.i.us.i)
  %_18.i.us.i = add i64 %_16.i.us.i, 1
  store i64 %_18.i.us.i, ptr %tester.sroa.7.0, align 8, !noalias !2396
  %34 = icmp eq i64 %_18.i.us.i, 0
  br i1 %34, label %bb10.i.i, label %bb7.i.us.i, !prof !1319

bb7.i.us.i:                                       ; preds = %bb2.us.i
  %.not2.i.us.i = icmp eq ptr %.fr.i.i.us.i, null
  br i1 %.not2.i.us.i, label %bb2.i.i486, label %bb15.i.us.i

bb2.i.i486:                                       ; preds = %bb7.i.us.i
  store i64 %_16.i.us.i, ptr %tester.sroa.7.0, align 8, !noalias !2399
  br label %bb6.us.i

bb15.i.us.i:                                      ; preds = %bb7.i.us.i
  %_29.i.us.i = load i64, ptr %.fr.i.i.us.i, align 8, !noundef !31
  %_30.i.us.i = icmp ne i64 %_29.i.us.i, 0
  tail call void @llvm.assume(i1 %_30.i.us.i)
  %_31.i.us.i = add i64 %_29.i.us.i, 1
  store i64 %_31.i.us.i, ptr %.fr.i.i.us.i, align 8
  %35 = icmp eq i64 %_31.i.us.i, 0
  br i1 %35, label %bb16.i.i, label %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.i, !prof !1319

_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.i: ; preds = %bb15.i.us.i
; call matrix::in_row_space
  %36 = tail call fastcc noundef zeroext i1 @_ZN6matrix12in_row_space17h77f24828cb07760aE(i64 %field.val, ptr noundef nonnull %tester.sroa.7.0, ptr noundef nonnull %.fr.i.i.us.i) #65
  br i1 %36, label %bb6.us.i, label %bb4.us.i

bb4.us.i:                                         ; preds = %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.i
  %37 = load ptr, ptr %_8.us.i, align 8, !noalias !2389, !noundef !31
  %.not1.us.i = icmp eq ptr %37, null
  br i1 %.not1.us.i, label %bb10.us.i, label %bb13.us.i

bb13.us.i:                                        ; preds = %bb4.us.i
  %_20.us.i = load i64, ptr %37, align 8, !noalias !2389, !noundef !31
  %_21.us.i = icmp ne i64 %_20.us.i, 0
  tail call void @llvm.assume(i1 %_21.us.i)
  %_22.us.i = add i64 %_20.us.i, 1
  store i64 %_22.us.i, ptr %37, align 8, !noalias !2389
  %38 = icmp eq i64 %_22.us.i, 0
  br i1 %38, label %bb14.i12, label %bb16.us.i, !prof !1319

bb16.us.i:                                        ; preds = %bb13.us.i
  %_17.us.i = load ptr, ptr %_8.us.i, align 8, !noalias !2389, !nonnull !31, !noundef !31
  br label %bb10.us.i

bb10.us.i:                                        ; preds = %bb16.us.i, %bb4.us.i
  %_10.sroa.0.0.us.i = phi ptr [ %_17.us.i, %bb16.us.i ], [ null, %bb4.us.i ]
  %39 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2393
  %40 = icmp eq ptr %39, null
  br i1 %40, label %bb2.i.i.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.i, !prof !1319

_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.i:  ; preds = %bb10.us.i
  store i64 1, ptr %39, align 8, !noalias !2389
  %_7.sroa.4.0..sroa_idx.i.us.i = getelementptr inbounds nuw i8, ptr %39, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.us.i, align 8, !noalias !2389
  %_7.sroa.5.0..sroa_idx.i.us.i = getelementptr inbounds nuw i8, ptr %39, i64 16
  store ptr %_10.sroa.0.0.us.i, ptr %_7.sroa.5.0..sroa_idx.i.us.i, align 8, !noalias !2389
  %_7.sroa.6.0..sroa_idx.i.us.i = getelementptr inbounds nuw i8, ptr %39, i64 24
  store ptr %33, ptr %_7.sroa.6.0..sroa_idx.i.us.i, align 8, !noalias !2389
  store ptr %39, ptr %reversed.i, align 8, !noalias !2389
  br label %bb6.us.i

bb6.us.i:                                         ; preds = %bb2.i.i486, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.i, %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.i
  %41 = phi ptr [ %39, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.us.i ], [ %33, %_ZN6matrix6Tester8contains17h0bf8a920431f2f68E.exit.us.i ], [ %33, %bb2.i.i486 ]
  %42 = getelementptr inbounds nuw i8, ptr %32, i64 24
  %43 = load ptr, ptr %42, align 8, !noalias !2389, !noundef !31
  %.not.us.i = icmp eq ptr %43, null
  br i1 %.not.us.i, label %bb7.i8, label %bb2.us.i

bb2.i:                                            ; preds = %bb2.lr.ph.i, %bb6.i
  %44 = phi ptr [ %63, %bb6.i ], [ %1, %bb2.lr.ph.i ]
  %45 = phi ptr [ %61, %bb6.i ], [ null, %bb2.lr.ph.i ]
  %_8.i = getelementptr inbounds nuw i8, ptr %44, i64 16
  %_8.val.i = load ptr, ptr %_8.i, align 8, !noalias !2389
  %.fr.i.i.i = freeze ptr %_8.val.i
  %.not1.i.i.i.i.i11.i.i = icmp eq ptr %.fr.i.i.i, null
  br i1 %18, label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i", label %bb3.i.i.i.i

bb3.i.i.i.i:                                      ; preds = %bb2.i
  br i1 %.not1.i.i.i.i.i11.i.i, label %bb1.i.us.i.i.i, label %bb1.i.i.preheader.i.i

"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i": ; preds = %bb2.i
  br i1 %.not1.i.i.i.i.i11.i.i, label %bb10.i11, label %bb1.i.i.preheader.i.i

bb1.i.i.preheader.i.i:                            ; preds = %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i", %bb3.i.i.i.i
  %_33.i20.i.i = phi ptr [ %tester.sroa.7.0, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i" ], [ %_33.i.i.i, %bb3.i.i.i.i ]
  %_25.i19.i.i = phi ptr [ %tester.sroa.7.0, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i" ], [ %_25.i.i.i, %bb3.i.i.i.i ]
  %_10.i18.i.i = phi ptr [ %tester.sroa.7.0, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i" ], [ %_10.i.i.i, %bb3.i.i.i.i ]
  br label %bb1.i.i.i.i

bb1.i.us.i.i.i:                                   ; preds = %bb3.i.i.i.i
  br i1 %_6.i.not.not.not.i.not.us.i.i.i, label %bb1.i5.us.i.i.i, label %bb3.i.us.i.i.i

bb3.i.us.i.i.i:                                   ; preds = %bb1.i.us.i.i.i
  %.val.i.us.i.i.i = load ptr, ptr %_10.i.i.i, align 8, !noalias !2404, !noundef !31
  %.not.i.i.i.i.us.i.i.i = icmp eq ptr %.val.i.us.i.i.i, null
  br i1 %.not.i.i.i.i.us.i.i.i, label %bb6.i, label %bb5.i.i.i.i.us.i.i.i

bb5.i.i.i.i.us.i.i.i:                             ; preds = %bb3.i.us.i.i.i
  %_11.i.i.i.i.us.i.i.i = load i64, ptr %.val.i.us.i.i.i, align 8, !noalias !2404, !noundef !31
  %_12.i.i.i.i.us.i.i.i = icmp ne i64 %_11.i.i.i.i.us.i.i.i, 0
  tail call void @llvm.assume(i1 %_12.i.i.i.i.us.i.i.i)
  %46 = icmp eq i64 %_11.i.i.i.i.us.i.i.i, -1
  br i1 %46, label %bb6.i.i.i.i.i.i.i, label %bb6.i, !prof !1319

bb1.i.i.i.i:                                      ; preds = %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i", %bb1.i.i.preheader.i.i
  %_16.i8.i.i.i.i = phi ptr [ %_16.i.i.i.i.i, %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i" ], [ %_10.i18.i.i, %bb1.i.i.preheader.i.i ]
  %_6.i.not.not.not.i.not.i.i.i = icmp eq ptr %_16.i8.i.i.i.i, %_25.i19.i.i
  br i1 %_6.i.not.not.not.i.not.i.i.i, label %bb1.i5.i.i.i, label %bb3.i.i3.i.i

bb3.i.i3.i.i:                                     ; preds = %bb1.i.i.i.i
  %_16.i.i.i.i.i = getelementptr inbounds nuw i8, ptr %_16.i8.i.i.i.i, i64 8
  %.val.i.i.i.i = load ptr, ptr %_16.i8.i.i.i.i, align 8, !noalias !2404, !noundef !31
  %.not.i.i.i.i.i.i.i = icmp eq ptr %.val.i.i.i.i, null
  br i1 %.not.i.i.i.i.i.i.i, label %bb2.i.i.i.i.i.i.i, label %bb5.i.i.i.i.i.i.i

bb5.i.i.i.i.i.i.i:                                ; preds = %bb3.i.i3.i.i
  %_11.i.i.i.i.i.i.i = load i64, ptr %.val.i.i.i.i, align 8, !noalias !2404, !noundef !31
  %_12.i.i.i.i.i.i.i = icmp ne i64 %_11.i.i.i.i.i.i.i, 0
  tail call void @llvm.assume(i1 %_12.i.i.i.i.i.i.i)
  %_13.i.i.i.i.i.i.i = add i64 %_11.i.i.i.i.i.i.i, 1
  store i64 %_13.i.i.i.i.i.i.i, ptr %.val.i.i.i.i, align 8, !noalias !2404
  %47 = icmp eq i64 %_13.i.i.i.i.i.i.i, 0
  br i1 %47, label %bb6.i.i.i.i.i.i.i, label %bb2.i.i.i.i.i.i.i, !prof !1319

bb2.i.i.i.i.i.i.i:                                ; preds = %bb5.i.i.i.i.i.i.i, %bb3.i.i3.i.i
  %_24.i.i.i.i.i.i.i = load i64, ptr %.fr.i.i.i, align 8, !noalias !2412, !noundef !31
  %_25.i.i.i.i.i.i.i = icmp ne i64 %_24.i.i.i.i.i.i.i, 0
  tail call void @llvm.assume(i1 %_25.i.i.i.i.i.i.i)
  %_26.i.i.i.i.i.i.i = add i64 %_24.i.i.i.i.i.i.i, 1
  store i64 %_26.i.i.i.i.i.i.i, ptr %.fr.i.i.i, align 8, !noalias !2412
  %48 = icmp eq i64 %_26.i.i.i.i.i.i.i, 0
  br i1 %48, label %bb12.i.i.i.i.i.i.i, label %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i", !prof !1319

bb6.i.i.i.i.i.i.i:                                ; preds = %bb5.i.i.i.i.us.i.i.i, %bb5.i.i.i.i.i.i.i
  tail call void @llvm.trap()
  unreachable

bb12.i.i.i.i.i.i.i:                               ; preds = %bb2.i.i.i.i.i.i.i
  tail call void @llvm.trap()
  unreachable

"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i": ; preds = %bb2.i.i.i.i.i.i.i
; call matrix::in_row_space
  %_0.i.i.i.i.i.i.i = tail call fastcc noundef zeroext i1 @_ZN6matrix12in_row_space17h77f24828cb07760aE(i64 %field.val, ptr noundef %.val.i.i.i.i, ptr noundef nonnull %.fr.i.i.i) #65, !noalias !2412
  br i1 %_0.i.i.i.i.i.i.i, label %bb6.i, label %bb1.i.i.i.i

bb1.i5.us.i.i.i:                                  ; preds = %bb1.i.us.i.i.i
  br i1 %_6.i.not.not.not.i7.not.us.not.i.i.i, label %bb10.i11, label %bb3.i8.us.i.i.i

bb3.i8.us.i.i.i:                                  ; preds = %bb1.i5.us.i.i.i
  %.val.i10.us.i.i.i = load ptr, ptr %tester.sroa.7.0, align 8, !noalias !2413, !noundef !31
  %.not.i.i.i.i11.us.i.i.i = icmp eq ptr %.val.i10.us.i.i.i, null
  br i1 %.not.i.i.i.i11.us.i.i.i, label %bb6.i, label %bb5.i.i.i.i12.us.i.i.i

bb5.i.i.i.i12.us.i.i.i:                           ; preds = %bb3.i8.us.i.i.i
  %_11.i.i.i.i13.us.i.i.i = load i64, ptr %.val.i10.us.i.i.i, align 8, !noalias !2413, !noundef !31
  %_12.i.i.i.i14.us.i.i.i = icmp ne i64 %_11.i.i.i.i13.us.i.i.i, 0
  tail call void @llvm.assume(i1 %_12.i.i.i.i14.us.i.i.i)
  %49 = icmp eq i64 %_11.i.i.i.i13.us.i.i.i, -1
  br i1 %49, label %bb6.i.i.i.i26.i.i.i, label %bb6.i, !prof !1319

bb1.i5.i.i.i:                                     ; preds = %bb1.i.i.i.i, %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i"
  %_16.i8.i6.i.i.i = phi ptr [ %_16.i.i9.i.i.i, %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i" ], [ %tester.sroa.7.0, %bb1.i.i.i.i ]
  %_6.i.not.not.not.i7.not.not.i.not.i.i = icmp eq ptr %_16.i8.i6.i.i.i, %_33.i20.i.i
  br i1 %_6.i.not.not.not.i7.not.not.i.not.i.i, label %bb4.i, label %bb3.i8.i.i.i

bb3.i8.i.i.i:                                     ; preds = %bb1.i5.i.i.i
  %_16.i.i9.i.i.i = getelementptr inbounds nuw i8, ptr %_16.i8.i6.i.i.i, i64 8
  %.val.i10.i.i.i = load ptr, ptr %_16.i8.i6.i.i.i, align 8, !noalias !2413, !noundef !31
  %.not.i.i.i.i11.i.i.i = icmp eq ptr %.val.i10.i.i.i, null
  br i1 %.not.i.i.i.i11.i.i.i, label %bb2.i.i.i.i16.i.i.i, label %bb5.i.i.i.i12.i.i.i

bb5.i.i.i.i12.i.i.i:                              ; preds = %bb3.i8.i.i.i
  %_11.i.i.i.i13.i.i.i = load i64, ptr %.val.i10.i.i.i, align 8, !noalias !2413, !noundef !31
  %_12.i.i.i.i14.i.i.i = icmp ne i64 %_11.i.i.i.i13.i.i.i, 0
  tail call void @llvm.assume(i1 %_12.i.i.i.i14.i.i.i)
  %_13.i.i.i.i15.i.i.i = add i64 %_11.i.i.i.i13.i.i.i, 1
  store i64 %_13.i.i.i.i15.i.i.i, ptr %.val.i10.i.i.i, align 8, !noalias !2413
  %50 = icmp eq i64 %_13.i.i.i.i15.i.i.i, 0
  br i1 %50, label %bb6.i.i.i.i26.i.i.i, label %bb2.i.i.i.i16.i.i.i, !prof !1319

bb2.i.i.i.i16.i.i.i:                              ; preds = %bb5.i.i.i.i12.i.i.i, %bb3.i8.i.i.i
  %_24.i.i.i.i19.i.i.i = load i64, ptr %.fr.i.i.i, align 8, !noalias !2417, !noundef !31
  %_25.i.i.i.i20.i.i.i = icmp ne i64 %_24.i.i.i.i19.i.i.i, 0
  tail call void @llvm.assume(i1 %_25.i.i.i.i20.i.i.i)
  %_26.i.i.i.i21.i.i.i = add i64 %_24.i.i.i.i19.i.i.i, 1
  store i64 %_26.i.i.i.i21.i.i.i, ptr %.fr.i.i.i, align 8, !noalias !2417
  %51 = icmp eq i64 %_26.i.i.i.i21.i.i.i, 0
  br i1 %51, label %bb12.i.i.i.i25.i.i.i, label %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i", !prof !1319

bb6.i.i.i.i26.i.i.i:                              ; preds = %bb5.i.i.i.i12.us.i.i.i, %bb5.i.i.i.i12.i.i.i
  tail call void @llvm.trap()
  unreachable

bb12.i.i.i.i25.i.i.i:                             ; preds = %bb2.i.i.i.i16.i.i.i
  tail call void @llvm.trap()
  unreachable

"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i": ; preds = %bb2.i.i.i.i16.i.i.i
; call matrix::in_row_space
  %_0.i.i.i.i24.i.i.i = tail call fastcc noundef zeroext i1 @_ZN6matrix12in_row_space17h77f24828cb07760aE(i64 %field.val, ptr noundef %.val.i10.i.i.i, ptr noundef nonnull %.fr.i.i.i) #65, !noalias !2417
  br i1 %_0.i.i.i.i24.i.i.i, label %bb6.i, label %bb1.i5.i.i.i

bb10.i.i:                                         ; preds = %bb2.us.i
  tail call void @llvm.trap()
  unreachable

bb16.i.i:                                         ; preds = %bb15.i.us.i, %bb15.i.us.us.i
  tail call void @llvm.trap()
  unreachable

bb7.i8:                                           ; preds = %bb6.i, %bb6.us.i, %bb6.us.us.i
  %.lcssa.i = phi ptr [ %29, %bb6.us.us.i ], [ %41, %bb6.us.i ], [ %61, %bb6.i ]
  %.not4.i.i = icmp eq ptr %.lcssa.i, null
  br i1 %.not4.i.i, label %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit, label %bb2.i2.i

bb2.i2.i:                                         ; preds = %bb7.i8, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i
  %52 = phi ptr [ %59, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], [ %.lcssa.i, %bb7.i8 ]
  %result.sroa.0.05.i.i = phi ptr [ %56, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], [ null, %bb7.i8 ]
  %53 = getelementptr inbounds nuw i8, ptr %52, i64 16
  %54 = load ptr, ptr %53, align 8, !noalias !2418, !noundef !31
  %.not1.i3.i = icmp eq ptr %54, null
  br i1 %.not1.i3.i, label %bb5.i.i, label %bb8.i.i

bb8.i.i:                                          ; preds = %bb2.i2.i
  %_13.i.i = load i64, ptr %54, align 8, !noalias !2418, !noundef !31
  %_14.i.i = icmp ne i64 %_13.i.i, 0
  tail call void @llvm.assume(i1 %_14.i.i)
  %_15.i.i = add i64 %_13.i.i, 1
  store i64 %_15.i.i, ptr %54, align 8, !noalias !2418
  %55 = icmp eq i64 %_15.i.i, 0
  br i1 %55, label %bb9.i5.i, label %bb11.i.i, !prof !1319

bb5.i.i:                                          ; preds = %bb11.i.i, %bb2.i2.i
  %_4.sroa.0.0.i.i = phi ptr [ %_10.i.i, %bb11.i.i ], [ null, %bb2.i2.i ]
  %56 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2421
  %57 = icmp eq ptr %56, null
  br i1 %57, label %bb2.i.i.i.i9, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i, !prof !1319

bb2.i.i.i.i9:                                     ; preds = %bb5.i.i
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2421
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i:   ; preds = %bb5.i.i
  store i64 1, ptr %56, align 8, !noalias !2418
  %_7.sroa.4.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %56, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i.i, align 8, !noalias !2418
  %_7.sroa.5.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %56, i64 16
  store ptr %_4.sroa.0.0.i.i, ptr %_7.sroa.5.0..sroa_idx.i.i.i, align 8, !noalias !2418
  %_7.sroa.6.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %56, i64 24
  store ptr %result.sroa.0.05.i.i, ptr %_7.sroa.6.0..sroa_idx.i.i.i, align 8, !noalias !2418
  %58 = getelementptr inbounds nuw i8, ptr %52, i64 24
  %59 = load ptr, ptr %58, align 8, !noalias !2418, !noundef !31
  %.not.i4.i = icmp eq ptr %59, null
  br i1 %.not.i4.i, label %bb2.i6.i, label %bb2.i2.i

bb9.i5.i:                                         ; preds = %bb8.i.i
  tail call void @llvm.trap()
  unreachable

bb11.i.i:                                         ; preds = %bb8.i.i
  %_10.i.i = load ptr, ptr %53, align 8, !noalias !2418, !nonnull !31, !noundef !31
  br label %bb5.i.i

bb2.i6.i:                                         ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i
  %.lcssa701 = phi ptr [ %56, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i.i ], !dbg !1250
  %_8.i.i.i = load i64, ptr %.lcssa.i, align 8, !noalias !2424, !noundef !31
  %val.i.i.i = add i64 %_8.i.i.i, -1
  store i64 %val.i.i.i, ptr %.lcssa.i, align 8, !noalias !2424
  %60 = icmp eq i64 %val.i.i.i, 0
  br i1 %60, label %bb1.i.i.i, label %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit

bb1.i.i.i:                                        ; preds = %bb2.i6.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %reversed.i) #103, !noalias !2389
  br label %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit

bb4.i:                                            ; preds = %bb1.i5.i.i.i
  %.pre.i = load ptr, ptr %_8.i, align 8, !noalias !2389
  %.not1.i = icmp eq ptr %.pre.i, null
  br i1 %.not1.i, label %bb10.i11, label %bb13.i

bb6.i:                                            ; preds = %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i", %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i", %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i, %bb5.i.i.i.i12.us.i.i.i, %bb3.i8.us.i.i.i, %bb5.i.i.i.i.us.i.i.i, %bb3.i.us.i.i.i
  %61 = phi ptr [ %65, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i ], [ %45, %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i22.i.i.i" ], [ %45, %bb5.i.i.i.i12.us.i.i.i ], [ %45, %bb5.i.i.i.i.us.i.i.i ], [ %45, %bb3.i.us.i.i.i ], [ %45, %bb3.i8.us.i.i.i ], [ %45, %"_ZN4core3ops8function5impls79_$LT$impl$u20$core..ops..function..FnMut$LT$A$GT$$u20$for$u20$$RF$mut$u20$F$GT$8call_mut17h6432cf80c4f9827fE.exit.i.i.i.i" ]
  %62 = getelementptr inbounds nuw i8, ptr %44, i64 24
  %63 = load ptr, ptr %62, align 8, !noalias !2389, !noundef !31
  %.not.i = icmp eq ptr %63, null
  br i1 %.not.i, label %bb7.i8, label %bb2.i

bb13.i:                                           ; preds = %bb4.i
  %_20.i = load i64, ptr %.pre.i, align 8, !noalias !2389, !noundef !31
  %_21.i = icmp ne i64 %_20.i, 0
  tail call void @llvm.assume(i1 %_21.i)
  %_22.i = add i64 %_20.i, 1
  store i64 %_22.i, ptr %.pre.i, align 8, !noalias !2389
  %64 = icmp eq i64 %_22.i, 0
  br i1 %64, label %bb14.i12, label %bb16.i10, !prof !1319

bb10.i11:                                         ; preds = %bb16.i10, %bb4.i, %bb1.i5.us.i.i.i, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i"
  %_10.sroa.0.0.i = phi ptr [ %_17.i, %bb16.i10 ], [ null, %bb4.i ], [ null, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4iter17h898ec9056c4f54abE.exit.thread.i.i" ], [ null, %bb1.i5.us.i.i.i ]
  %65 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2393
  %66 = icmp eq ptr %65, null
  br i1 %66, label %bb2.i.i.i, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i, !prof !1319

bb2.i.i.i:                                        ; preds = %bb10.i11, %bb10.us.i, %bb10.us.us.i
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2393
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i:     ; preds = %bb10.i11
  store i64 1, ptr %65, align 8, !noalias !2389
  %_7.sroa.4.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %65, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i, align 8, !noalias !2389
  %_7.sroa.5.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %65, i64 16
  store ptr %_10.sroa.0.0.i, ptr %_7.sroa.5.0..sroa_idx.i.i, align 8, !noalias !2389
  %_7.sroa.6.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %65, i64 24
  store ptr %45, ptr %_7.sroa.6.0..sroa_idx.i.i, align 8, !noalias !2389
  store ptr %65, ptr %reversed.i, align 8, !noalias !2389
  br label %bb6.i

bb14.i12:                                         ; preds = %bb13.i, %bb13.us.i, %bb13.us.us.i
  tail call void @llvm.trap()
  unreachable

bb16.i10:                                         ; preds = %bb13.i
  %_17.i = load ptr, ptr %_8.i, align 8, !noalias !2389, !nonnull !31, !noundef !31
  br label %bb10.i11

_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit: ; preds = %_ZN6matrix11make_tester17hfad29fce983c4295E.exit, %bb7.i8, %bb2.i6.i, %bb1.i.i.i
  %result.sroa.0.0.lcssa.i6.i = phi ptr [ %.lcssa701, %bb2.i6.i ], [ %.lcssa701, %bb1.i.i.i ], [ null, %bb7.i8 ], [ null, %_ZN6matrix11make_tester17hfad29fce983c4295E.exit ]
  call void @llvm.lifetime.end.p0(ptr nonnull %reversed.i), !noalias !2389
  call void @llvm.lifetime.start.p0(ptr nonnull %_12)
  store i64 %tester.sroa.0.0, ptr %_12, align 8
  %tester.sroa.7.0._12.sroa_idx = getelementptr inbounds nuw i8, ptr %_12, i64 8
  store ptr %tester.sroa.7.0, ptr %tester.sroa.7.0._12.sroa_idx, align 8
  %tester.sroa.9.0._12.sroa_idx = getelementptr inbounds nuw i8, ptr %_12, i64 16
  store i64 %tester.sroa.9.0, ptr %tester.sroa.9.0._12.sroa_idx, align 8
  %tester.sroa.10.0._12.sroa_idx = getelementptr inbounds nuw i8, ptr %_12, i64 24
  store i64 %tester.sroa.10.0, ptr %tester.sroa.10.0._12.sroa_idx, align 8
  %67 = icmp eq i64 %tester.sroa.0.0, -9223372036854775808
  br i1 %67, label %bb2.i32, label %bb3.i13

bb2.i32:                                          ; preds = %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit
  %68 = icmp eq ptr %tester.sroa.7.0, null
  br i1 %68, label %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit", label %bb2.i.i

bb2.i.i:                                          ; preds = %bb2.i32
  %_8.i.i.i33 = load i64, ptr %tester.sroa.7.0, align 8, !noalias !2429, !noundef !31
  %val.i.i.i34 = add i64 %_8.i.i.i33, -1
  store i64 %val.i.i.i34, ptr %tester.sroa.7.0, align 8, !noalias !2429
  %69 = icmp eq i64 %val.i.i.i34, 0
  br i1 %69, label %bb1.i.i.i35, label %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit"

bb1.i.i.i35:                                      ; preds = %bb2.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %tester.sroa.7.0._12.sroa_idx) #103
  br label %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit"

bb3.i13:                                          ; preds = %_ZN6matrix16remove_dependent17h77fb362bae39ddd1E.exit
  %70 = icmp eq i64 %tester.sroa.10.0, 0
  br i1 %70, label %"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i", label %bb3.i.i.i.i14

bb3.i.i.i.i14:                                    ; preds = %bb3.i13
  %_27.not.i.i.i.i15 = icmp ult i64 %tester.sroa.9.0, %tester.sroa.0.0
  %71 = select i1 %_27.not.i.i.i.i15, i64 0, i64 %tester.sroa.0.0
  %wrapped_start.sroa.0.0.i.i.i.i16 = sub nuw i64 %tester.sroa.9.0, %71
  %head_len.i.i.i.i17 = sub i64 %tester.sroa.0.0, %wrapped_start.sroa.0.0.i.i.i.i16
  %_13.not.i.i.i.i18 = icmp ult i64 %head_len.i.i.i.i17, %tester.sroa.10.0
  %_16.i.i.i.i19 = add i64 %wrapped_start.sroa.0.0.i.i.i.i16, %tester.sroa.10.0
  %_5.sroa.11.0.i.i.i = tail call i64 @llvm.usub.sat.i64(i64 %tester.sroa.10.0, i64 %head_len.i.i.i.i17)
  %_5.sroa.5.0.i.i.i = select i1 %_13.not.i.i.i.i18, i64 %tester.sroa.0.0, i64 %_16.i.i.i.i19
  %_12.i.i.i = getelementptr inbounds nuw ptr, ptr %tester.sroa.7.0, i64 %wrapped_start.sroa.0.0.i.i.i.i16
  %_14.i.i.i = sub i64 %_5.sroa.5.0.i.i.i, %wrapped_start.sroa.0.0.i.i.i.i16
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2436)
  %_73.i.i.i.i20 = icmp eq i64 %_5.sroa.5.0.i.i.i, %wrapped_start.sroa.0.0.i.i.i.i16
  br i1 %_73.i.i.i.i20, label %"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i", label %bb2.i5.i.i.i

bb2.i5.i.i.i:                                     ; preds = %bb3.i.i.i.i14, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i"
  %_3.sroa.0.04.i.i.i.i21 = phi i64 [ %72, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i" ], [ 0, %bb3.i.i.i.i14 ]
  %_6.i.i.i.i22 = getelementptr inbounds nuw ptr, ptr %_12.i.i.i, i64 %_3.sroa.0.04.i.i.i.i21
  %72 = add nuw i64 %_3.sroa.0.04.i.i.i.i21, 1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2439)
  %73 = load ptr, ptr %_6.i.i.i.i22, align 8, !alias.scope !2442, !noalias !2443, !noundef !31
  %74 = icmp eq ptr %73, null
  br i1 %74, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i", label %bb2.i.i.i.i.i23

bb2.i.i.i.i.i23:                                  ; preds = %bb2.i5.i.i.i
  %_8.i.i.i.i.i.i24 = load i64, ptr %73, align 8, !noalias !2448, !noundef !31
  %val.i.i.i.i.i.i25 = add i64 %_8.i.i.i.i.i.i24, -1
  store i64 %val.i.i.i.i.i.i25, ptr %73, align 8, !noalias !2448
  %75 = icmp eq i64 %val.i.i.i.i.i.i25, 0
  br i1 %75, label %bb1.i.i.i.i.i.i31, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i"

bb1.i.i.i.i.i.i31:                                ; preds = %bb2.i.i.i.i.i23
; call alloc::rc::Rc<T,A>::drop_slow
  tail call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_6.i.i.i.i22) #103, !noalias !2443
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i": ; preds = %bb1.i.i.i.i.i.i31, %bb2.i.i.i.i.i23, %bb2.i5.i.i.i
  %_7.i.i.i.i26 = icmp eq i64 %72, %_14.i.i.i
  br i1 %_7.i.i.i.i26, label %"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i", label %bb2.i5.i.i.i

"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i": ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i", %bb3.i.i.i.i14
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2451)
  br i1 %_13.not.i.i.i.i18, label %bb2.i.i.i.i.i.i, label %"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i"

bb2.i.i.i.i.i.i:                                  ; preds = %"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i", %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i"
  %_3.sroa.0.04.i.i.i.i.i.i = phi i64 [ %76, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i" ], [ 0, %"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i" ]
  %_6.i.i.i.i.i.i = getelementptr inbounds nuw ptr, ptr %tester.sroa.7.0, i64 %_3.sroa.0.04.i.i.i.i.i.i
  %76 = add nuw i64 %_3.sroa.0.04.i.i.i.i.i.i, 1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2454)
  %77 = load ptr, ptr %_6.i.i.i.i.i.i, align 8, !alias.scope !2457, !noalias !2443, !noundef !31
  %78 = icmp eq ptr %77, null
  br i1 %78, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i", label %bb2.i.i.i.i.i.i.i30

bb2.i.i.i.i.i.i.i30:                              ; preds = %bb2.i.i.i.i.i.i
  %_8.i.i.i.i.i.i.i.i = load i64, ptr %77, align 8, !noalias !2458, !noundef !31
  %val.i.i.i.i.i.i.i.i = add i64 %_8.i.i.i.i.i.i.i.i, -1
  store i64 %val.i.i.i.i.i.i.i.i, ptr %77, align 8, !noalias !2458
  %79 = icmp eq i64 %val.i.i.i.i.i.i.i.i, 0
  br i1 %79, label %bb1.i.i.i.i.i.i.i.i, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i"

bb1.i.i.i.i.i.i.i.i:                              ; preds = %bb2.i.i.i.i.i.i.i30
; call alloc::rc::Rc<T,A>::drop_slow
  tail call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_6.i.i.i.i.i.i) #103, !noalias !2443
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i": ; preds = %bb1.i.i.i.i.i.i.i.i, %bb2.i.i.i.i.i.i.i30, %bb2.i.i.i.i.i.i
  %_7.i.i.i.i.i.i = icmp eq i64 %76, %_5.sroa.11.0.i.i.i
  br i1 %_7.i.i.i.i.i.i, label %"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i", label %bb2.i.i.i.i.i.i

"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i": ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i.i.i.i.i", %"_ZN4core3ptr98drop_in_place$LT$$u5b$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$u5d$$GT$17he5d1c5421e1edcbbE.exit.i.i.i", %bb3.i13
  %80 = icmp eq i64 %tester.sroa.0.0, 0
  br i1 %80, label %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit", label %bb2.i.i.i2.i.i

bb2.i.i.i2.i.i:                                   ; preds = %"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i"
  tail call void @free(ptr noundef nonnull %tester.sroa.7.0) #65, !dbg !1104
  br label %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit"

"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit": ; preds = %bb2.i32, %bb2.i.i, %bb1.i.i.i35, %"_ZN94_$LT$alloc..collections..vec_deque..VecDeque$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3d072e656ef58b12E.exit.i.i", %bb2.i.i.i2.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_12)
  %.not = icmp eq ptr %result.sroa.0.0.lcssa.i6.i, null
  br i1 %.not, label %bb2.i36, label %bb7.preheader

bb7.preheader:                                    ; preds = %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit"
  %81 = getelementptr inbounds nuw i8, ptr %cursor.i, i64 8
  %82 = getelementptr inbounds nuw i8, ptr %cursor.i, i64 16
  %83 = getelementptr inbounds nuw i8, ptr %first.i, i64 8
  %_21.sroa.4.0._20.sroa_idx.i = getelementptr inbounds nuw i8, ptr %_20.i115, i64 8
  %_21.sroa.5.0._20.sroa_idx.i = getelementptr inbounds nuw i8, ptr %_20.i115, i64 16
  %_27 = add i64 %count, 1
  %84 = getelementptr inbounds nuw i8, ptr %_11.i, i64 8
  %85 = getelementptr inbounds nuw i8, ptr %_11.i, i64 16
  br label %bb8

bb2.i36:                                          ; preds = %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit", %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41
  %86 = phi ptr [ %93, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41 ], [ %0, %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit" ]
  %result.sroa.0.05.i = phi ptr [ %90, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41 ], [ null, %"_ZN4core3ptr35drop_in_place$LT$matrix..Tester$GT$17h9d9a4d6e041a17a8E.exit" ]
  %87 = getelementptr inbounds nuw i8, ptr %86, i64 16
  %88 = load ptr, ptr %87, align 8, !noalias !2461, !noundef !31
  %.not1.i37 = icmp eq ptr %88, null
  br i1 %.not1.i37, label %bb5.i, label %bb8.i

bb8.i:                                            ; preds = %bb2.i36
  %_13.i38 = load i64, ptr %88, align 8, !noalias !2461, !noundef !31
  %_14.i39 = icmp ne i64 %_13.i38, 0
  tail call void @llvm.assume(i1 %_14.i39)
  %_15.i = add i64 %_13.i38, 1
  store i64 %_15.i, ptr %88, align 8, !noalias !2461
  %89 = icmp eq i64 %_15.i, 0
  br i1 %89, label %bb9.i, label %bb11.i40, !prof !1319

bb5.i:                                            ; preds = %bb11.i40, %bb2.i36
  %_4.sroa.0.0.i = phi ptr [ %_10.i, %bb11.i40 ], [ null, %bb2.i36 ]
  %90 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2464
  %91 = icmp eq ptr %90, null
  br i1 %91, label %bb2.i.i.i47, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41, !prof !1319

bb2.i.i.i47:                                      ; preds = %bb5.i
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2464
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41:   ; preds = %bb5.i
  store i64 1, ptr %90, align 8, !noalias !2461
  %_7.sroa.4.0..sroa_idx.i.i42 = getelementptr inbounds nuw i8, ptr %90, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i42, align 8, !noalias !2461
  %_7.sroa.5.0..sroa_idx.i.i43 = getelementptr inbounds nuw i8, ptr %90, i64 16
  store ptr %_4.sroa.0.0.i, ptr %_7.sroa.5.0..sroa_idx.i.i43, align 8, !noalias !2461
  %_7.sroa.6.0..sroa_idx.i.i44 = getelementptr inbounds nuw i8, ptr %90, i64 24
  store ptr %result.sroa.0.05.i, ptr %_7.sroa.6.0..sroa_idx.i.i44, align 8, !noalias !2461
  %92 = getelementptr inbounds nuw i8, ptr %86, i64 24
  %93 = load ptr, ptr %92, align 8, !noalias !2461, !noundef !31
  %.not.i45 = icmp eq ptr %93, null
  br i1 %.not.i45, label %_ZN6matrix14reverse_matrix17h1e08ca037225e633E.exit, label %bb2.i36

bb9.i:                                            ; preds = %bb8.i
  tail call void @llvm.trap()
  unreachable

bb11.i40:                                         ; preds = %bb8.i
  %_10.i = load ptr, ptr %87, align 8, !noalias !2461, !nonnull !31, !noundef !31
  br label %bb5.i

_ZN6matrix14reverse_matrix17h1e08ca037225e633E.exit: ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41
  %.lcssa665 = phi ptr [ %90, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i41 ], !dbg !1250
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2467)
  call void @llvm.lifetime.start.p0(ptr nonnull %rows.i)
  store ptr %.lcssa665, ptr %rows.i, align 8, !noalias !2467
  br label %bb16.i48

bb16.i48:                                         ; preds = %_ZN6matrix14reverse_matrix17h1e08ca037225e633E.exit, %bb16.i48
  %_4.sroa.0.026.i = phi i64 [ %95, %bb16.i48 ], [ 0, %_ZN6matrix14reverse_matrix17h1e08ca037225e633E.exit ]
  %94 = phi ptr [ %.pr.i, %bb16.i48 ], [ %.lcssa665, %_ZN6matrix14reverse_matrix17h1e08ca037225e633E.exit ]
  %95 = add i64 %_4.sroa.0.026.i, 1
  %96 = getelementptr inbounds nuw i8, ptr %94, i64 24
  %.pr.i = load ptr, ptr %96, align 8, !noalias !2467
  %.not.i49 = icmp eq ptr %.pr.i, null
  br i1 %.not.i49, label %bb14.thread.i, label %bb16.i48

bb14.thread.i:                                    ; preds = %bb16.i48
  %.lcssa = phi i64 [ %95, %bb16.i48 ]
  %97 = getelementptr inbounds nuw i8, ptr %best, i64 32
  %_730.i = load i64, ptr %97, align 8, !alias.scope !2467, !noundef !31
  %_631.i = icmp slt i64 %.lcssa, %_730.i
  br i1 %_631.i, label %bb1.i.i.i62, label %bb2.i50

bb2.i50:                                          ; preds = %bb14.thread.i
  %_8.i51 = icmp sgt i64 %.lcssa, %_730.i
  br i1 %_8.i51, label %bb3.i58, label %bb4.i52

bb1.i.i.i62:                                      ; preds = %bb14.thread.i
  store i64 0, ptr %.lcssa665, align 8, !noalias !2470
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %rows.i) #103, !noalias !2467
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

bb4.i52:                                          ; preds = %bb2.i50
  %98 = getelementptr inbounds nuw i8, ptr %best, i64 40
  %99 = load i64, ptr %98, align 8, !alias.scope !2467, !noundef !31
  %100 = add i64 %99, 1
  store i64 %100, ptr %98, align 8, !alias.scope !2467
  %_14.i53 = icmp ult i64 %100, 3000
  br i1 %_14.i53, label %bb7.i57, label %bb8.i54

bb3.i58:                                          ; preds = %bb2.i50
  store i64 %.lcssa, ptr %97, align 8, !alias.scope !2467
  %101 = getelementptr inbounds nuw i8, ptr %best, i64 40
  store i64 1, ptr %101, align 8, !alias.scope !2467
  %102 = tail call noundef dereferenceable_or_null(16) ptr @malloc(i64 noundef 16) #65, !dbg !1250, !noalias !2475
  %103 = icmp eq ptr %102, null
  br i1 %103, label %bb3.i.i.i, label %"_ZN118_$LT$alloc..collections..vec_deque..VecDeque$LT$T$GT$$u20$as$u20$core..convert..From$LT$$u5b$T$u3b$$u20$N$u5d$$GT$$GT$4from17hb4c281df93a5f980E.exit.i"

bb3.i.i.i:                                        ; preds = %bb3.i58
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 8, i64 16) #105, !noalias !2481
  unreachable

"_ZN118_$LT$alloc..collections..vec_deque..VecDeque$LT$T$GT$$u20$as$u20$core..convert..From$LT$$u5b$T$u3b$$u20$N$u5d$$GT$$GT$4from17hb4c281df93a5f980E.exit.i": ; preds = %bb3.i58
  store i64 0, ptr %102, align 8, !noalias !2482
  %_11.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %102, i64 8
  store ptr %.lcssa665, ptr %_11.sroa.4.0..sroa_idx.i, align 8, !noalias !2482
; call core::ptr::drop_in_place<alloc::collections::vec_deque::VecDeque<matrix::Answer>>
  tail call fastcc void @"_ZN4core3ptr82drop_in_place$LT$alloc..collections..vec_deque..VecDeque$LT$matrix..Answer$GT$$GT$17h02813d3d402b9506E"(ptr noalias noundef nonnull align 8 dereferenceable(48) %best) #65
  store i64 1, ptr %best, align 8, !alias.scope !2467
  %_10.sroa.4.0.self.sroa_idx.i = getelementptr inbounds nuw i8, ptr %best, i64 8
  store ptr %102, ptr %_10.sroa.4.0.self.sroa_idx.i, align 8, !alias.scope !2467
  %_10.sroa.5.0.self.sroa_idx.i = getelementptr inbounds nuw i8, ptr %best, i64 16
  store i64 0, ptr %_10.sroa.5.0.self.sroa_idx.i, align 8, !alias.scope !2467
  %_10.sroa.6.0.self.sroa_idx.i = getelementptr inbounds nuw i8, ptr %best, i64 24
  store i64 1, ptr %_10.sroa.6.0.self.sroa_idx.i, align 8, !alias.scope !2467
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

bb8.i54:                                          ; preds = %bb4.i52
  %104 = icmp eq i64 %100, 3000
  br i1 %104, label %bb9.i56, label %bb2.i19.i.thread

bb2.i19.i.thread:                                 ; preds = %bb8.i54
  store i64 0, ptr %.lcssa665, align 8, !noalias !2483
  br label %bb1.i.i23.i

bb7.i57:                                          ; preds = %bb4.i52
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2488)
  %105 = getelementptr inbounds nuw i8, ptr %best, i64 24
  %_9.i.i = load i64, ptr %105, align 8, !alias.scope !2491, !noundef !31
  %self1.i.i = load i64, ptr %best, align 8, !range !1117, !alias.scope !2491, !noundef !31
  %_3.i.i = icmp eq i64 %_9.i.i, %self1.i.i
  br i1 %_3.i.i, label %bb1.i.i, label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17hd3ce057660ae2de6E.exit.i"

bb1.i.i:                                          ; preds = %bb7.i57
; call alloc::collections::vec_deque::VecDeque<T,A>::grow
  tail call fastcc void @"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4grow17h7b97bab9c8ea9632E"(ptr noalias noundef nonnull align 8 dereferenceable(48) %best) #103
  %self3.pre.i.i = load i64, ptr %best, align 8, !range !1117, !alias.scope !2491
  %.pre.i.i = load i64, ptr %105, align 8, !alias.scope !2491
  br label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17hd3ce057660ae2de6E.exit.i"

"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17hd3ce057660ae2de6E.exit.i": ; preds = %bb1.i.i, %bb7.i57
  %106 = phi i64 [ %.pre.i.i, %bb1.i.i ], [ %_9.i.i, %bb7.i57 ]
  %self3.i.i = phi i64 [ %self3.pre.i.i, %bb1.i.i ], [ %self1.i.i, %bb7.i57 ]
  %107 = getelementptr inbounds nuw i8, ptr %best, i64 16
  %idx.i.i = load i64, ptr %107, align 8, !alias.scope !2491, !noundef !31
  %self2.i.i = add i64 %idx.i.i, -1
  %logical_index.i.i = add i64 %self2.i.i, %self3.i.i
  %_24.not.i.i = icmp ult i64 %logical_index.i.i, %self3.i.i
  %logical_index.self2.i.i = select i1 %_24.not.i.i, i64 %logical_index.i.i, i64 %self2.i.i
  store i64 %logical_index.self2.i.i, ptr %107, align 8, !alias.scope !2491
  %108 = add i64 %106, 1
  store i64 %108, ptr %105, align 8, !alias.scope !2491
  %109 = getelementptr inbounds nuw i8, ptr %best, i64 8
  %_27.i.i = load ptr, ptr %109, align 8, !alias.scope !2491, !nonnull !31, !noundef !31
  %_25.i.i = getelementptr inbounds nuw %Answer, ptr %_27.i.i, i64 %logical_index.self2.i.i
  store i64 0, ptr %_25.i.i, align 8, !noalias !2491
  %110 = getelementptr inbounds nuw i8, ptr %_25.i.i, i64 8
  store ptr %.lcssa665, ptr %110, align 8, !noalias !2491
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

bb9.i56:                                          ; preds = %bb8.i54
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2492)
  %111 = getelementptr inbounds nuw i8, ptr %best, i64 24
  %_9.i3.i = load i64, ptr %111, align 8, !alias.scope !2495, !noundef !31
  %self1.i4.i = load i64, ptr %best, align 8, !range !1117, !alias.scope !2495, !noundef !31
  %_3.i5.i = icmp eq i64 %_9.i3.i, %self1.i4.i
  br i1 %_3.i5.i, label %bb1.i15.i, label %bb2.i19.i

bb1.i15.i:                                        ; preds = %bb9.i56
; call alloc::collections::vec_deque::VecDeque<T,A>::grow
  tail call fastcc void @"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4grow17h7b97bab9c8ea9632E"(ptr noalias noundef nonnull align 8 dereferenceable(48) %best) #103
  %self3.pre.i16.i = load i64, ptr %best, align 8, !range !1117, !alias.scope !2495
  %.pre.i17.i = load i64, ptr %111, align 8, !alias.scope !2495
  br label %bb2.i19.i

bb2.i19.i:                                        ; preds = %bb9.i56, %bb1.i15.i
  %112 = phi i64 [ %.pre.i17.i, %bb1.i15.i ], [ %_9.i3.i, %bb9.i56 ]
  %self3.i7.i = phi i64 [ %self3.pre.i16.i, %bb1.i15.i ], [ %self1.i4.i, %bb9.i56 ]
  %113 = getelementptr inbounds nuw i8, ptr %best, i64 16
  %idx.i8.i = load i64, ptr %113, align 8, !alias.scope !2495, !noundef !31
  %self2.i9.i = add i64 %idx.i8.i, -1
  %logical_index.i10.i = add i64 %self2.i9.i, %self3.i7.i
  %_24.not.i11.i = icmp ult i64 %logical_index.i10.i, %self3.i7.i
  %logical_index.self2.i12.i = select i1 %_24.not.i11.i, i64 %logical_index.i10.i, i64 %self2.i9.i
  store i64 %logical_index.self2.i12.i, ptr %113, align 8, !alias.scope !2495
  %114 = add i64 %112, 1
  store i64 %114, ptr %111, align 8, !alias.scope !2495
  %115 = getelementptr inbounds nuw i8, ptr %best, i64 8
  %_27.i13.i = load ptr, ptr %115, align 8, !alias.scope !2495, !nonnull !31, !noundef !31
  %_25.i14.i = getelementptr inbounds nuw %Answer, ptr %_27.i13.i, i64 %logical_index.self2.i12.i
  store i64 1, ptr %_25.i14.i, align 8, !noalias !2495
  %_8.i.i20.i.pre = load i64, ptr %.lcssa665, align 8, !noalias !2483
  %116 = add i64 %_8.i.i20.i.pre, -1
  store i64 %116, ptr %.lcssa665, align 8, !noalias !2483
  %117 = icmp eq i64 %116, 0
  br i1 %117, label %bb1.i.i23.i, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

bb1.i.i23.i:                                      ; preds = %bb2.i19.i.thread, %bb2.i19.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %rows.i) #103, !noalias !2467
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit": ; preds = %bb1.i.i23.i, %bb2.i19.i, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17hd3ce057660ae2de6E.exit.i", %"_ZN118_$LT$alloc..collections..vec_deque..VecDeque$LT$T$GT$$u20$as$u20$core..convert..From$LT$$u5b$T$u3b$$u20$N$u5d$$GT$$GT$4from17hb4c281df93a5f980E.exit.i", %bb1.i.i.i62
  call void @llvm.lifetime.end.p0(ptr nonnull %rows.i)
  br i1 %.not21.i7, label %bb2.i74, label %bb2.i68

bb2.i68:                                          ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"
  %_8.i.i69 = load i64, ptr %1, align 8, !noalias !2496, !noundef !31
  %val.i.i70 = add i64 %_8.i.i69, -1
  store i64 %val.i.i70, ptr %1, align 8, !noalias !2496
  %118 = icmp eq i64 %val.i.i70, 0
  br i1 %118, label %bb1.i.i72, label %bb2.i74

bb1.i.i72:                                        ; preds = %bb2.i68
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %future) #103
  br label %bb2.i74

bb2.i74:                                          ; preds = %bb1.i.i72, %bb2.i68, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"
  %_8.i.i75 = load i64, ptr %0, align 8, !noalias !2501, !noundef !31
  %val.i.i76 = add i64 %_8.i.i75, -1
  store i64 %val.i.i76, ptr %0, align 8, !noalias !2501
  %119 = icmp eq i64 %val.i.i76, 0
  br i1 %119, label %bb24.sink.split, label %bb24

bb8:                                              ; preds = %bb7.preheader, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"
  %result.sroa.0.0.lcssa.i6.i153199 = phi ptr [ %result.sroa.0.0.lcssa.i6.i, %bb7.preheader ], [ %_30.sroa.0.0, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit" ]
  call void @llvm.lifetime.start.p0(ptr nonnull %next)
  store ptr %result.sroa.0.0.lcssa.i6.i153199, ptr %next, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %candidate)
  %120 = getelementptr inbounds nuw i8, ptr %result.sroa.0.0.lcssa.i6.i153199, i64 16
  %121 = load ptr, ptr %120, align 8, !noundef !31
  %.not3 = icmp eq ptr %121, null
  br i1 %.not3, label %bb36, label %bb30

bb19:                                             ; preds = %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"
  br i1 %.not21.i7, label %bb2.i86, label %bb2.i80

bb2.i80:                                          ; preds = %bb19
  %_8.i.i81 = load i64, ptr %1, align 8, !noalias !2506, !noundef !31
  %val.i.i82 = add i64 %_8.i.i81, -1
  store i64 %val.i.i82, ptr %1, align 8, !noalias !2506
  %122 = icmp eq i64 %val.i.i82, 0
  br i1 %122, label %bb1.i.i84, label %bb2.i86

bb1.i.i84:                                        ; preds = %bb2.i80
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %future) #103
  br label %bb2.i86

bb2.i86:                                          ; preds = %bb1.i.i84, %bb2.i80, %bb19
  %_8.i.i87 = load i64, ptr %0, align 8, !noalias !2511, !noundef !31
  %val.i.i88 = add i64 %_8.i.i87, -1
  store i64 %val.i.i88, ptr %0, align 8, !noalias !2511
  %123 = icmp eq i64 %val.i.i88, 0
  br i1 %123, label %bb24.sink.split, label %bb24

bb30:                                             ; preds = %bb8
  %_41 = load i64, ptr %121, align 8, !noundef !31
  %_42 = icmp ne i64 %_41, 0
  call void @llvm.assume(i1 %_42)
  %_43 = add i64 %_41, 1
  store i64 %_43, ptr %121, align 8
  %124 = icmp eq i64 %_43, 0
  br i1 %124, label %bb31, label %bb33, !prof !1319

bb31:                                             ; preds = %bb30
  call void @llvm.trap()
  unreachable

bb33:                                             ; preds = %bb30
  %_38 = load ptr, ptr %120, align 8, !nonnull !31, !noundef !31
  br label %bb36

bb36:                                             ; preds = %bb33, %bb8
  %_20.sroa.0.0 = phi ptr [ %_38, %bb33 ], [ null, %bb8 ]
  %_55 = load i64, ptr %0, align 8, !noundef !31
  %_56 = icmp ne i64 %_55, 0
  call void @llvm.assume(i1 %_56)
  %_57 = add i64 %_55, 1
  store i64 %_57, ptr %0, align 8
  %125 = icmp eq i64 %_57, 0
  br i1 %125, label %bb37, label %bb34, !prof !1319

bb34:                                             ; preds = %bb36
  %126 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2516
  %127 = icmp eq ptr %126, null
  br i1 %127, label %bb2.i.i92, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit, !prof !1319

bb2.i.i92:                                        ; preds = %bb34
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2516
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit:       ; preds = %bb34
  store i64 1, ptr %126, align 8
  %_7.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %126, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i, align 8
  %_7.sroa.5.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %126, i64 16
  store ptr %_20.sroa.0.0, ptr %_7.sroa.5.0..sroa_idx.i, align 8
  %_7.sroa.6.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %126, i64 24
  store ptr %0, ptr %_7.sroa.6.0..sroa_idx.i, align 8
  store ptr %126, ptr %candidate, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %_24)
  br label %bb2.i94

bb2.i94:                                          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105
  %128 = phi ptr [ %135, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105 ], [ %126, %_ZN6matrix6matrix17he37191504af5b7c1E.exit ]
  %result.sroa.0.05.i95 = phi ptr [ %132, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105 ], [ null, %_ZN6matrix6matrix17he37191504af5b7c1E.exit ]
  %129 = getelementptr inbounds nuw i8, ptr %128, i64 16
  %130 = load ptr, ptr %129, align 8, !noalias !2519, !noundef !31
  %.not1.i96 = icmp eq ptr %130, null
  br i1 %.not1.i96, label %bb5.i103, label %bb8.i97

bb8.i97:                                          ; preds = %bb2.i94
  %_13.i98 = load i64, ptr %130, align 8, !noalias !2519, !noundef !31
  %_14.i99 = icmp ne i64 %_13.i98, 0
  call void @llvm.assume(i1 %_14.i99)
  %_15.i100 = add i64 %_13.i98, 1
  store i64 %_15.i100, ptr %130, align 8, !noalias !2519
  %131 = icmp eq i64 %_15.i100, 0
  br i1 %131, label %bb9.i113, label %bb11.i101, !prof !1319

bb5.i103:                                         ; preds = %bb11.i101, %bb2.i94
  %_4.sroa.0.0.i104 = phi ptr [ %_10.i102, %bb11.i101 ], [ null, %bb2.i94 ]
  %132 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2522
  %133 = icmp eq ptr %132, null
  br i1 %133, label %bb2.i.i.i112, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105, !prof !1319

bb2.i.i.i112:                                     ; preds = %bb5.i103
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2522
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105:  ; preds = %bb5.i103
  store i64 1, ptr %132, align 8, !noalias !2519
  %_7.sroa.4.0..sroa_idx.i.i106 = getelementptr inbounds nuw i8, ptr %132, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i106, align 8, !noalias !2519
  %_7.sroa.5.0..sroa_idx.i.i107 = getelementptr inbounds nuw i8, ptr %132, i64 16
  store ptr %_4.sroa.0.0.i104, ptr %_7.sroa.5.0..sroa_idx.i.i107, align 8, !noalias !2519
  %_7.sroa.6.0..sroa_idx.i.i108 = getelementptr inbounds nuw i8, ptr %132, i64 24
  store ptr %result.sroa.0.05.i95, ptr %_7.sroa.6.0..sroa_idx.i.i108, align 8, !noalias !2519
  %134 = getelementptr inbounds nuw i8, ptr %128, i64 24
  %135 = load ptr, ptr %134, align 8, !noalias !2519, !noundef !31
  %.not.i109 = icmp eq ptr %135, null
  br i1 %.not.i109, label %bb3.preheader.i, label %bb2.i94

bb9.i113:                                         ; preds = %bb8.i97
  call void @llvm.trap()
  unreachable

bb11.i101:                                        ; preds = %bb8.i97
  %_10.i102 = load ptr, ptr %129, align 8, !noalias !2519, !nonnull !31, !noundef !31
  br label %bb5.i103

bb3.preheader.i:                                  ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105
  %.lcssa706 = phi ptr [ %132, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i105 ]
  %_7.sroa.6.0..sroa_idx.i.i108.le = getelementptr inbounds nuw i8, ptr %.lcssa706, i64 24
  store ptr %.lcssa706, ptr %_24, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %cursor.i)
  store i64 2, ptr %.lcssa706, align 8
  store ptr %.lcssa706, ptr %81, align 8, !alias.scope !2525
  store ptr null, ptr %82, align 8, !alias.scope !2525
  store i64 1, ptr %cursor.i, align 8, !alias.scope !2525
  call void @llvm.lifetime.start.p0(ptr nonnull %first.i)
  store ptr %.lcssa706, ptr %first.i, align 8
  store ptr null, ptr %83, align 8
  br label %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i

bb3.i118thread-pre-split:                         ; preds = %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i"
  %.pr = load ptr, ptr %81, align 8
  %.pr278 = load ptr, ptr %82, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %first.i)
  store ptr %.pr, ptr %first.i, align 8
  store ptr %.pr278, ptr %83, align 8
  %.not.i9.i = icmp eq ptr %.pr, null
  br i1 %.not.i9.i, label %bb2.i.i127, label %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i, !prof !2528

bb2.i.i127:                                       ; preds = %bb3.i118thread-pre-split
; call core::option::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_8822e31da2eb3253489717f3d2aef9a3) #104
  unreachable

_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i: ; preds = %bb3.preheader.i, %bb3.i118thread-pre-split
  %136 = phi ptr [ %.lcssa706, %bb3.preheader.i ], [ %.pr, %bb3.i118thread-pre-split ]
  %137 = phi ptr [ null, %bb3.preheader.i ], [ %.pr278, %bb3.i118thread-pre-split ]
  %_0.i.i = getelementptr inbounds nuw i8, ptr %136, i64 16
  %138 = load ptr, ptr %_0.i.i, align 8, !noundef !31
  %.not221.i = icmp eq ptr %138, null
  br i1 %.not221.i, label %bb8.i491, label %bb6.i119

bb6.i119:                                         ; preds = %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i, %bb6.i119
  %139 = phi ptr [ %142, %bb6.i119 ], [ %138, %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i ]
  %columns.sroa.0.022.i = phi i64 [ %140, %bb6.i119 ], [ 0, %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i ]
  %140 = add i64 %columns.sroa.0.022.i, 1
  %141 = getelementptr inbounds nuw i8, ptr %139, i64 24
  %142 = load ptr, ptr %141, align 8, !noundef !31
  %.not2.i120 = icmp eq ptr %142, null
  br i1 %.not2.i120, label %bb8.i491, label %bb6.i119

bb8.i491:                                         ; preds = %bb6.i119, %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i
  %columns.sroa.0.0.lcssa.i = phi i64 [ 0, %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit.i ], [ %140, %bb6.i119 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_11.i)
  call void @llvm.experimental.noalias.scope.decl(metadata !2529)
  %143 = getelementptr inbounds nuw i8, ptr %136, i64 24
  %144 = load ptr, ptr %143, align 8, !noalias !2529, !noundef !31
  %.not1.i492 = icmp eq ptr %144, null
  br i1 %.not1.i492, label %bb9.i498.thread, label %bb11.i493

bb11.i493:                                        ; preds = %bb8.i491
  %_20.i494 = load i64, ptr %144, align 8, !noalias !2529, !noundef !31
  %_21.i495 = icmp ne i64 %_20.i494, 0
  call void @llvm.assume(i1 %_21.i495)
  %_22.i496 = add i64 %_20.i494, 1
  store i64 %_22.i496, ptr %144, align 8, !noalias !2529
  %145 = icmp eq i64 %_22.i496, 0
  br i1 %145, label %bb12.i510, label %bb9.i498, !prof !1319

bb9.i498:                                         ; preds = %bb11.i493
  %_17.i497 = load ptr, ptr %143, align 8, !noalias !2529, !nonnull !31, !noundef !31
  %.not27.i = icmp eq ptr %137, null
  br i1 %.not27.i, label %bb4.i.i, label %bb2.i499.preheader

bb9.i498.thread:                                  ; preds = %bb8.i491
  %.not27.i516 = icmp eq ptr %137, null
  br i1 %.not27.i516, label %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit, label %bb2.i499.preheader

bb2.i499.preheader:                               ; preds = %bb9.i498, %bb9.i498.thread
  %future.sroa.0.18.i.ph = phi ptr [ null, %bb9.i498.thread ], [ %_17.i497, %bb9.i498 ]
  br label %bb2.i499

bb12.i510:                                        ; preds = %bb11.i493
  call void @llvm.trap()
  unreachable

bb2.i499:                                         ; preds = %bb2.i499.preheader, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501
  %146 = phi ptr [ %152, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501 ], [ %137, %bb2.i499.preheader ]
  %future.sroa.0.18.i = phi ptr [ %150, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501 ], [ %future.sroa.0.18.i.ph, %bb2.i499.preheader ]
  %147 = getelementptr inbounds nuw i8, ptr %146, i64 16
  %148 = load ptr, ptr %147, align 8, !noalias !2529, !noundef !31
  %.not3.i = icmp eq ptr %148, null
  br i1 %.not3.i, label %bb15.i500, label %bb17.i

bb4.i.i:                                          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501, %bb9.i498
  %future.sroa.0.1.lcssa17.i = phi ptr [ %_17.i497, %bb9.i498 ], [ %150, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501 ]
  store ptr %future.sroa.0.1.lcssa17.i, ptr %84, align 8, !alias.scope !2532
  store ptr null, ptr %85, align 8, !alias.scope !2532
  br label %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit

bb17.i:                                           ; preds = %bb2.i499
  %_36.i = load i64, ptr %148, align 8, !noalias !2529, !noundef !31
  %_37.i = icmp ne i64 %_36.i, 0
  call void @llvm.assume(i1 %_37.i)
  %_38.i = add i64 %_36.i, 1
  store i64 %_38.i, ptr %148, align 8, !noalias !2529
  %149 = icmp eq i64 %_38.i, 0
  br i1 %149, label %bb18.i507, label %bb20.i, !prof !1319

bb15.i500:                                        ; preds = %bb20.i, %bb2.i499
  %_7.sroa.0.0.i = phi ptr [ %_33.i, %bb20.i ], [ null, %bb2.i499 ]
  %150 = call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2535
  %151 = icmp eq ptr %150, null
  br i1 %151, label %bb2.i.i.i506, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501, !prof !1319

bb2.i.i.i506:                                     ; preds = %bb15.i500
; call alloc::alloc::handle_alloc_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2538
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i501:  ; preds = %bb15.i500
  store i64 1, ptr %150, align 8, !noalias !2529
  %_7.sroa.4.0..sroa_idx.i.i502 = getelementptr inbounds nuw i8, ptr %150, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i502, align 8, !noalias !2529
  %_7.sroa.5.0..sroa_idx.i.i503 = getelementptr inbounds nuw i8, ptr %150, i64 16
  store ptr %_7.sroa.0.0.i, ptr %_7.sroa.5.0..sroa_idx.i.i503, align 8, !noalias !2529
  %_7.sroa.6.0..sroa_idx.i.i504 = getelementptr inbounds nuw i8, ptr %150, i64 24
  store ptr %future.sroa.0.18.i, ptr %_7.sroa.6.0..sroa_idx.i.i504, align 8, !noalias !2529
  %past.sroa.0.0.i = getelementptr inbounds nuw i8, ptr %146, i64 24
  %152 = load ptr, ptr %past.sroa.0.0.i, align 8, !noalias !2529, !noundef !31
  %.not2.i505 = icmp eq ptr %152, null
  br i1 %.not2.i505, label %bb4.i.i, label %bb2.i499

bb18.i507:                                        ; preds = %bb17.i
  call void @llvm.trap()
  unreachable

bb20.i:                                           ; preds = %bb17.i
  %_33.i = load ptr, ptr %147, align 8, !noalias !2529, !nonnull !31, !noundef !31
  br label %bb15.i500

_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit: ; preds = %bb9.i498.thread, %bb4.i.i
  %storemerge.i.i = phi i64 [ 1, %bb4.i.i ], [ 0, %bb9.i498.thread ]
  store i64 %storemerge.i.i, ptr %_11.i, align 8, !alias.scope !2532
  call void @llvm.lifetime.start.p0(ptr nonnull %_20.i115)
  %_33.0.i.i.i.i = shl i64 %columns.sroa.0.0.lcssa.i, 3
  %_33.1.i.i.i.i = icmp ugt i64 %columns.sroa.0.0.lcssa.i, 2305843009213693951
  %_38.i.i.i.i = icmp ugt i64 %_33.0.i.i.i.i, 9223372036854775800
  %or.cond.not.i.i.i.i = or i1 %_33.1.i.i.i.i, %_38.i.i.i.i
  br i1 %or.cond.not.i.i.i.i, label %_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit13.i.split, label %bb18.i.i.i.i, !prof !1219

_ZN6matrix11Permutation3now17h3200e75ffb24d2feE.exit13.i.split: ; preds = %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit
; call alloc::raw_vec::capacity_overflow
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #108, !dbg !1943, !noalias !2539
  unreachable, !dbg !1943

bb18.i.i.i.i:                                     ; preds = %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit
  %153 = icmp eq i64 %_33.0.i.i.i.i, 0
  br i1 %153, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17hd2f38306e734cb0aE.exit.i.i.i.i", label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit:  ; preds = %bb18.i.i.i.i
  %154 = call noundef ptr @malloc(i64 noundef range(i64 0, 9223372036854775801) %_33.0.i.i.i.i) #65, !dbg !1250, !noalias !2542
  %155 = icmp eq ptr %154, null
  br i1 %155, label %_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.i.i.i.split, label %bb10.i.i.i.i

_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.i.i.i.split: ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit
  %_33.0.i.i.i.i.lcssa687 = phi i64 [ %_33.0.i.i.i.i, %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit ]
; call alloc::raw_vec::handle_error
  call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 8, i64 %_33.0.i.i.i.i.lcssa687) #105, !noalias !2539
  unreachable

bb10.i.i.i.i:                                     ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit
  %156 = ptrtoint ptr %154 to i64
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17hd2f38306e734cb0aE.exit.i.i.i.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17hd2f38306e734cb0aE.exit.i.i.i.i": ; preds = %bb10.i.i.i.i, %bb18.i.i.i.i
  %_4.sroa.4.0.i.i.i = phi i64 [ %columns.sroa.0.0.lcssa.i, %bb10.i.i.i.i ], [ 0, %bb18.i.i.i.i ]
  %_4.sroa.10.0.i.i.i = phi i64 [ %156, %bb10.i.i.i.i ], [ 8, %bb18.i.i.i.i ]
  %157 = inttoptr i64 %_4.sroa.10.0.i.i.i to ptr
  %_7.i.i.i121 = icmp samesign ule i64 %columns.sroa.0.0.lcssa.i, %_4.sroa.4.0.i.i.i
  call void @llvm.assume(i1 %_7.i.i.i121)
  %_0.i.i.i7.not.i.i.i.i.i.i = icmp eq i64 %columns.sroa.0.0.lcssa.i, 0
  br i1 %_0.i.i.i7.not.i.i.i.i.i.i, label %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i", label %bb3.i.i.i.i.i.i.preheader

bb3.i.i.i.i.i.i.preheader:                        ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17hd2f38306e734cb0aE.exit.i.i.i.i"
  %min.iters.check = icmp ult i64 %columns.sroa.0.0.lcssa.i, 4
  br i1 %min.iters.check, label %bb3.i.i.i.i.i.i.preheader653, label %vector.ph

vector.ph:                                        ; preds = %bb3.i.i.i.i.i.i.preheader
  %n.vec = and i64 %columns.sroa.0.0.lcssa.i, 2305843009213693948
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %vec.ind = phi <2 x i64> [ <i64 0, i64 1>, %vector.ph ], [ %vec.ind.next, %vector.body ]
  %step.add = add <2 x i64> %vec.ind, splat (i64 2)
  %158 = getelementptr inbounds nuw i64, ptr %157, i64 %index
  %159 = getelementptr inbounds nuw i8, ptr %158, i64 16
  store <2 x i64> %vec.ind, ptr %158, align 8, !noalias !2545
  store <2 x i64> %step.add, ptr %159, align 8, !noalias !2545
  %index.next = add nuw i64 %index, 4
  %vec.ind.next = add <2 x i64> %vec.ind, splat (i64 4)
  %160 = icmp eq i64 %index.next, %n.vec
  br i1 %160, label %middle.block, label %vector.body, !llvm.loop !2558

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %columns.sroa.0.0.lcssa.i, %n.vec
  br i1 %cmp.n, label %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i", label %bb3.i.i.i.i.i.i.preheader653

bb3.i.i.i.i.i.i.preheader653:                     ; preds = %bb3.i.i.i.i.i.i.preheader, %middle.block
  %.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %bb3.i.i.i.i.i.i.preheader ]
  br label %bb3.i.i.i.i.i.i

bb3.i.i.i.i.i.i:                                  ; preds = %bb3.i.i.i.i.i.i.preheader653, %bb3.i.i.i.i.i.i
  %161 = phi i64 [ %162, %bb3.i.i.i.i.i.i ], [ %.ph, %bb3.i.i.i.i.i.i.preheader653 ]
  %162 = add nuw i64 %161, 1
  %_3.i.i.i.i.i.i.i.i = getelementptr inbounds nuw i64, ptr %157, i64 %161
  store i64 %161, ptr %_3.i.i.i.i.i.i.i.i, align 8, !noalias !2545
  %exitcond.not.i.i.i.i.i.i = icmp eq i64 %162, %columns.sroa.0.0.lcssa.i
  br i1 %exitcond.not.i.i.i.i.i.i, label %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i", label %bb3.i.i.i.i.i.i, !llvm.loop !2559

"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i": ; preds = %bb3.i.i.i.i.i.i, %middle.block, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$7reserve17hd2f38306e734cb0aE.exit.i.i.i.i"
  store i64 %_4.sroa.4.0.i.i.i, ptr %_20.i115, align 8
  store ptr %157, ptr %_21.sroa.4.0._20.sroa_idx.i, align 8
  store i64 %columns.sroa.0.0.lcssa.i, ptr %_21.sroa.5.0._20.sroa_idx.i, align 8
; call matrix::zebra
  %_10.i122 = call fastcc noundef zeroext i1 @_ZN6matrix5zebra17h8b469c691e4d7e20E(ptr noalias noundef align 8 captures(address) dereferenceable(24) %_11.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_0.i.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_7.sroa.6.0..sroa_idx.i.i108.le, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) %_20.i115, i64 noundef 1) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %_11.i)
  %163 = icmp eq i64 %_4.sroa.4.0.i.i.i, 0
  br i1 %_10.i122, label %bb11.i125, label %bb12.i

bb12.i:                                           ; preds = %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i"
  br i1 %163, label %bb2.i.i.i123, label %start.split.i.i

start.split.i.i:                                  ; preds = %bb12.i
  call void @free(ptr noundef nonnull %157) #65, !dbg !1104
  br label %bb2.i.i.i123

bb2.i.i.i123:                                     ; preds = %start.split.i.i, %bb12.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_20.i115)
  %_8.i.i.i.i = load i64, ptr %136, align 8, !noalias !2560, !noundef !31
  %val.i.i.i.i = add i64 %_8.i.i.i.i, -1
  store i64 %val.i.i.i.i, ptr %136, align 8, !noalias !2560
  %164 = icmp eq i64 %val.i.i.i.i, 0
  br i1 %164, label %bb1.i.i.i.i124, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i"

bb1.i.i.i.i124:                                   ; preds = %bb2.i.i.i123
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(16) %first.i) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i": ; preds = %bb1.i.i.i.i124, %bb2.i.i.i123
  %165 = icmp eq ptr %137, null
  br i1 %165, label %bb2.i128, label %bb2.i1.i.i

bb2.i1.i.i:                                       ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i"
  %_8.i.i2.i.i = load i64, ptr %137, align 8, !noalias !2567, !noundef !31
  %val.i.i3.i.i = add i64 %_8.i.i2.i.i, -1
  store i64 %val.i.i3.i.i, ptr %137, align 8, !noalias !2567
  %166 = icmp eq i64 %val.i.i3.i.i, 0
  br i1 %166, label %bb1.i.i4.i.i, label %bb2.i128

bb1.i.i4.i.i:                                     ; preds = %bb2.i1.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %83) #103
  br label %bb2.i128

bb11.i125:                                        ; preds = %"_ZN111_$LT$alloc..vec..Vec$LT$T$GT$$u20$as$u20$alloc..vec..spec_from_iter_nested..SpecFromIterNested$LT$T$C$I$GT$$GT$9from_iter17h9fcc9d64c8791fb2E.exit.i"
  br i1 %163, label %bb2.i.i17.i, label %start.split.i14.i

start.split.i14.i:                                ; preds = %bb11.i125
  call void @free(ptr noundef nonnull %157) #65, !dbg !1104
  br label %bb2.i.i17.i

bb2.i.i17.i:                                      ; preds = %start.split.i14.i, %bb11.i125
  call void @llvm.lifetime.end.p0(ptr nonnull %_20.i115)
; call matrix::Permutation::brother
  call fastcc void @_ZN6matrix11Permutation7brother17h85c39cd5cf80aba3E(ptr noalias noundef align 8 captures(none) dereferenceable(24) %cursor.i, ptr nonnull %136, ptr %137) #65
  %_8.i.i.i18.i = load i64, ptr %136, align 8, !noalias !2572, !noundef !31
  %val.i.i.i19.i = add i64 %_8.i.i.i18.i, -1
  store i64 %val.i.i.i19.i, ptr %136, align 8, !noalias !2572
  %167 = icmp eq i64 %val.i.i.i19.i, 0
  br i1 %167, label %bb1.i.i.i25.i, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i20.i"

bb1.i.i.i25.i:                                    ; preds = %bb2.i.i17.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(16) %first.i) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i20.i"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i20.i": ; preds = %bb1.i.i.i25.i, %bb2.i.i17.i
  %168 = icmp eq ptr %137, null
  br i1 %168, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i", label %bb2.i1.i21.i

bb2.i1.i21.i:                                     ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i20.i"
  %_8.i.i2.i22.i = load i64, ptr %137, align 8, !noalias !2579, !noundef !31
  %val.i.i3.i23.i = add i64 %_8.i.i2.i22.i, -1
  store i64 %val.i.i3.i23.i, ptr %137, align 8, !noalias !2579
  %169 = icmp eq i64 %val.i.i3.i23.i, 0
  br i1 %169, label %bb1.i.i4.i24.i, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i"

bb1.i.i4.i24.i:                                   ; preds = %bb2.i1.i21.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %83) #103
  br label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i"

"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i": ; preds = %bb1.i.i4.i24.i, %bb2.i1.i21.i, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i20.i"
  call void @llvm.lifetime.end.p0(ptr nonnull %first.i)
  %_3.i = load i64, ptr %cursor.i, align 8, !range !954, !noundef !31
  %170 = trunc nuw i64 %_3.i to i1
  br i1 %170, label %bb3.i118thread-pre-split, label %bb2.i134

bb37:                                             ; preds = %bb36
  call void @llvm.trap()
  unreachable

bb2.i128:                                         ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i.i", %bb2.i1.i.i, %bb1.i.i4.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %first.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %cursor.i)
  %_8.i.i129 = load i64, ptr %.lcssa706, align 8, !noalias !2584, !noundef !31
  %val.i.i130 = add i64 %_8.i.i129, -1
  store i64 %val.i.i130, ptr %.lcssa706, align 8, !noalias !2584
  %171 = icmp eq i64 %val.i.i130, 0
  br i1 %171, label %bb1.i.i132, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit133"

bb1.i.i132:                                       ; preds = %bb2.i128
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_24) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit133"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit133": ; preds = %bb2.i128, %bb1.i.i132
  call void @llvm.lifetime.end.p0(ptr nonnull %_24)
  br label %bb17

bb2.i134:                                         ; preds = %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i"
  %_10.i122.lcssa697 = phi i1 [ %_10.i122, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit26.i" ]
  call void @llvm.lifetime.end.p0(ptr nonnull %cursor.i)
  %_8.i.i135 = load i64, ptr %.lcssa706, align 8, !noalias !2589, !noundef !31
  %val.i.i136 = add i64 %_8.i.i135, -1
  store i64 %val.i.i136, ptr %.lcssa706, align 8, !noalias !2589
  %172 = icmp eq i64 %val.i.i136, 0
  br i1 %172, label %bb1.i.i138, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139"

bb1.i.i138:                                       ; preds = %bb2.i134
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_24) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139": ; preds = %bb2.i134, %bb1.i.i138
  call void @llvm.lifetime.end.p0(ptr nonnull %_24)
  %173 = getelementptr inbounds nuw i8, ptr %result.sroa.0.0.lcssa.i6.i153199, i64 24
  %174 = load ptr, ptr %173, align 8, !noundef !31
  %.not5 = icmp eq ptr %174, null
  br i1 %.not5, label %bb40, label %bb42

bb17:                                             ; preds = %bb40, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit133"
  %_10.i122699 = phi i1 [ %_10.i122.lcssa697, %bb40 ], [ %_10.i122, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit133" ]
  %175 = getelementptr inbounds nuw i8, ptr %result.sroa.0.0.lcssa.i6.i153199, i64 24
  %176 = load ptr, ptr %175, align 8, !noundef !31
  %.not6 = icmp eq ptr %176, null
  br i1 %.not6, label %bb46, label %bb48

bb42:                                             ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139"
  %_71 = load i64, ptr %174, align 8, !noundef !31
  %_72 = icmp ne i64 %_71, 0
  call void @llvm.assume(i1 %_72)
  %_73 = add i64 %_71, 1
  store i64 %_73, ptr %174, align 8
  %177 = icmp eq i64 %_73, 0
  br i1 %177, label %bb43, label %bb45, !prof !1319

bb40:                                             ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139", %bb45
  %_29.sroa.0.0 = phi ptr [ %_68, %bb45 ], [ null, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit139" ]
; call matrix::search
  call fastcc void @_ZN6matrix6search17hc085af21f9aa784aE(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, i64 noundef %inv_size, i64 noundef %_27, ptr noundef nonnull %126, ptr noundef %_29.sroa.0.0, ptr noalias noundef align 8 dereferenceable(48) %best) #65
  br label %bb17

bb43:                                             ; preds = %bb42
  call void @llvm.trap()
  unreachable

bb45:                                             ; preds = %bb42
  %_68 = load ptr, ptr %173, align 8, !nonnull !31, !noundef !31
  br label %bb40

bb48:                                             ; preds = %bb17
  %_87 = load i64, ptr %176, align 8, !noundef !31
  %_88 = icmp ne i64 %_87, 0
  call void @llvm.assume(i1 %_88)
  %_89 = add i64 %_87, 1
  store i64 %_89, ptr %176, align 8
  %178 = icmp eq i64 %_89, 0
  br i1 %178, label %bb49, label %bb51, !prof !1319

bb46:                                             ; preds = %bb17, %bb51
  %_30.sroa.0.0 = phi ptr [ %_84, %bb51 ], [ null, %bb17 ]
  br i1 %_10.i122699, label %bb18, label %bb2.i143

bb49:                                             ; preds = %bb48
  call void @llvm.trap()
  unreachable

bb51:                                             ; preds = %bb48
  %_84 = load ptr, ptr %175, align 8, !nonnull !31, !noundef !31
  br label %bb46

bb18:                                             ; preds = %bb1.i.i147, %bb2.i143, %bb46
  call void @llvm.lifetime.end.p0(ptr nonnull %candidate)
  %_8.i.i140 = load i64, ptr %result.sroa.0.0.lcssa.i6.i153199, align 8, !noalias !2594, !noundef !31
  %val.i.i141 = add i64 %_8.i.i140, -1
  store i64 %val.i.i141, ptr %result.sroa.0.0.lcssa.i6.i153199, align 8, !noalias !2594
  %179 = icmp eq i64 %val.i.i141, 0
  br i1 %179, label %bb1.i.i142, label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"

bb1.i.i142:                                       ; preds = %bb18
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %next) #103
  br label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"

"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit": ; preds = %bb18, %bb1.i.i142
  call void @llvm.lifetime.end.p0(ptr nonnull %next)
  %.not2 = icmp eq ptr %_30.sroa.0.0, null
  br i1 %.not2, label %bb19, label %bb8

bb2.i143:                                         ; preds = %bb46
  %_8.i.i144 = load i64, ptr %126, align 8, !noalias !2599, !noundef !31
  %val.i.i145 = add i64 %_8.i.i144, -1
  store i64 %val.i.i145, ptr %126, align 8, !noalias !2599
  %180 = icmp eq i64 %val.i.i145, 0
  br i1 %180, label %bb1.i.i147, label %bb18

bb1.i.i147:                                       ; preds = %bb2.i143
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %candidate) #103
  br label %bb18

bb24.sink.split:                                  ; preds = %bb2.i86, %bb2.i74
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %rows) #103
  br label %bb24

bb24:                                             ; preds = %bb24.sink.split, %bb2.i86, %bb2.i74
  ret void
}
