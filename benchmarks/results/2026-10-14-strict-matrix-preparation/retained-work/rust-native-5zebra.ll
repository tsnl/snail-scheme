define internal fastcc noundef zeroext i1 @_ZN6matrix5zebra17h8b469c691e4d7e20E(ptr dead_on_return noalias noundef nonnull align 8 captures(none) dereferenceable(24) %cursor, ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(8) %first, ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(8) %rows, ptr noalias noundef nonnull readonly align 8 captures(address) %partitions.0, i64 noundef range(i64 0, 384307168202282326) %partitions.1) unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %minus.i = alloca [24 x i8], align 8
  %plus.i = alloca [24 x i8], align 8
  %refined.i = alloca [24 x i8], align 8
  %values.i = alloca [24 x i8], align 8
  %_24 = alloca [24 x i8], align 8
  %iter = alloca [32 x i8], align 8
  %permutation = alloca [16 x i8], align 8
  %_5166 = load i64, ptr %cursor, align 8, !range !954, !noundef !31
  %0 = trunc nuw i64 %_5166 to i1
  br i1 %0, label %bb2.lr.ph, label %bb26

bb2.lr.ph:                                        ; preds = %start
  %1 = getelementptr inbounds nuw i8, ptr %cursor, i64 8
  %2 = getelementptr inbounds nuw i8, ptr %cursor, i64 16
  %3 = getelementptr inbounds nuw i8, ptr %permutation, i64 8
  %4 = load ptr, ptr %rows, align 8, !noundef !31
  %.not = icmp eq ptr %4, null
  %_9.sroa.5.0.iter.sroa_idx = getelementptr inbounds nuw i8, ptr %iter, i64 8
  %_9.sroa.6.0.iter.sroa_idx = getelementptr inbounds nuw i8, ptr %iter, i64 16
  %_9.sroa.7.0.iter.sroa_idx = getelementptr inbounds nuw i8, ptr %iter, i64 24
  %_16 = getelementptr inbounds nuw i8, ptr %4, i64 16
  %5 = getelementptr inbounds nuw i8, ptr %values.i, i64 8
  %6 = getelementptr inbounds nuw i8, ptr %values.i, i64 16
  %7 = getelementptr inbounds nuw i8, ptr %refined.i, i64 8
  %8 = getelementptr inbounds nuw i8, ptr %refined.i, i64 16
  %_41.idx.i = mul nuw nsw i64 %partitions.1, 24
  %_41.i = getelementptr inbounds nuw i8, ptr %partitions.0, i64 %_41.idx.i
  %_4878.i = icmp eq i64 %partitions.1, 0
  %_10.sroa.2.0.plus.sroa_idx.i = getelementptr inbounds nuw i8, ptr %plus.i, i64 8
  %_10.sroa.3.0.plus.sroa_idx.i = getelementptr inbounds nuw i8, ptr %plus.i, i64 16
  %_11.sroa.2.0.minus.sroa_idx.i = getelementptr inbounds nuw i8, ptr %minus.i, i64 8
  %_11.sroa.3.0.minus.sroa_idx.i = getelementptr inbounds nuw i8, ptr %minus.i, i64 16
  %_26 = getelementptr inbounds nuw i8, ptr %4, i64 24
  br i1 %.not, label %bb2.us, label %bb2.preheader, !prof !1319

bb2.preheader:                                    ; preds = %bb2.lr.ph
  %9 = getelementptr inbounds nuw i8, ptr %_24, i64 8
  %10 = getelementptr inbounds nuw i8, ptr %_24, i64 16
  br label %bb2

bb2.us:                                           ; preds = %bb2.lr.ph
  call void @llvm.lifetime.start.p0(ptr nonnull %permutation)
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_b410dfce2835bc9116578fbe3e49b02f) #104
  unreachable

bb2:                                              ; preds = %bb2.preheader, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit"
  %_15.sroa.7.sroa.5.0168 = phi i64 [ %_15.sroa.7.sroa.5.2241255.lcssa, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit" ], [ undef, %bb2.preheader ]
  %_15.sroa.7.sroa.0.0167 = phi ptr [ %_15.sroa.7.sroa.0.2239257.lcssa, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit" ], [ undef, %bb2.preheader ]
  call void @llvm.lifetime.start.p0(ptr nonnull %permutation)
  %11 = load ptr, ptr %1, align 8, !noundef !31
  %12 = load ptr, ptr %2, align 8, !noundef !31
  store ptr %11, ptr %permutation, align 8
  store ptr %12, ptr %3, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %iter)
  store i64 2, ptr %_9.sroa.5.0.iter.sroa_idx, align 8
  store i64 1, ptr %_9.sroa.6.0.iter.sroa_idx, align 8
  store i64 -1, ptr %_9.sroa.7.0.iter.sroa_idx, align 8
  %.not.i = icmp eq ptr %11, null
  %_0.i = getelementptr inbounds nuw i8, ptr %11, i64 16
  br i1 %.not.i, label %bb5.us, label %bb5.preheader, !prof !1319

bb5.preheader:                                    ; preds = %bb2
  %13 = getelementptr inbounds nuw i8, ptr %11, i64 24
  %.not27.i = icmp eq ptr %12, null
  br label %bb5

bb5.us:                                           ; preds = %bb2
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_8822e31da2eb3253489717f3d2aef9a3) #104
  unreachable

