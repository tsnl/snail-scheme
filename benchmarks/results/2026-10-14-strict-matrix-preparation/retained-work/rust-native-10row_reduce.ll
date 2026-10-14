define internal fastcc noalias noundef ptr @_ZN6matrix10row_reduce17h00edd7e88ae65d79E(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noundef %0) unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %_37 = alloca [8 x i8], align 8
  %_35 = alloca [8 x i8], align 8
  %row1 = alloca [8 x i8], align 8
  %zap = alloca [8 x i8], align 8
  %row = alloca [8 x i8], align 8
  %rows = alloca [8 x i8], align 8
  store ptr %0, ptr %rows, align 8
  %.not = icmp eq ptr %0, null
  br i1 %.not, label %bb32, label %bb37

bb37:                                             ; preds = %start
  %1 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %2 = load ptr, ptr %1, align 8, !noundef !31
  %.not6 = icmp eq ptr %2, null
  br i1 %.not6, label %bb34, label %bb3.preheader

bb3.preheader:                                    ; preds = %bb37
  %3 = getelementptr inbounds nuw i8, ptr %field, i64 24
  %field.val17 = load i64, ptr %3, align 8
  %field.val17.fr = freeze i64 %field.val17
  %_4.i.i.i = icmp eq i64 %field.val17.fr, 0
  %_5.i.i.i = icmp eq i64 %field.val17.fr, -1
  %rhs1.sroa.0.0.i.i.i = tail call i64 @llvm.abs.i64(i64 %field.val17.fr, i1 false)
  br i1 %_4.i.i.i, label %bb39.us, label %bb4

bb39.us:                                          ; preds = %bb3.preheader
  call void @llvm.lifetime.start.p0(ptr nonnull %row)
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %5 = load ptr, ptr %4, align 8, !noundef !31
  %.not9.us = icmp eq ptr %5, null
  br i1 %.not9.us, label %bb40.us, label %bb42.us

bb42.us:                                          ; preds = %bb39.us
  %_59.us = load i64, ptr %5, align 8, !noundef !31
  %_60.us = icmp ne i64 %_59.us, 0
  tail call void @llvm.assume(i1 %_60.us)
  %_61.us = add i64 %_59.us, 1
  store i64 %_61.us, ptr %5, align 8
  %6 = icmp eq i64 %_61.us, 0
  br i1 %6, label %bb43, label %bb40.us, !prof !1319

bb40.us:                                          ; preds = %bb42.us, %bb39.us
; call core::panicking::panic_const::panic_const_rem_by_zero
  tail call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const23panic_const_rem_by_zero(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_60c5a064d67551d699ebaedccedd9313) #104
  unreachable

bb4:                                              ; preds = %bb3.preheader, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83"
  %out.sroa.0.0125 = phi ptr [ %49, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83" ], [ null, %bb3.preheader ]
  %7 = phi ptr [ %_9.sroa.0.0, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83" ], [ %0, %bb3.preheader ]
  call void @llvm.lifetime.start.p0(ptr nonnull %row)
  store ptr %7, ptr %row, align 8
  %8 = getelementptr inbounds nuw i8, ptr %7, i64 16
  %9 = load ptr, ptr %8, align 8, !noundef !31
  %.not8 = icmp eq ptr %9, null
  br i1 %.not8, label %bb38, label %bb39, !prof !1319

bb25:                                             ; preds = %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83"
  %.lcssa418 = phi ptr [ %49, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83" ], !dbg !1250
  call void @llvm.lifetime.start.p0(ptr nonnull %_37)
; call matrix::row_reduce
  %10 = tail call fastcc noundef ptr @_ZN6matrix10row_reduce17h00edd7e88ae65d79E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noundef nonnull %.lcssa418) #65
  store ptr %10, ptr %_37, align 8
; call matrix::prepend_column
  %11 = call fastcc noundef ptr @_ZN6matrix14prepend_column17h118b02c0839c62b0E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_37) #65
  %12 = icmp eq ptr %10, null
  br i1 %12, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit", label %bb2.i

bb2.i:                                            ; preds = %bb25
  %_8.i.i = load i64, ptr %10, align 8, !noalias !1320, !noundef !31
  %val.i.i = add i64 %_8.i.i, -1
  store i64 %val.i.i, ptr %10, align 8, !noalias !1320
  %13 = icmp eq i64 %val.i.i, 0
  br i1 %13, label %bb1.i.i, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

bb1.i.i:                                          ; preds = %bb2.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_37) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit": ; preds = %bb25, %bb2.i, %bb1.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_37)
  br label %bb32