bb5:                                              ; preds = %bb5.preheader, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit"
  %14 = phi i64 [ 1, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit" ], [ 0, %bb5.preheader ]
  %_15.sroa.7.sroa.5.1140 = phi i64 [ %_15.sroa.7.sroa.5.2241255, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit" ], [ %_15.sroa.7.sroa.5.0168, %bb5.preheader ]
  %_15.sroa.7.sroa.0.1139 = phi ptr [ %_15.sroa.7.sroa.0.2239257, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit" ], [ %_15.sroa.7.sroa.0.0167, %bb5.preheader ]
  %_11.i = add nuw nsw i64 %14, 1
  store i64 %_11.i, ptr %iter, align 8, !alias.scope !2253
  %self3.i = getelementptr inbounds nuw i64, ptr %_9.sroa.6.0.iter.sroa_idx, i64 %14
  %_14.i = load i64, ptr %self3.i, align 8, !alias.scope !2253, !noundef !31
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2256)
  call void @llvm.lifetime.start.p0(ptr nonnull %values.i), !noalias !2259
  store i64 0, ptr %values.i, align 8, !noalias !2259
  store ptr inttoptr (i64 8 to ptr), ptr %5, align 8, !noalias !2259
  store i64 0, ptr %6, align 8, !noalias !2259
  %15 = load ptr, ptr %_0.i, align 8, !alias.scope !2256, !noalias !2262, !noundef !31
  %.not2.i = icmp eq ptr %15, null
  br i1 %.not2.i, label %_ZN6matrix10normalized17h57971e6854951785E.exit, label %bb2.lr.ph.i

bb2.lr.ph.i:                                      ; preds = %bb5
  %16 = sub i64 0, %_14.i
  br label %bb2.i7

bb2.i7:                                           ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i", %bb2.lr.ph.i
  %_14.i.i553 = phi ptr [ inttoptr (i64 8 to ptr), %bb2.lr.ph.i ], [ %_14.i.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i" ]
  %len.i.i = phi i64 [ 0, %bb2.lr.ph.i ], [ %21, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i" ]
  %17 = phi ptr [ %15, %bb2.lr.ph.i ], [ %24, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i" ]
  %first.sroa.0.03.i = phi ptr [ %first, %bb2.lr.ph.i ], [ %23, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i" ]
  %18 = load ptr, ptr %first.sroa.0.03.i, align 8, !noalias !2263, !noundef !31
  %.not1.i = icmp eq ptr %18, null
  br i1 %.not1.i, label %bb8.i, label %bb9.i, !prof !1319

bb9.i:                                            ; preds = %bb2.i7
  %19 = getelementptr inbounds nuw i8, ptr %18, i64 16
  %_12.i = load i64, ptr %19, align 8, !noalias !2259, !noundef !31
  %20 = getelementptr inbounds nuw i8, ptr %17, i64 16
  %_13.i = load i64, ptr %20, align 8, !noalias !2259, !noundef !31
  %_11.i8 = icmp eq i64 %_12.i, %_13.i
  %_10.sroa.0.0.i = select i1 %_11.i8, i64 %_14.i, i64 %16
  %self1.i.i = load i64, ptr %values.i, align 8, !range !1117, !alias.scope !2264, !noalias !2259, !noundef !31
  %_4.i.i = icmp eq i64 %len.i.i, %self1.i.i
  br i1 %_4.i.i, label %bb1.i.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i"

bb1.i.i:                                          ; preds = %bb9.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1a919c860bf3f0ecE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %values.i) #103, !noalias !2259
  %_14.i.i.pre = load ptr, ptr %5, align 8, !alias.scope !2264, !noalias !2259
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i": ; preds = %bb1.i.i, %bb9.i
  %_14.i.i = phi ptr [ %_14.i.i.pre, %bb1.i.i ], [ %_14.i.i553, %bb9.i ]
  %end.i.i = getelementptr inbounds nuw i64, ptr %_14.i.i, i64 %len.i.i
  store i64 %_10.sroa.0.0.i, ptr %end.i.i, align 8, !noalias !2259
  %21 = add i64 %len.i.i, 1
  store i64 %21, ptr %6, align 8, !alias.scope !2264, !noalias !2259
  %22 = getelementptr inbounds nuw i8, ptr %17, i64 24
  %23 = getelementptr inbounds nuw i8, ptr %18, i64 24
  %24 = load ptr, ptr %22, align 8, !noalias !2259, !noundef !31
  %.not.i9 = icmp eq ptr %24, null
  br i1 %.not.i9, label %_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit, label %bb2.i7

bb8.i:                                            ; preds = %bb2.i7
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_94eb63f9f13c84d91e78ea6118cf9ad3) #104, !noalias !2259
  unreachable

_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit: ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i"
  %.lcssa = phi i64 [ %21, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17hcbe01e35bf639703E.exit.i" ]
  %_18.sroa.0.0.copyload.pre = load i64, ptr %values.i, align 8, !noalias !2267
  %_18.sroa.6.0.copyload.pre = load ptr, ptr %5, align 8, !noalias !2267
  %25 = icmp eq i64 %_18.sroa.0.0.copyload.pre, 0
  br label %_ZN6matrix10normalized17h57971e6854951785E.exit

_ZN6matrix10normalized17h57971e6854951785E.exit:  ; preds = %_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit, %bb5
  %_18.sroa.9.0.copyload = phi i64 [ %.lcssa, %_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit ], [ 0, %bb5 ]
  %_18.sroa.6.0.copyload = phi ptr [ %_18.sroa.6.0.copyload.pre, %_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit ], [ inttoptr (i64 8 to ptr), %bb5 ]
  %_18.sroa.0.0.copyload = phi i1 [ %25, %_ZN6matrix10normalized17h57971e6854951785E.exit.loopexit ], [ true, %bb5 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %values.i), !noalias !2259
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2268)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2271)
  call void @llvm.lifetime.start.p0(ptr nonnull %minus.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %plus.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %refined.i), !noalias !2273
  store i64 0, ptr %refined.i, align 8, !noalias !2273
  store ptr inttoptr (i64 8 to ptr), ptr %7, align 8, !noalias !2273
  store i64 0, ptr %8, align 8, !noalias !2273
  br i1 %_4878.i, label %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245, label %bb28.i

_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245: ; preds = %_ZN6matrix10normalized17h57971e6854951785E.exit
  call void @llvm.lifetime.end.p0(ptr nonnull %refined.i), !noalias !2273
  call void @llvm.lifetime.end.p0(ptr nonnull %minus.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %plus.i)
  br label %bb8.i465

bb28.i:                                           ; preds = %_ZN6matrix10normalized17h57971e6854951785E.exit, %bb19.i
  %old.sroa.0.080.i = phi ptr [ %old.sroa.0.3.lcssa.i, %bb19.i ], [ %_16, %_ZN6matrix10normalized17h57971e6854951785E.exit ]
  %iter.sroa.0.079.i = phi ptr [ %_54.i, %bb19.i ], [ %partitions.0, %_ZN6matrix10normalized17h57971e6854951785E.exit ]
  %_54.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.079.i, i64 24
  store i64 0, ptr %plus.i, align 8, !noalias !2273
  store ptr inttoptr (i64 8 to ptr), ptr %_10.sroa.2.0.plus.sroa_idx.i, align 8, !noalias !2273
  store i64 0, ptr %_10.sroa.3.0.plus.sroa_idx.i, align 8, !noalias !2273
  store i64 0, ptr %minus.i, align 8, !noalias !2273
  store ptr inttoptr (i64 8 to ptr), ptr %_11.sroa.2.0.minus.sroa_idx.i, align 8, !noalias !2273
  store i64 0, ptr %_11.sroa.3.0.minus.sroa_idx.i, align 8, !noalias !2273
  %26 = getelementptr inbounds nuw i8, ptr %iter.sroa.0.079.i, i64 8
  %_59.i = load ptr, ptr %26, align 8, !alias.scope !2271, !noalias !2276, !nonnull !31, !noundef !31
  %27 = getelementptr inbounds nuw i8, ptr %iter.sroa.0.079.i, i64 16
  %_58.i = load i64, ptr %27, align 8, !alias.scope !2271, !noalias !2276, !noundef !31
  %_63.idx.i = shl nuw nsw i64 %_58.i, 3
  %_63.i = getelementptr inbounds nuw i8, ptr %_59.i, i64 %_63.idx.i
  %_6971.i = icmp eq i64 %_58.i, 0
  br i1 %_6971.i, label %bb35.i, label %bb30.i

bb30.i:                                           ; preds = %bb28.i, %bb9.i16
  %_14.i87.i = phi ptr [ %_14.i88.i, %bb9.i16 ], [ inttoptr (i64 8 to ptr), %bb28.i ]
  %len.i.i10 = phi i64 [ %len.i85.i, %bb9.i16 ], [ 0, %bb28.i ]
  %old.sroa.0.173.i = phi ptr [ %old.sroa.0.2.i, %bb9.i16 ], [ %old.sroa.0.080.i, %bb28.i ]
  %iter1.sroa.0.072.i = phi ptr [ %_75.i, %bb9.i16 ], [ %_59.i, %bb28.i ]
  %_75.i = getelementptr inbounds nuw i8, ptr %iter1.sroa.0.072.i, i64 8
  %column.i = load i64, ptr %iter1.sroa.0.072.i, align 8, !noalias !2273, !noundef !31
  %_17.i = icmp ult i64 %column.i, %_18.sroa.9.0.copyload
  br i1 %_17.i, label %bb4.i, label %panic.i

bb29.i:                                           ; preds = %bb9.i16
  %len.i85.i.lcssa = phi i64 [ %len.i85.i, %bb9.i16 ]
  %old.sroa.0.2.i.lcssa = phi ptr [ %old.sroa.0.2.i, %bb9.i16 ]
  %_80.pre.i = load ptr, ptr %_11.sroa.2.0.minus.sroa_idx.i, align 8, !noalias !2273
  %_84.idx.i = shl nuw nsw i64 %len.i85.i.lcssa, 3
  %_84.i = getelementptr inbounds nuw i8, ptr %_80.pre.i, i64 %_84.idx.i
  %_9774.i = icmp eq i64 %len.i85.i.lcssa, 0
  br i1 %_9774.i, label %bb35.i, label %bb36.i

bb4.i:                                            ; preds = %bb30.i
  %28 = getelementptr inbounds nuw i64, ptr %_18.sroa.6.0.copyload, i64 %column.i
  %_15.i = load i64, ptr %28, align 8, !alias.scope !2268, !noalias !2277, !noundef !31
  %29 = icmp eq i64 %_15.i, 1
  br i1 %29, label %bb5.i, label %bb8.i11

panic.i:                                          ; preds = %bb30.i
  %_18.sroa.9.0.copyload.lcssa = phi i64 [ %_18.sroa.9.0.copyload, %bb30.i ]
  %column.i.lcssa = phi i64 [ %column.i, %bb30.i ]
; call core::panicking::panic_bounds_check
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core9panicking18panic_bounds_check(i64 noundef %column.i.lcssa, i64 noundef range(i64 0, 1152921504606846976) %_18.sroa.9.0.copyload.lcssa, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_26c224f0e44753d64bdf2171aa2bcc98) #104, !noalias !2273
  unreachable

bb5.i:                                            ; preds = %bb4.i
  %30 = load ptr, ptr %old.sroa.0.173.i, align 8, !noalias !2278, !noundef !31
  %.not.i18 = icmp eq ptr %30, null
  br i1 %.not.i18, label %bb31.i, label %bb32.i, !prof !1319

bb8.i11:                                          ; preds = %bb4.i
  %self1.i.i12 = load i64, ptr %minus.i, align 8, !range !1117, !noalias !2273, !noundef !31
  %_4.i.i13 = icmp eq i64 %len.i.i10, %self1.i.i12
  br i1 %_4.i.i13, label %bb1.i.i17, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i"

bb1.i.i17:                                        ; preds = %bb8.i11
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1a8a596198001465E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %minus.i) #103, !noalias !2273
  %_14.i.pre.i = load ptr, ptr %_11.sroa.2.0.minus.sroa_idx.i, align 8, !noalias !2273
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i": ; preds = %bb1.i.i17, %bb8.i11
  %_14.i.i14 = phi ptr [ %_14.i87.i, %bb8.i11 ], [ %_14.i.pre.i, %bb1.i.i17 ]
  %end.i.i15 = getelementptr inbounds nuw i64, ptr %_14.i.i14, i64 %len.i.i10
  store i64 %column.i, ptr %end.i.i15, align 8, !noalias !2279
  %31 = add i64 %len.i.i10, 1
  store i64 %31, ptr %_11.sroa.3.0.minus.sroa_idx.i, align 8, !noalias !2273
  br label %bb9.i16

bb32.i:                                           ; preds = %bb5.i
  %32 = getelementptr inbounds nuw i8, ptr %30, i64 16
  %_20.i = load i64, ptr %32, align 8, !noalias !2273, !noundef !31
  %33 = icmp eq i64 %_20.i, 1
  br i1 %33, label %bb7.i, label %bb20.i

bb31.i:                                           ; preds = %bb5.i
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_0ba6edefd221925dcef087be703e3a45) #104, !noalias !2273
  unreachable

bb7.i:                                            ; preds = %bb32.i
  %34 = getelementptr inbounds nuw i8, ptr %30, i64 24
  %len.i14.i = load i64, ptr %_10.sroa.3.0.plus.sroa_idx.i, align 8, !noalias !2273, !noundef !31
  %self1.i15.i = load i64, ptr %plus.i, align 8, !range !1117, !noalias !2273, !noundef !31
  %_4.i16.i = icmp eq i64 %len.i14.i, %self1.i15.i
  br i1 %_4.i16.i, label %bb1.i19.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i"

bb1.i19.i:                                        ; preds = %bb7.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1a8a596198001465E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %plus.i) #103, !noalias !2273
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i": ; preds = %bb1.i19.i, %bb7.i
  %_14.i17.i = load ptr, ptr %_10.sroa.2.0.plus.sroa_idx.i, align 8, !noalias !2273, !nonnull !31, !noundef !31
  %end.i18.i = getelementptr inbounds nuw i64, ptr %_14.i17.i, i64 %len.i14.i
  store i64 %column.i, ptr %end.i18.i, align 8, !noalias !2282
  %35 = add i64 %len.i14.i, 1
  store i64 %35, ptr %_10.sroa.3.0.plus.sroa_idx.i, align 8, !noalias !2273
  br label %bb9.i16