bb39:                                             ; preds = %bb4
  %14 = getelementptr inbounds nuw i8, ptr %7, i64 24
  %15 = load ptr, ptr %14, align 8, !noundef !31
  %.not9 = icmp eq ptr %15, null
  br i1 %.not9, label %bb40, label %bb42

bb38:                                             ; preds = %bb4
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_d99798429f603bd7244700661e4dbc7e) #104
  unreachable

bb42:                                             ; preds = %bb39
  %_59 = load i64, ptr %15, align 8, !noundef !31
  %_60 = icmp ne i64 %_59, 0
  tail call void @llvm.assume(i1 %_60)
  %_61 = add i64 %_59, 1
  store i64 %_61, ptr %15, align 8
  %16 = icmp eq i64 %_61, 0
  br i1 %16, label %bb43, label %bb45, !prof !1319

bb40:                                             ; preds = %bb39, %bb45
  %_69 = phi ptr [ %_69.pre, %bb45 ], [ %9, %bb39 ]
  %_9.sroa.0.0 = phi ptr [ %_56, %bb45 ], [ null, %bb39 ]
  store ptr %_9.sroa.0.0, ptr %rows, align 8
  %17 = getelementptr inbounds nuw i8, ptr %_69, i64 16
  %_11 = load i64, ptr %17, align 8, !noundef !31
  %_6.i.i.i = icmp eq i64 %_11, -9223372036854775808
  %_7.i.i.i = and i1 %_6.i.i.i, %_5.i.i.i
  br i1 %_7.i.i.i, label %panic2.i.i.i, label %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit

panic2.i.i.i:                                     ; preds = %bb40
; call core::panicking::panic_const::panic_const_rem_overflow
  tail call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const24panic_const_rem_overflow(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_60c5a064d67551d699ebaedccedd9313) #104
  unreachable

_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit:   ; preds = %bb40
  %r.i.i.i = srem i64 %_11, %field.val17.fr
  %_8.i.i.i = icmp slt i64 %r.i.i.i, 0
  %18 = select i1 %_8.i.i.i, i64 %rhs1.sroa.0.0.i.i.i, i64 0
  %_0.sroa.0.0.i.i.i = sub nsw i64 0, %r.i.i.i
  %_0.i = icmp eq i64 %18, %_0.sroa.0.0.i.i.i
  br i1 %_0.i, label %bb6, label %_ZN6matrix5Field6reduce17he506c12b8e7fdac0E.exit.i

bb43:                                             ; preds = %bb42, %bb42.us
  tail call void @llvm.trap()
  unreachable

bb45:                                             ; preds = %bb42
  %_56 = load ptr, ptr %14, align 8, !nonnull !31, !noundef !31
  %_69.pre = load ptr, ptr %8, align 8
  br label %bb40