bb9.i16:                                          ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i", %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i"
  %_14.i88.i = phi ptr [ %_14.i87.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i" ], [ %_14.i.i14, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i" ]
  %len.i85.i = phi i64 [ %len.i.i10, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i" ], [ %31, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i" ]
  %old.sroa.0.2.i = phi ptr [ %34, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit20.i" ], [ %old.sroa.0.173.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h5f4723966e69b453E.exit.i" ]
  %_69.i = icmp eq ptr %_75.i, %_63.i
  br i1 %_69.i, label %bb29.i, label %bb30.i

bb20.i:                                           ; preds = %bb32.i, %bb38.i
  %storemerge.i = phi i64 [ 1, %bb38.i ], [ 0, %bb32.i ]
  %minus.val12.i = load i64, ptr %minus.i, align 8, !range !1117, !noalias !2273, !noundef !31
  %36 = icmp eq i64 %minus.val12.i, 0
  br i1 %36, label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i", label %bb2.i.i.i.i.i

bb2.i.i.i.i.i:                                    ; preds = %bb20.i
  %minus.val13.i = load ptr, ptr %_11.sroa.2.0.minus.sroa_idx.i, align 8, !noalias !2273, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %minus.val13.i) #65, !dbg !1104
  br label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i"

"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i": ; preds = %bb2.i.i.i.i.i, %bb20.i
  %plus.val10.i = load i64, ptr %plus.i, align 8, !range !1117, !noalias !2273, !noundef !31
  %37 = icmp eq i64 %plus.val10.i, 0
  br i1 %37, label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i", label %bb2.i.i.i.i21.i

bb2.i.i.i.i21.i:                                  ; preds = %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i"
  %plus.val11.i = load ptr, ptr %_10.sroa.2.0.plus.sroa_idx.i, align 8, !noalias !2273, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %plus.val11.i) #65, !dbg !1104
  br label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i"

"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i": ; preds = %bb2.i.i.i.i21.i, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i"
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2285)
  %_1.val.i.i = load ptr, ptr %7, align 8, !alias.scope !2285, !noalias !2273, !nonnull !31, !noundef !31
  %_1.val1.i.i = load i64, ptr %8, align 8, !alias.scope !2285, !noalias !2273, !noundef !31
  %_74.i.i.i.i = icmp eq i64 %_1.val1.i.i, 0
  br i1 %_74.i.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i.i", label %bb2.i.i.i.i

bb2.i.i.i.i:                                      ; preds = %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i", %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i"
  %_3.sroa.0.05.i.i.i.i = phi i64 [ %38, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i" ], [ 0, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i" ]
  %_6.i.i.i.i = getelementptr inbounds nuw %"alloc::vec::Vec<usize>", ptr %_1.val.i.i, i64 %_3.sroa.0.05.i.i.i.i
  %38 = add nuw i64 %_3.sroa.0.05.i.i.i.i, 1
  %_6.val.i.i.i.i = load i64, ptr %_6.i.i.i.i, align 8, !range !1117, !alias.scope !2288, !noalias !2291, !noundef !31
  %39 = icmp eq i64 %_6.val.i.i.i.i, 0
  br i1 %39, label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i", label %bb2.i.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i.i:                              ; preds = %bb2.i.i.i.i
  %40 = getelementptr i8, ptr %_6.i.i.i.i, i64 8
  %_6.val3.i.i.i.i = load ptr, ptr %40, align 8, !alias.scope !2288, !noalias !2291, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %_6.val3.i.i.i.i) #65, !dbg !1104
  br label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i"

"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i": ; preds = %bb2.i.i.i.i.i.i.i.i, %bb2.i.i.i.i
  %_7.i.i.i.i = icmp eq i64 %38, %_1.val1.i.i
  br i1 %_7.i.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i.i", label %bb2.i.i.i.i

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i.i": ; preds = %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i.i", %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit23.i"
  %_1.val2.i.i = load i64, ptr %refined.i, align 8, !range !1117, !alias.scope !2285, !noalias !2273, !noundef !31
  %41 = icmp eq i64 %_1.val2.i.i, 0
  br i1 %41, label %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread, label %bb2.i.i.i.i24.i

bb2.i.i.i.i24.i:                                  ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i.i"
  tail call void @free(ptr noundef nonnull %_1.val.i.i) #65, !dbg !1104
  br label %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread

bb10.i:                                           ; preds = %bb38.i
  %42 = getelementptr inbounds nuw i8, ptr %43, i64 24
  %_97.i = icmp eq ptr %_102.i, %_84.i
  br i1 %_97.i, label %bb35.i, label %bb36.i

bb36.i:                                           ; preds = %bb29.i, %bb10.i
  %old.sroa.0.376.i = phi ptr [ %42, %bb10.i ], [ %old.sroa.0.2.i.lcssa, %bb29.i ]
  %iter2.sroa.0.075.i = phi ptr [ %_102.i, %bb10.i ], [ %_80.pre.i, %bb29.i ]
  %_102.i = getelementptr inbounds nuw i8, ptr %iter2.sroa.0.075.i, i64 8
  %43 = load ptr, ptr %old.sroa.0.376.i, align 8, !noalias !2278, !noundef !31
  %.not5.i = icmp eq ptr %43, null
  br i1 %.not5.i, label %bb37.i, label %bb38.i, !prof !1319

bb35.i:                                           ; preds = %bb10.i, %bb29.i, %bb28.i
  %_9774103.i = phi i1 [ true, %bb29.i ], [ true, %bb28.i ], [ false, %bb10.i ]
  %_84102.i = phi ptr [ %_84.i, %bb29.i ], [ inttoptr (i64 8 to ptr), %bb28.i ], [ %_84.i, %bb10.i ]
  %_80101.i = phi ptr [ %_80.pre.i, %bb29.i ], [ inttoptr (i64 8 to ptr), %bb28.i ], [ %_80.pre.i, %bb10.i ]
  %_79100.i = phi i64 [ 0, %bb29.i ], [ 0, %bb28.i ], [ %len.i85.i.lcssa, %bb10.i ]
  %old.sroa.0.3.lcssa.i = phi ptr [ %old.sroa.0.2.i.lcssa, %bb29.i ], [ %old.sroa.0.080.i, %bb28.i ], [ %42, %bb10.i ]
  %_108.i = load ptr, ptr %_10.sroa.2.0.plus.sroa_idx.i, align 8, !noalias !2273, !nonnull !31, !noundef !31
  %_107.i = load i64, ptr %_10.sroa.3.0.plus.sroa_idx.i, align 8, !noalias !2273, !noundef !31
  %_1126.i = lshr i64 %_107.i, 1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2292)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2295)
  %_917.not.i.i = icmp eq i64 %_1126.i, 0
  br i1 %_917.not.i.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i", label %bb5.preheader.i.i

bb5.preheader.i.i:                                ; preds = %bb35.i
  %_118.i = getelementptr inbounds nuw i64, ptr %_108.i, i64 %_107.i
  %min.iters.check351 = icmp ult i64 %_107.i, 8
  br i1 %min.iters.check351, label %bb6.i.i.preheader, label %vector.ph352

vector.ph352:                                     ; preds = %bb5.preheader.i.i
  %n.vec354 = and i64 %_1126.i, 9223372036854775804
  br label %vector.body355

vector.body355:                                   ; preds = %vector.body355, %vector.ph352
  %index356 = phi i64 [ 0, %vector.ph352 ], [ %index.next365, %vector.body355 ]
  %44 = xor i64 %index356, -1
  %45 = getelementptr inbounds nuw i64, ptr %_108.i, i64 %index356
  %46 = getelementptr i64, ptr %_118.i, i64 %44
  %47 = getelementptr inbounds nuw i8, ptr %45, i64 16
  %wide.load357 = load <2 x i64>, ptr %45, align 8, !alias.scope !2292, !noalias !2297
  %wide.load358 = load <2 x i64>, ptr %47, align 8, !alias.scope !2292, !noalias !2297
  %48 = getelementptr i8, ptr %46, i64 -8
  %49 = getelementptr i8, ptr %46, i64 -24
  %wide.load359 = load <2 x i64>, ptr %48, align 8, !alias.scope !2295, !noalias !2298
  %wide.load360 = load <2 x i64>, ptr %49, align 8, !alias.scope !2295, !noalias !2298
  %reverse361 = shufflevector <2 x i64> %wide.load359, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %reverse362 = shufflevector <2 x i64> %wide.load360, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  store <2 x i64> %reverse361, ptr %45, align 8, !alias.scope !2292, !noalias !2297
  store <2 x i64> %reverse362, ptr %47, align 8, !alias.scope !2292, !noalias !2297
  %reverse363 = shufflevector <2 x i64> %wide.load357, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %reverse364 = shufflevector <2 x i64> %wide.load358, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  store <2 x i64> %reverse363, ptr %48, align 8, !alias.scope !2295, !noalias !2298
  store <2 x i64> %reverse364, ptr %49, align 8, !alias.scope !2295, !noalias !2298
  %index.next365 = add nuw nsw i64 %index356, 4
  %50 = icmp eq i64 %index.next365, %n.vec354
  br i1 %50, label %middle.block366, label %vector.body355, !llvm.loop !2299

middle.block366:                                  ; preds = %vector.body355
  %cmp.n367 = icmp eq i64 %_1126.i, %n.vec354
  br i1 %cmp.n367, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i", label %bb6.i.i.preheader

bb6.i.i.preheader:                                ; preds = %bb5.preheader.i.i, %middle.block366
  %i.sroa.0.018.i.i.ph = phi i64 [ %n.vec354, %middle.block366 ], [ 0, %bb5.preheader.i.i ]
  br label %bb6.i.i

bb6.i.i:                                          ; preds = %bb6.i.i.preheader, %bb6.i.i
  %i.sroa.0.018.i.i = phi i64 [ %54, %bb6.i.i ], [ %i.sroa.0.018.i.i.ph, %bb6.i.i.preheader ]
  %51 = xor i64 %i.sroa.0.018.i.i, -1
  %x.i.i = getelementptr inbounds nuw i64, ptr %_108.i, i64 %i.sroa.0.018.i.i
  %y.i.i = getelementptr i64, ptr %_118.i, i64 %51
  %52 = load i64, ptr %x.i.i, align 8, !alias.scope !2292, !noalias !2297, !noundef !31
  %53 = load i64, ptr %y.i.i, align 8, !alias.scope !2295, !noalias !2298
  store i64 %53, ptr %x.i.i, align 8, !alias.scope !2292, !noalias !2297
  store i64 %52, ptr %y.i.i, align 8, !alias.scope !2295, !noalias !2298
  %54 = add nuw nsw i64 %i.sroa.0.018.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %54, %_1126.i
  br i1 %exitcond.not.i.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i", label %bb6.i.i, !llvm.loop !2302