_ZN6matrix5Field6reduce17he506c12b8e7fdac0E.exit.i: ; preds = %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit
  %r.i.i.i.lcssa = phi i64 [ %r.i.i.i, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  %.lcssa410 = phi i64 [ %18, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  %_69.lcssa406 = phi ptr [ %_69, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  %_9.sroa.0.0.lcssa402 = phi ptr [ %_9.sroa.0.0, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  %out.sroa.0.0125.lcssa398 = phi ptr [ %out.sroa.0.0125, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  %.lcssa392 = phi ptr [ %7, %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit ]
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1325)
  %_0.sroa.0.0.i.i.i28 = add nsw i64 %r.i.i.i.lcssa, -1
  %_5.i = add i64 %_0.sroa.0.0.i.i.i28, %.lcssa410
  %19 = getelementptr inbounds nuw i8, ptr %field, i64 16
  %_9.i = load i64, ptr %19, align 8, !alias.scope !1325, !noundef !31
  %_11.i = icmp ult i64 %_5.i, %_9.i
  br i1 %_11.i, label %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit, label %panic.i

panic.i:                                          ; preds = %_ZN6matrix5Field6reduce17he506c12b8e7fdac0E.exit.i
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef %_5.i, i64 noundef %_9.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_c9f1d2bc5b229c09904b0cd96b990b99) #104, !noalias !1325
  unreachable

_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit: ; preds = %_ZN6matrix5Field6reduce17he506c12b8e7fdac0E.exit.i
  %_16 = getelementptr inbounds nuw i8, ptr %_69.lcssa406, i64 24
  %20 = getelementptr inbounds nuw i8, ptr %field, i64 8
  %_10.i = load ptr, ptr %20, align 8, !alias.scope !1325, !nonnull !31, !noundef !31
  %_3.i = getelementptr inbounds nuw i64, ptr %_10.i, i64 %_5.i
  %_0.i30 = load i64, ptr %_3.i, align 8, !noalias !1325, !noundef !31
; call matrix::scale
  %21 = tail call fastcc noundef ptr @_ZN6matrix5scale17h3fc454c5a3d61a8dE(i64 %field.val17.fr, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_16, i64 noundef %_0.i30) #65
  store ptr %21, ptr %zap, align 8
  %.not10126 = icmp eq ptr %_9.sroa.0.0.lcssa402, null
  br i1 %.not10126, label %bb19, label %bb12

bb6:                                              ; preds = %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit
  %22 = getelementptr inbounds nuw i8, ptr %_69, i64 24
  %23 = load ptr, ptr %22, align 8, !noundef !31
  %.not15 = icmp eq ptr %23, null
  br i1 %.not15, label %bb46, label %bb48

bb12:                                             ; preds = %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68"
  %out.sroa.0.1127 = phi ptr [ %40, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68" ], [ %out.sroa.0.0125.lcssa398, %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit ]
  %24 = phi ptr [ %_31.sroa.0.0, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68" ], [ %_9.sroa.0.0.lcssa402, %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit ]
  call void @llvm.lifetime.start.p0(ptr nonnull %row1)
  store ptr %24, ptr %row1, align 8
  %25 = getelementptr inbounds nuw i8, ptr %24, i64 16
  %26 = load ptr, ptr %25, align 8, !noundef !31
  %.not12 = icmp eq ptr %26, null
  br i1 %.not12, label %bb52, label %bb1.i.i.i46, !prof !1319

bb19:                                             ; preds = %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68", %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit
  %out.sroa.0.1.lcssa = phi ptr [ %out.sroa.0.0125.lcssa398, %_ZN6matrix5Field10reciprocal17h98edd6a6be4bcf65E.exit ], [ %40, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68" ]
  %27 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1328
  %28 = icmp eq ptr %27, null
  br i1 %28, label %bb2.i.i, label %_ZN6matrix6number17heeef4114a060e7afE.exit, !prof !1319

bb2.i.i:                                          ; preds = %bb19
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1328
  unreachable

_ZN6matrix6number17heeef4114a060e7afE.exit:       ; preds = %bb19
  store i64 1, ptr %27, align 8
  %_7.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %27, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i, align 8
  %_7.sroa.5.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %27, i64 16
  store i64 1, ptr %_7.sroa.5.0..sroa_idx.i, align 8
  %_7.sroa.6.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %27, i64 24
  store ptr %21, ptr %_7.sroa.6.0..sroa_idx.i, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %_35)
; call matrix::row_reduce
  %29 = tail call fastcc noundef ptr @_ZN6matrix10row_reduce17h00edd7e88ae65d79E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noundef %out.sroa.0.1.lcssa) #65
  store ptr %29, ptr %_35, align 8
; call matrix::prepend_column
  %_33 = call fastcc noundef ptr @_ZN6matrix14prepend_column17h118b02c0839c62b0E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_35) #65
  %30 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1331
  %31 = icmp eq ptr %30, null
  br i1 %31, label %bb2.i.i36, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit, !prof !1319

bb2.i.i36:                                        ; preds = %_ZN6matrix6number17heeef4114a060e7afE.exit
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1331
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit:       ; preds = %_ZN6matrix6number17heeef4114a060e7afE.exit
  store i64 1, ptr %30, align 8
  %_7.sroa.4.0..sroa_idx.i33 = getelementptr inbounds nuw i8, ptr %30, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i33, align 8
  %_7.sroa.5.0..sroa_idx.i34 = getelementptr inbounds nuw i8, ptr %30, i64 16
  store ptr %27, ptr %_7.sroa.5.0..sroa_idx.i34, align 8
  %_7.sroa.6.0..sroa_idx.i35 = getelementptr inbounds nuw i8, ptr %30, i64 24
  store ptr %_33, ptr %_7.sroa.6.0..sroa_idx.i35, align 8
  %32 = icmp eq ptr %29, null
  br i1 %32, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41", label %bb2.i37

bb2.i37:                                          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit
  %_8.i.i38 = load i64, ptr %29, align 8, !noalias !1334, !noundef !31
  %val.i.i39 = add i64 %_8.i.i38, -1
  store i64 %val.i.i39, ptr %29, align 8, !noalias !1334
  %33 = icmp eq i64 %val.i.i39, 0
  br i1 %33, label %bb1.i.i40, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41"

bb1.i.i40:                                        ; preds = %bb2.i37
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %_35) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41": ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit, %bb2.i37, %bb1.i.i40
  call void @llvm.lifetime.end.p0(ptr nonnull %_35)
  %_8.i.i42 = load i64, ptr %.lcssa392, align 8, !noalias !1339, !noundef !31
  %val.i.i43 = add i64 %_8.i.i42, -1
  store i64 %val.i.i43, ptr %.lcssa392, align 8, !noalias !1339
  %34 = icmp eq i64 %val.i.i43, 0
  br i1 %34, label %bb1.i.i44, label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"

bb1.i.i44:                                        ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41"
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %row) #103
  br label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit"

"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit": ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit41", %bb1.i.i44
  call void @llvm.lifetime.end.p0(ptr nonnull %row)
  br label %bb32

bb1.i.i.i46:                                      ; preds = %bb12
  %35 = getelementptr inbounds nuw i8, ptr %26, i64 16
  %_25 = load i64, ptr %35, align 8, !noundef !31
  %_6.i.i.i48 = icmp eq i64 %_25, -9223372036854775808
  %_7.i.i.i49 = and i1 %_5.i.i.i, %_6.i.i.i48
  br i1 %_7.i.i.i49, label %panic2.i.i.i56, label %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit58

panic2.i.i.i56:                                   ; preds = %bb1.i.i.i46
; call core::panicking::panic_const::panic_const_rem_overflow
  tail call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core9panicking11panic_const24panic_const_rem_overflow(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_60c5a064d67551d699ebaedccedd9313) #104
  unreachable

_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit58: ; preds = %bb1.i.i.i46
  %r.i.i.i51 = srem i64 %_25, %field.val17.fr
  %_8.i.i.i52 = icmp slt i64 %r.i.i.i51, 0
  %36 = select i1 %_8.i.i.i52, i64 %rhs1.sroa.0.0.i.i.i, i64 0
  %_0.sroa.0.0.i.i.i54 = sub nsw i64 0, %r.i.i.i51
  %_0.i55 = icmp eq i64 %36, %_0.sroa.0.0.i.i.i54
  %37 = getelementptr inbounds nuw i8, ptr %26, i64 24
  br i1 %_0.i55, label %bb14, label %bb15

bb52:                                             ; preds = %bb12
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_9c1718b673c4cf5213892071089844ef) #104
  unreachable