"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i": ; preds = %bb6.i.i, %middle.block366, %bb35.i
  %_1287.i = lshr i64 %_79100.i, 1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2303)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2306)
  %_917.not.i26.i = icmp eq i64 %_1287.i, 0
  br i1 %_917.not.i26.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i", label %bb6.i28.i.preheader

bb6.i28.i.preheader:                              ; preds = %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i"
  %min.iters.check = icmp ult i64 %_79100.i, 8
  br i1 %min.iters.check, label %bb6.i28.i.preheader648, label %vector.ph

vector.ph:                                        ; preds = %bb6.i28.i.preheader
  %n.vec = and i64 %_1287.i, 9223372036854775804
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i64 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %55 = xor i64 %index, -1
  %56 = getelementptr inbounds nuw i64, ptr %_80101.i, i64 %index
  %57 = getelementptr i64, ptr %_84102.i, i64 %55
  %58 = getelementptr inbounds nuw i8, ptr %56, i64 16
  %wide.load = load <2 x i64>, ptr %56, align 8, !alias.scope !2303, !noalias !2308
  %wide.load344 = load <2 x i64>, ptr %58, align 8, !alias.scope !2303, !noalias !2308
  %59 = getelementptr i8, ptr %57, i64 -8
  %60 = getelementptr i8, ptr %57, i64 -24
  %wide.load345 = load <2 x i64>, ptr %59, align 8, !alias.scope !2306, !noalias !2309
  %wide.load346 = load <2 x i64>, ptr %60, align 8, !alias.scope !2306, !noalias !2309
  %reverse = shufflevector <2 x i64> %wide.load345, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %reverse347 = shufflevector <2 x i64> %wide.load346, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  store <2 x i64> %reverse, ptr %56, align 8, !alias.scope !2303, !noalias !2308
  store <2 x i64> %reverse347, ptr %58, align 8, !alias.scope !2303, !noalias !2308
  %reverse348 = shufflevector <2 x i64> %wide.load, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %reverse349 = shufflevector <2 x i64> %wide.load344, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  store <2 x i64> %reverse348, ptr %59, align 8, !alias.scope !2306, !noalias !2309
  store <2 x i64> %reverse349, ptr %60, align 8, !alias.scope !2306, !noalias !2309
  %index.next = add nuw nsw i64 %index, 4
  %61 = icmp eq i64 %index.next, %n.vec
  br i1 %61, label %middle.block, label %vector.body, !llvm.loop !2310

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %_1287.i, %n.vec
  br i1 %cmp.n, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i", label %bb6.i28.i.preheader648

bb6.i28.i.preheader648:                           ; preds = %bb6.i28.i.preheader, %middle.block
  %i.sroa.0.018.i29.i.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %bb6.i28.i.preheader ]
  br label %bb6.i28.i

bb6.i28.i:                                        ; preds = %bb6.i28.i.preheader648, %bb6.i28.i
  %i.sroa.0.018.i29.i = phi i64 [ %65, %bb6.i28.i ], [ %i.sroa.0.018.i29.i.ph, %bb6.i28.i.preheader648 ]
  %62 = xor i64 %i.sroa.0.018.i29.i, -1
  %x.i30.i = getelementptr inbounds nuw i64, ptr %_80101.i, i64 %i.sroa.0.018.i29.i
  %y.i31.i = getelementptr i64, ptr %_84102.i, i64 %62
  %63 = load i64, ptr %x.i30.i, align 8, !alias.scope !2303, !noalias !2308, !noundef !31
  %64 = load i64, ptr %y.i31.i, align 8, !alias.scope !2306, !noalias !2309
  store i64 %64, ptr %x.i30.i, align 8, !alias.scope !2303, !noalias !2308
  store i64 %63, ptr %y.i31.i, align 8, !alias.scope !2306, !noalias !2309
  %65 = add nuw nsw i64 %i.sroa.0.018.i29.i, 1
  %exitcond.not.i32.i = icmp eq i64 %65, %_1287.i
  br i1 %exitcond.not.i32.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i", label %bb6.i28.i, !llvm.loop !2311

"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i": ; preds = %bb6.i28.i, %middle.block, %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit.i"
  %_141.i = icmp ult i64 %_107.i, 1152921504606846976
  tail call void @llvm.assume(i1 %_141.i)
  %66 = icmp ne i64 %_107.i, 0
  br i1 %66, label %bb14.i, label %bb15.i

bb38.i:                                           ; preds = %bb36.i
  %67 = getelementptr inbounds nuw i8, ptr %43, i64 16
  %_26.i = load i64, ptr %67, align 8, !noalias !2273, !noundef !31
  %68 = icmp eq i64 %_26.i, 1
  br i1 %68, label %bb20.i, label %bb10.i

bb37.i:                                           ; preds = %bb36.i
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_2baeaccd0d7814c4c05a63b074a48a66) #104, !noalias !2273
  unreachable

bb14.i:                                           ; preds = %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i"
  %len.i34.i = load i64, ptr %8, align 8, !alias.scope !2312, !noalias !2315, !noundef !31
  %self1.i35.i = load i64, ptr %refined.i, align 8, !range !1117, !alias.scope !2312, !noalias !2315, !noundef !31
  %_4.i36.i = icmp eq i64 %len.i34.i, %self1.i35.i
  br i1 %_4.i36.i, label %bb1.i39.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit.i"

bb1.i39.i:                                        ; preds = %bb14.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h5794fcd5d51613d7E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %refined.i) #103, !noalias !2315
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit.i": ; preds = %bb1.i39.i, %bb14.i
  %_14.i37.i = load ptr, ptr %7, align 8, !alias.scope !2312, !noalias !2315, !nonnull !31, !noundef !31
  %end.i38.i = getelementptr inbounds nuw %"alloc::vec::Vec<usize>", ptr %_14.i37.i, i64 %len.i34.i
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %end.i38.i, ptr noundef nonnull align 8 dereferenceable(24) %plus.i, i64 24, i1 false), !noalias !2273
  %69 = add i64 %len.i34.i, 1
  store i64 %69, ptr %8, align 8, !alias.scope !2312, !noalias !2315
  br label %bb15.i

bb15.i:                                           ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit.i", %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$7reverse7revswap17h64227b461f6d09ebE.exit33.i"
  %_144.i = icmp ult i64 %_79100.i, 1152921504606846976
  tail call void @llvm.assume(i1 %_144.i)
  br i1 %_9774103.i, label %bb25.i, label %bb17.i

bb17.i:                                           ; preds = %bb15.i
  %len.i40.i = load i64, ptr %8, align 8, !alias.scope !2317, !noalias !2320, !noundef !31
  %self1.i41.i = load i64, ptr %refined.i, align 8, !range !1117, !alias.scope !2317, !noalias !2320, !noundef !31
  %_4.i42.i = icmp eq i64 %len.i40.i, %self1.i41.i
  br i1 %_4.i42.i, label %bb1.i45.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit46.i"

bb1.i45.i:                                        ; preds = %bb17.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h5794fcd5d51613d7E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %refined.i) #103, !noalias !2320
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit46.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit46.i": ; preds = %bb1.i45.i, %bb17.i
  %_14.i43.i = load ptr, ptr %7, align 8, !alias.scope !2317, !noalias !2320, !nonnull !31, !noundef !31
  %end.i44.i = getelementptr inbounds nuw %"alloc::vec::Vec<usize>", ptr %_14.i43.i, i64 %len.i40.i
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %end.i44.i, ptr noundef nonnull align 8 dereferenceable(24) %minus.i, i64 24, i1 false), !noalias !2273
  %70 = add i64 %len.i40.i, 1
  store i64 %70, ptr %8, align 8, !alias.scope !2317, !noalias !2320
  br label %bb18.i

bb25.i:                                           ; preds = %bb15.i
  %minus.val.i = load i64, ptr %minus.i, align 8, !range !1117, !noalias !2273, !noundef !31
  %71 = icmp eq i64 %minus.val.i, 0
  br i1 %71, label %bb18.i, label %bb2.i.i.i.i47.i

bb2.i.i.i.i47.i:                                  ; preds = %bb25.i
  tail call void @free(ptr noundef nonnull %_80101.i) #65, !dbg !1104
  br label %bb18.i

bb18.i:                                           ; preds = %bb2.i.i.i.i47.i, %bb25.i, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h11a553f809c2831eE.exit46.i"
  %plus.val.i = load i64, ptr %plus.i, align 8, !range !1117
  %72 = icmp eq i64 %plus.val.i, 0
  %or.cond = select i1 %66, i1 true, i1 %72
  br i1 %or.cond, label %bb19.i, label %bb2.i.i.i.i50.i

bb19.i:                                           ; preds = %bb2.i.i.i.i50.i, %bb18.i
  %_48.i = icmp eq ptr %_54.i, %_41.i
  br i1 %_48.i, label %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit, label %bb28.i

bb2.i.i.i.i50.i:                                  ; preds = %bb18.i
  tail call void @free(ptr noundef nonnull %_108.i) #65, !dbg !1104
  br label %bb19.i

_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread: ; preds = %bb2.i.i.i.i24.i, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i.i"
  call void @llvm.lifetime.end.p0(ptr nonnull %refined.i), !noalias !2273
  call void @llvm.lifetime.end.p0(ptr nonnull %minus.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %plus.i)
  br label %75

_ZN6matrix11compare_row17he3a7eced9e1850caE.exit: ; preds = %bb19.i
  %_15.sroa.0.0.copyload52.pre = load i64, ptr %refined.i, align 8, !noalias !2322
  %_15.sroa.0.0.copyload52.pre.fr = freeze i64 %_15.sroa.0.0.copyload52.pre
  %_15.sroa.7.sroa.0.0.copyload.pre = load ptr, ptr %7, align 8, !noalias !2322
  %_15.sroa.7.sroa.5.0.copyload.pre = load i64, ptr %8, align 8, !noalias !2322
  call void @llvm.lifetime.end.p0(ptr nonnull %refined.i), !noalias !2273
  call void @llvm.lifetime.end.p0(ptr nonnull %minus.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %plus.i)
  %73 = xor i64 %_15.sroa.0.0.copyload52.pre.fr, -9223372036854775808
  %74 = icmp slt i64 %_15.sroa.0.0.copyload52.pre.fr, 0
  br i1 %74, label %75, label %bb8.i465

75:                                               ; preds = %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread
  %_15.sroa.7.sroa.5.2241 = phi i64 [ %_15.sroa.7.sroa.5.1140, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread ], [ %_15.sroa.7.sroa.5.0.copyload.pre, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ]
  %_15.sroa.7.sroa.0.2239 = phi ptr [ %_15.sroa.7.sroa.0.1139, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread ], [ %_15.sroa.7.sroa.0.0.copyload.pre, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ]
  %76 = phi i64 [ %storemerge.i, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread ], [ %73, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ]
  switch i64 %76, label %bb4 [
    i64 0, label %bb28
    i64 1, label %bb27
    i64 2, label %bb8.i465
  ]

bb6:                                              ; preds = %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit"
  %_15.sroa.7.sroa.0.2239257.lcssa = phi ptr [ %_15.sroa.7.sroa.0.2239257, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit" ]
  %_15.sroa.7.sroa.5.2241255.lcssa = phi i64 [ %_15.sroa.7.sroa.5.2241255, %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit" ]
  call void @llvm.lifetime.end.p0(ptr nonnull %iter)
; call matrix::Permutation::brother
  tail call fastcc void @_ZN6matrix11Permutation7brother17h85c39cd5cf80aba3E(ptr noalias noundef align 8 captures(none) dereferenceable(24) %cursor, ptr nonnull %11, ptr %12) #65
  %_8.i.i.i = load i64, ptr %11, align 8, !noalias !2323, !noundef !31
  %val.i.i.i = add i64 %_8.i.i.i, -1
  store i64 %val.i.i.i, ptr %11, align 8, !noalias !2323
  %77 = icmp eq i64 %val.i.i.i, 0
  br i1 %77, label %bb1.i.i.i, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i"

bb1.i.i.i:                                        ; preds = %bb6
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(16) %permutation) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i": ; preds = %bb1.i.i.i, %bb6
  br i1 %.not27.i, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit", label %bb2.i1.i

bb2.i1.i:                                         ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i"
  %_8.i.i2.i = load i64, ptr %12, align 8, !noalias !2330, !noundef !31
  %val.i.i3.i = add i64 %_8.i.i2.i, -1
  store i64 %val.i.i3.i, ptr %12, align 8, !noalias !2330
  %78 = icmp eq i64 %val.i.i3.i, 0
  br i1 %78, label %bb1.i.i4.i, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit"

bb1.i.i4.i:                                       ; preds = %bb2.i1.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %3) #103
  br label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit"

"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit": ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i", %bb2.i1.i, %bb1.i.i4.i
  call void @llvm.lifetime.end.p0(ptr nonnull %permutation)
  %_5 = load i64, ptr %cursor, align 8, !range !954, !noundef !31
  %79 = trunc nuw i64 %_5 to i1
  br i1 %79, label %bb2, label %bb26

bb4:                                              ; preds = %75
  unreachable