bb15:                                             ; preds = %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit58
  %_28 = sub i64 0, %_25
; call matrix::combine
  %38 = call fastcc noundef ptr @_ZN6matrix7combine17h24c574d4280bb634E(i64 %field.val17.fr, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %37, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %zap, i64 noundef %_28) #65
  br label %bb17

bb14:                                             ; preds = %_ZN6matrix5Field4zero17hecdcf04d078c8ba6E.exit58
  %39 = load ptr, ptr %37, align 8, !noundef !31
  %.not13 = icmp eq ptr %39, null
  br i1 %.not13, label %bb17, label %bb56

bb17:                                             ; preds = %bb14, %bb59, %bb15
  %tail.sroa.0.0 = phi ptr [ %_93, %bb59 ], [ %38, %bb15 ], [ null, %bb14 ]
  %40 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1344
  %41 = icmp eq ptr %40, null
  br i1 %41, label %bb2.i.i62, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit63, !prof !1319

bb2.i.i62:                                        ; preds = %bb17
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1344
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit63:     ; preds = %bb17
  store i64 1, ptr %40, align 8
  %_7.sroa.4.0..sroa_idx.i59 = getelementptr inbounds nuw i8, ptr %40, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i59, align 8
  %_7.sroa.5.0..sroa_idx.i60 = getelementptr inbounds nuw i8, ptr %40, i64 16
  store ptr %tail.sroa.0.0, ptr %_7.sroa.5.0..sroa_idx.i60, align 8
  %_7.sroa.6.0..sroa_idx.i61 = getelementptr inbounds nuw i8, ptr %40, i64 24
  store ptr %out.sroa.0.1127, ptr %_7.sroa.6.0..sroa_idx.i61, align 8
  %42 = getelementptr inbounds nuw i8, ptr %24, i64 24
  %43 = load ptr, ptr %42, align 8, !noundef !31
  %.not14 = icmp eq ptr %43, null
  br i1 %.not14, label %bb60, label %bb62