bb27:                                             ; preds = %bb2.i.i.i.i49, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47", %75
  %_15.sroa.7.sroa.0.2239257 = phi ptr [ %_15.sroa.7.sroa.0.2239256, %bb2.i.i.i.i49 ], [ %_15.sroa.7.sroa.0.2239256, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47" ], [ %_15.sroa.7.sroa.0.2239, %75 ]
  %_15.sroa.7.sroa.5.2241255 = phi i64 [ %_15.sroa.7.sroa.5.2241254, %bb2.i.i.i.i49 ], [ %_15.sroa.7.sroa.5.2241254, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47" ], [ %_15.sroa.7.sroa.5.2241, %75 ]
  br i1 %_18.sroa.0.0.copyload, label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit", label %bb2.i.i.i.i19

bb2.i.i.i.i19:                                    ; preds = %bb27
  tail call void @free(ptr noundef nonnull %_18.sroa.6.0.copyload) #65, !dbg !1104
  br label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit"

"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$i64$GT$$GT$17h0ab5e44e0a915fffE.exit": ; preds = %bb27, %bb2.i.i.i.i19
  %_5.not.i = icmp eq i64 %_11.i, 2
  br i1 %_5.not.i, label %bb6, label %bb5

bb8.i465:                                         ; preds = %75, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit
  %_15.sroa.7.sroa.0.2239256 = phi ptr [ %_15.sroa.7.sroa.0.2239, %75 ], [ %_15.sroa.7.sroa.0.0.copyload.pre, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ], [ inttoptr (i64 8 to ptr), %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245 ]
  %_15.sroa.7.sroa.5.2241254 = phi i64 [ %_15.sroa.7.sroa.5.2241, %75 ], [ %_15.sroa.7.sroa.5.0.copyload.pre, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ], [ 0, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245 ]
  %_15.sroa.0.0243253 = phi i64 [ 1, %75 ], [ %_15.sroa.0.0.copyload52.pre.fr, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit ], [ 0, %_ZN6matrix11compare_row17he3a7eced9e1850caE.exit.thread245 ]
  call void @llvm.lifetime.start.p0(ptr nonnull %_24)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2335)
  %80 = load ptr, ptr %13, align 8, !noalias !2335, !noundef !31
  %.not1.i466 = icmp eq ptr %80, null
  br i1 %.not1.i466, label %bb9.i470.thread, label %bb11.i

bb11.i:                                           ; preds = %bb8.i465
  %_20.i467 = load i64, ptr %80, align 8, !noalias !2335, !noundef !31
  %_21.i = icmp ne i64 %_20.i467, 0
  tail call void @llvm.assume(i1 %_21.i)
  %_22.i = add i64 %_20.i467, 1
  store i64 %_22.i, ptr %80, align 8, !noalias !2335
  %81 = icmp eq i64 %_22.i, 0
  br i1 %81, label %bb12.i, label %bb9.i470, !prof !1319

bb9.i470:                                         ; preds = %bb11.i
  %_17.i469 = load ptr, ptr %13, align 8, !noalias !2335, !nonnull !31, !noundef !31
  br i1 %.not27.i, label %bb4.i.i, label %bb2.i.preheader

bb9.i470.thread:                                  ; preds = %bb8.i465
  br i1 %.not27.i, label %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit, label %bb2.i.preheader

bb2.i.preheader:                                  ; preds = %bb9.i470, %bb9.i470.thread
  %future.sroa.0.18.i.ph = phi ptr [ null, %bb9.i470.thread ], [ %_17.i469, %bb9.i470 ]
  br label %bb2.i

bb12.i:                                           ; preds = %bb11.i
  tail call void @llvm.trap()
  unreachable

bb2.i:                                            ; preds = %bb2.i.preheader, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i
  %82 = phi ptr [ %88, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i ], [ %12, %bb2.i.preheader ]
  %future.sroa.0.18.i = phi ptr [ %86, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i ], [ %future.sroa.0.18.i.ph, %bb2.i.preheader ]
  %83 = getelementptr inbounds nuw i8, ptr %82, i64 16
  %84 = load ptr, ptr %83, align 8, !noalias !2335, !noundef !31
  %.not3.i = icmp eq ptr %84, null
  br i1 %.not3.i, label %bb15.i473, label %bb17.i471

bb4.i.i:                                          ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i, %bb9.i470
  %future.sroa.0.1.lcssa17.i = phi ptr [ %_17.i469, %bb9.i470 ], [ %86, %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i ]
  store ptr %future.sroa.0.1.lcssa17.i, ptr %9, align 8, !alias.scope !2338
  store ptr null, ptr %10, align 8, !alias.scope !2338
  br label %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit

bb17.i471:                                        ; preds = %bb2.i
  %_36.i = load i64, ptr %84, align 8, !noalias !2335, !noundef !31
  %_37.i = icmp ne i64 %_36.i, 0
  tail call void @llvm.assume(i1 %_37.i)
  %_38.i = add i64 %_36.i, 1
  store i64 %_38.i, ptr %84, align 8, !noalias !2335
  %85 = icmp eq i64 %_38.i, 0
  br i1 %85, label %bb18.i476, label %bb20.i472, !prof !1319

bb15.i473:                                        ; preds = %bb20.i472, %bb2.i
  %_7.sroa.0.0.i = phi ptr [ %_33.i, %bb20.i472 ], [ null, %bb2.i ]
  %86 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !2341
  %87 = icmp eq ptr %86, null
  br i1 %87, label %bb2.i.i.i475, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit.i, !prof !1319

bb2.i.i.i475:                                     ; preds = %bb15.i473
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !2344
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit.i:     ; preds = %bb15.i473
  store i64 1, ptr %86, align 8, !noalias !2335
  %_7.sroa.4.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %86, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i, align 8, !noalias !2335
  %_7.sroa.5.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %86, i64 16
  store ptr %_7.sroa.0.0.i, ptr %_7.sroa.5.0..sroa_idx.i.i, align 8, !noalias !2335
  %_7.sroa.6.0..sroa_idx.i.i = getelementptr inbounds nuw i8, ptr %86, i64 24
  store ptr %future.sroa.0.18.i, ptr %_7.sroa.6.0..sroa_idx.i.i, align 8, !noalias !2335
  %past.sroa.0.0.i = getelementptr inbounds nuw i8, ptr %82, i64 24
  %88 = load ptr, ptr %past.sroa.0.0.i, align 8, !noalias !2335, !noundef !31
  %.not2.i474 = icmp eq ptr %88, null
  br i1 %.not2.i474, label %bb4.i.i, label %bb2.i

bb18.i476:                                        ; preds = %bb17.i471
  tail call void @llvm.trap()
  unreachable

bb20.i472:                                        ; preds = %bb17.i471
  %_33.i = load ptr, ptr %83, align 8, !noalias !2335, !nonnull !31, !noundef !31
  br label %bb15.i473

_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit: ; preds = %bb9.i470.thread, %bb4.i.i
  %storemerge.i.i = phi i64 [ 1, %bb4.i.i ], [ 0, %bb9.i470.thread ]
  store i64 %storemerge.i.i, ptr %_24, align 8, !alias.scope !2338
  %89 = icmp ne ptr %_15.sroa.7.sroa.0.2239256, null
  tail call void @llvm.assume(i1 %89)
; call matrix::zebra
  %_23 = call fastcc noundef zeroext i1 @_ZN6matrix5zebra17h8b469c691e4d7e20E(ptr noalias noundef align 8 captures(address) dereferenceable(24) %_24, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %first, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_26, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) %_15.sroa.7.sroa.0.2239256, i64 noundef %_15.sroa.7.sroa.5.2241254) #65
  call void @llvm.lifetime.end.p0(ptr nonnull %_24)
  %_74.i.i.i37 = icmp eq i64 %_15.sroa.7.sroa.5.2241254, 0
  br i1 %_23, label %bb14, label %bb15