bb56:                                             ; preds = %bb14
  %_96 = load i64, ptr %39, align 8, !noundef !31
  %_97 = icmp ne i64 %_96, 0
  tail call void @llvm.assume(i1 %_97)
  %_98 = add i64 %_96, 1
  store i64 %_98, ptr %39, align 8
  %44 = icmp eq i64 %_98, 0
  br i1 %44, label %bb57, label %bb59, !prof !1319

bb57:                                             ; preds = %bb56
  tail call void @llvm.trap()
  unreachable

bb59:                                             ; preds = %bb56
  %_93 = load ptr, ptr %37, align 8, !nonnull !31, !noundef !31
  br label %bb17

bb62:                                             ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit63
  %_112 = load i64, ptr %43, align 8, !noundef !31
  %_113 = icmp ne i64 %_112, 0
  tail call void @llvm.assume(i1 %_113)
  %_114 = add i64 %_112, 1
  store i64 %_114, ptr %43, align 8
  %45 = icmp eq i64 %_114, 0
  br i1 %45, label %bb63, label %bb65, !prof !1319

bb60:                                             ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit63, %bb65
  %_31.sroa.0.0 = phi ptr [ %_109, %bb65 ], [ null, %_ZN6matrix6matrix17he37191504af5b7c1E.exit63 ]
  store ptr %_31.sroa.0.0, ptr %rows, align 8
  %_8.i.i65 = load i64, ptr %24, align 8, !noalias !1347, !noundef !31
  %val.i.i66 = add i64 %_8.i.i65, -1
  store i64 %val.i.i66, ptr %24, align 8, !noalias !1347
  %46 = icmp eq i64 %val.i.i66, 0
  br i1 %46, label %bb1.i.i67, label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68"

bb1.i.i67:                                        ; preds = %bb60
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %row1) #103
  br label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68"

"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit68": ; preds = %bb60, %bb1.i.i67
  call void @llvm.lifetime.end.p0(ptr nonnull %row1)
  %.not10 = icmp eq ptr %_31.sroa.0.0, null
  br i1 %.not10, label %bb19, label %bb12

bb63:                                             ; preds = %bb62
  tail call void @llvm.trap()
  unreachable

bb65:                                             ; preds = %bb62
  %_109 = load ptr, ptr %42, align 8, !nonnull !31, !noundef !31
  br label %bb60

bb32:                                             ; preds = %start, %bb1.i.i72, %bb34, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit", %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit"
  %_0.sroa.0.0 = phi ptr [ %11, %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit" ], [ null, %bb1.i.i72 ], [ %30, %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit" ], [ null, %bb34 ], [ null, %start ]
  ret ptr %_0.sroa.0.0

bb34:                                             ; preds = %bb37
  %_8.i.i70 = load i64, ptr %0, align 8, !noalias !1352, !noundef !31
  %val.i.i71 = add i64 %_8.i.i70, -1
  store i64 %val.i.i71, ptr %0, align 8, !noalias !1352
  %47 = icmp eq i64 %val.i.i71, 0
  br i1 %47, label %bb1.i.i72, label %bb32

bb1.i.i72:                                        ; preds = %bb34
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %rows) #103
  br label %bb32

bb48:                                             ; preds = %bb6
  %_75 = load i64, ptr %23, align 8, !noundef !31
  %_76 = icmp ne i64 %_75, 0
  tail call void @llvm.assume(i1 %_76)
  %_77 = add i64 %_75, 1
  store i64 %_77, ptr %23, align 8
  %48 = icmp eq i64 %_77, 0
  br i1 %48, label %bb49, label %bb51, !prof !1319

bb46:                                             ; preds = %bb6, %bb51
  %_13.sroa.0.0 = phi ptr [ %_72, %bb51 ], [ null, %bb6 ]
  %49 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1357
  %50 = icmp eq ptr %49, null
  br i1 %50, label %bb2.i.i77, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit78, !prof !1319

bb2.i.i77:                                        ; preds = %bb46
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1357
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit78:     ; preds = %bb46
  store i64 1, ptr %49, align 8
  %_7.sroa.4.0..sroa_idx.i74 = getelementptr inbounds nuw i8, ptr %49, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i74, align 8
  %_7.sroa.5.0..sroa_idx.i75 = getelementptr inbounds nuw i8, ptr %49, i64 16
  store ptr %_13.sroa.0.0, ptr %_7.sroa.5.0..sroa_idx.i75, align 8
  %_7.sroa.6.0..sroa_idx.i76 = getelementptr inbounds nuw i8, ptr %49, i64 24
  store ptr %out.sroa.0.0125, ptr %_7.sroa.6.0..sroa_idx.i76, align 8
  %_8.i.i80 = load i64, ptr %7, align 8, !noalias !1360, !noundef !31
  %val.i.i81 = add i64 %_8.i.i80, -1
  store i64 %val.i.i81, ptr %7, align 8, !noalias !1360
  %51 = icmp eq i64 %val.i.i81, 0
  br i1 %51, label %bb1.i.i82, label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83"

bb1.i.i82:                                        ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit78
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %row) #103
  br label %"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83"

"_ZN4core3ptr60drop_in_place$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$17h3898b77770d9dd48E.exit83": ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit78, %bb1.i.i82
  call void @llvm.lifetime.end.p0(ptr nonnull %row)
  %.not7 = icmp eq ptr %_9.sroa.0.0, null
  br i1 %.not7, label %bb25, label %bb4

bb49:                                             ; preds = %bb48
  tail call void @llvm.trap()
  unreachable

bb51:                                             ; preds = %bb48
  %_72 = load ptr, ptr %22, align 8, !nonnull !31, !noundef !31
  br label %bb46
}