bb28:                                             ; preds = %75, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i"
  %.not27.i728 = phi i1 [ %.not27.i, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i" ], [ %.not27.i, %75 ]
  %90 = phi ptr [ %11, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i" ], [ %11, %75 ]
  %91 = phi ptr [ %12, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i" ], [ %12, %75 ]
  %_18.sroa.6.0.copyload684 = phi ptr [ %_18.sroa.6.0.copyload, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i" ], [ %_18.sroa.6.0.copyload, %75 ]
  %_18.sroa.0.0.copyload674 = phi i1 [ %_18.sroa.0.0.copyload, %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i" ], [ %_18.sroa.0.0.copyload, %75 ]
  br i1 %_18.sroa.0.0.copyload674, label %bb2.i.i23, label %bb2.i.i.i.i20

bb2.i.i.i.i20:                                    ; preds = %bb2.i.i.i.i33, %bb28
  %_18.sroa.6.0.copyload684731 = phi ptr [ %_18.sroa.6.0.copyload, %bb2.i.i.i.i33 ], [ %_18.sroa.6.0.copyload684, %bb28 ]
  %92 = phi ptr [ %12, %bb2.i.i.i.i33 ], [ %91, %bb28 ]
  %93 = phi ptr [ %11, %bb2.i.i.i.i33 ], [ %90, %bb28 ]
  %.not27.i728729 = phi i1 [ %.not27.i, %bb2.i.i.i.i33 ], [ %.not27.i728, %bb28 ]
  tail call void @free(ptr noundef nonnull %_18.sroa.6.0.copyload684731) #65, !dbg !1104
  br label %bb2.i.i23

bb2.i.i23:                                        ; preds = %bb2.i.i.i.i33, %bb2.i.i.i.i20, %bb28
  %94 = phi ptr [ %12, %bb2.i.i.i.i33 ], [ %92, %bb2.i.i.i.i20 ], [ %91, %bb28 ]
  %95 = phi ptr [ %11, %bb2.i.i.i.i33 ], [ %93, %bb2.i.i.i.i20 ], [ %90, %bb28 ]
  %.not27.i728730 = phi i1 [ %.not27.i, %bb2.i.i.i.i33 ], [ %.not27.i728729, %bb2.i.i.i.i20 ], [ %.not27.i728, %bb28 ]
  call void @llvm.lifetime.end.p0(ptr nonnull %iter)
  %_8.i.i.i24 = load i64, ptr %95, align 8, !noalias !2345, !noundef !31
  %val.i.i.i25 = add i64 %_8.i.i.i24, -1
  store i64 %val.i.i.i25, ptr %95, align 8, !noalias !2345
  %96 = icmp eq i64 %val.i.i.i25, 0
  br i1 %96, label %bb1.i.i.i31, label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i26"

bb1.i.i.i31:                                      ; preds = %bb2.i.i23
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(16) %permutation) #103
  br label %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i26"

"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i26": ; preds = %bb1.i.i.i31, %bb2.i.i23
  br i1 %.not27.i728730, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32", label %bb2.i1.i27

bb2.i1.i27:                                       ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i26"
  %_8.i.i2.i28 = load i64, ptr %94, align 8, !noalias !2352, !noundef !31
  %val.i.i3.i29 = add i64 %_8.i.i2.i28, -1
  store i64 %val.i.i3.i29, ptr %94, align 8, !noalias !2352
  %97 = icmp eq i64 %val.i.i3.i29, 0
  br i1 %97, label %bb1.i.i4.i30, label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32"

bb1.i.i4.i30:                                     ; preds = %bb2.i1.i27
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h9e7bdfd20efd7218E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %3) #103
  br label %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32"

"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32": ; preds = %"_ZN4core3ptr88drop_in_place$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..MatrixCell$GT$$GT$$GT$17he0a1e64550aade55E.exit.i26", %bb2.i1.i27, %bb1.i.i4.i30
  call void @llvm.lifetime.end.p0(ptr nonnull %permutation)
  br label %bb26

bb15:                                             ; preds = %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit
  br i1 %_74.i.i.i37, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i", label %bb2.i.i.i

bb2.i.i.i:                                        ; preds = %bb15, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i"
  %_3.sroa.0.05.i.i.i = phi i64 [ %98, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i" ], [ 0, %bb15 ]
  %_6.i.i.i = getelementptr inbounds nuw %"alloc::vec::Vec<usize>", ptr %_15.sroa.7.sroa.0.2239256, i64 %_3.sroa.0.05.i.i.i
  %98 = add nuw i64 %_3.sroa.0.05.i.i.i, 1
  %_6.val.i.i.i = load i64, ptr %_6.i.i.i, align 8, !range !1117, !alias.scope !2357, !noalias !2360, !noundef !31
  %99 = icmp eq i64 %_6.val.i.i.i, 0
  br i1 %99, label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i", label %bb2.i.i.i.i.i.i.i

bb2.i.i.i.i.i.i.i:                                ; preds = %bb2.i.i.i
  %100 = getelementptr i8, ptr %_6.i.i.i, i64 8
  %_6.val3.i.i.i = load ptr, ptr %100, align 8, !alias.scope !2357, !noalias !2360, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %_6.val3.i.i.i) #65, !dbg !1104
  br label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i"

"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i": ; preds = %bb2.i.i.i.i.i.i.i, %bb2.i.i.i
  %_7.i.i.i = icmp eq i64 %98, %_15.sroa.7.sroa.5.2241254
  br i1 %_7.i.i.i, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i", label %bb2.i.i.i

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i": ; preds = %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i", %bb15
  %101 = icmp eq i64 %_15.sroa.0.0243253, 0
  br i1 %101, label %bb28, label %bb2.i.i.i.i33

bb2.i.i.i.i33:                                    ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i"
  tail call void @free(ptr noundef nonnull %_15.sroa.7.sroa.0.2239256) #65, !dbg !1104
  br i1 %_18.sroa.0.0.copyload, label %bb2.i.i23, label %bb2.i.i.i.i20

bb14:                                             ; preds = %_ZN6matrix11Permutation5child17hb1b866b0412a1726E.exit
  br i1 %_74.i.i.i37, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47", label %bb2.i.i.i38

bb2.i.i.i38:                                      ; preds = %bb14, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45"
  %_3.sroa.0.05.i.i.i39 = phi i64 [ %102, %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45" ], [ 0, %bb14 ]
  %_6.i.i.i40 = getelementptr inbounds nuw %"alloc::vec::Vec<usize>", ptr %_15.sroa.7.sroa.0.2239256, i64 %_3.sroa.0.05.i.i.i39
  %102 = add nuw i64 %_3.sroa.0.05.i.i.i39, 1
  %_6.val.i.i.i41 = load i64, ptr %_6.i.i.i40, align 8, !range !1117, !alias.scope !2363, !noalias !2366, !noundef !31
  %103 = icmp eq i64 %_6.val.i.i.i41, 0
  br i1 %103, label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45", label %bb2.i.i.i.i.i.i.i42

bb2.i.i.i.i.i.i.i42:                              ; preds = %bb2.i.i.i38
  %104 = getelementptr i8, ptr %_6.i.i.i40, i64 8
  %_6.val3.i.i.i43 = load ptr, ptr %104, align 8, !alias.scope !2363, !noalias !2366, !nonnull !31, !noundef !31
  tail call void @free(ptr noundef nonnull %_6.val3.i.i.i43) #65, !dbg !1104
  br label %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45"

"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45": ; preds = %bb2.i.i.i.i.i.i.i42, %bb2.i.i.i38
  %_7.i.i.i46 = icmp eq i64 %102, %_15.sroa.7.sroa.5.2241254
  br i1 %_7.i.i.i46, label %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47", label %bb2.i.i.i38

"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47": ; preds = %"_ZN4core3ptr49drop_in_place$LT$alloc..vec..Vec$LT$usize$GT$$GT$17h2e6ca82f322e8a21E.exit.i.i.i45", %bb14
  %105 = icmp eq i64 %_15.sroa.0.0243253, 0
  br i1 %105, label %bb27, label %bb2.i.i.i.i49

bb2.i.i.i.i49:                                    ; preds = %"_ZN70_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..drop..Drop$GT$4drop17h3927497b34055db7E.exit.i47"
  tail call void @free(ptr noundef nonnull %_15.sroa.7.sroa.0.2239256) #65, !dbg !1104
  br label %bb27

bb26:                                             ; preds = %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit", %start, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32"
  %_0.sroa.0.1 = phi i1 [ false, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit32" ], [ true, %start ], [ true, %"_ZN4core3ptr40drop_in_place$LT$matrix..Permutation$GT$17h9a700f3bb86af3afE.exit" ]
  ret i1 %_0.sroa.0.1
}
