define internal fastcc noundef zeroext i1 @_ZN9bv2string9roundtrip17h991279b9b7076855E(ptr dead_on_return noalias noundef nonnull readonly align 8 captures(none) dereferenceable(24) %bytes) unnamed_addr #2 personality ptr @rust_eh_personality {
start:
  %e.i1 = alloca [16 x i8], align 8
  %e.i = alloca [16 x i8], align 8
  %_9 = alloca [24 x i8], align 8
  %_4 = alloca [24 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %_4)
  %0 = getelementptr inbounds nuw i8, ptr %bytes, i64 8
  %_14 = load ptr, ptr %0, align 8, !nonnull !40, !noundef !40
  %1 = getelementptr inbounds nuw i8, ptr %bytes, i64 16
  %_13 = load i64, ptr %1, align 8, !noundef !40
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %_4, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %_14, i64 noundef %_13) #64
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1300)
  %_2.i2 = load i64, ptr %_4, align 8, !range !855, !alias.scope !1300, !noalias !1303, !noundef !40
  %2 = trunc nuw i64 %_2.i2 to i1
  br i1 %2, label %bb2.i5, label %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6", !prof !999

bb2.i5:                                           ; preds = %start
  call void @llvm.lifetime.start.p0(ptr nonnull %e.i1), !noalias !1305
  %3 = getelementptr inbounds nuw i8, ptr %_4, i64 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %e.i1, ptr noundef nonnull readonly align 8 dereferenceable(16) %3, i64 16, i1 false), !noalias !1303
; call core::result::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6result13unwrap_failed(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @anon.eb89d4395b0ead844ef0b45b8b54da85.154, i64 noundef 43, ptr noundef nonnull align 1 %e.i1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) @vtable.3, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_5eb977615060cf4843ed1b7d5b2da065) #107, !noalias !1300
  unreachable

"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6": ; preds = %start
  %4 = getelementptr inbounds nuw i8, ptr %_4, i64 8
  %t.0.i3 = load ptr, ptr %4, align 8, !alias.scope !1300, !noalias !1303, !nonnull !40, !align !66, !noundef !40
  %5 = getelementptr inbounds nuw i8, ptr %_4, i64 16
  %t.1.i4 = load i64, ptr %5, align 8, !alias.scope !1300, !noalias !1303, !noundef !40
  call void @llvm.lifetime.end.p0(ptr nonnull %_4)
  %_38.i = icmp sgt i64 %t.1.i4, -1
  br i1 %_38.i, label %bb18.i, label %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6.split"

"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6.split": ; preds = %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6"
; call alloc::raw_vec::capacity_overflow
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #104, !dbg !1143
  unreachable, !dbg !1143

bb18.i:                                           ; preds = %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit6"
  %6 = icmp eq i64 %t.1.i4, 0
  br i1 %6, label %bb16.thread, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit

bb16.thread:                                      ; preds = %bb18.i
  call void @llvm.lifetime.start.p0(ptr nonnull %_9)
  %7 = getelementptr inbounds nuw i8, ptr %_9, i64 8, !dbg !1306
  store ptr inttoptr (i64 1 to ptr), ptr %7, align 8, !dbg !1306, !alias.scope !1311, !noalias !1314
  %8 = getelementptr inbounds nuw i8, ptr %_9, i64 16, !dbg !1306
  store i64 0, ptr %8, align 8, !dbg !1306, !alias.scope !1311, !noalias !1314
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1316)
  br label %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit"

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit:  ; preds = %bb18.i
  %9 = tail call noundef ptr @malloc(i64 noundef range(i64 0, -9223372036854775808) %t.1.i4) #64, !dbg !1146, !noalias !1319
  %10 = icmp eq ptr %9, null
  br i1 %10, label %_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.split, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit90

_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i.split: ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 %t.1.i4) #105
  unreachable

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit90: ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %9, ptr nonnull align 1 %t.0.i3, i64 %t.1.i4, i1 false)
  %11 = tail call noundef ptr @malloc(i64 noundef range(i64 0, -9223372036854775808) %t.1.i4) #64, !dbg !1146, !noalias !1322
  %12 = icmp eq ptr %11, null
  br i1 %12, label %bb18, label %bb16

bb18:                                             ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit90
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 %t.1.i4) #105
  unreachable

bb16:                                             ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit90
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %11, ptr nonnull align 1 %t.0.i3, i64 %t.1.i4, i1 false)
  call void @llvm.lifetime.start.p0(ptr nonnull %_9)
; call core::str::converts::from_utf8
  call fastcc void @_RNvNtNtCsgEmfK2I1SDS_4core3str8converts9from_utf8(ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %_9, ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) %11, i64 noundef %t.1.i4) #64
  %_2.i.pre = load i64, ptr %_9, align 8, !range !855, !alias.scope !1325, !noalias !1327
  %13 = trunc nuw i64 %_2.i.pre to i1
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1325)
  br i1 %13, label %bb2.i, label %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit", !prof !1329

bb2.i:                                            ; preds = %bb16
  call void @llvm.lifetime.start.p0(ptr nonnull %e.i), !noalias !1330
  %14 = getelementptr inbounds nuw i8, ptr %_9, i64 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %e.i, ptr noundef nonnull readonly align 8 dereferenceable(16) %14, i64 16, i1 false), !noalias !1327
; call core::result::unwrap_failed
  call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6result13unwrap_failed(ptr noalias noundef nonnull readonly align 1 captures(address, read_provenance) @anon.eb89d4395b0ead844ef0b45b8b54da85.154, i64 noundef 43, ptr noundef nonnull align 1 %e.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) @vtable.3, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_8586b2d8bf87d4023a523f486625895a) #107, !noalias !1325
  unreachable

"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit": ; preds = %bb16.thread, %bb16
  %.ph7299 = phi ptr [ inttoptr (i64 1 to ptr), %bb16.thread ], [ %9, %bb16 ]
  %15 = phi ptr [ inttoptr (i64 1 to ptr), %bb16.thread ], [ %11, %bb16 ]
  %16 = getelementptr inbounds nuw i8, ptr %_9, i64 8
  %t.0.i = load ptr, ptr %16, align 8, !alias.scope !1325, !noalias !1327, !nonnull !40, !align !66, !noundef !40
  %17 = getelementptr inbounds nuw i8, ptr %_9, i64 16
  %t.1.i = load i64, ptr %17, align 8, !alias.scope !1325, !noalias !1327, !noundef !40
  call void @llvm.lifetime.end.p0(ptr nonnull %_9)
  %_38.i21 = icmp sgt i64 %t.1.i, -1
  br i1 %_38.i21, label %bb18.i24, label %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit.split"

"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit.split": ; preds = %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit"
; call alloc::raw_vec::capacity_overflow
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec17capacity_overflow() #104, !dbg !1143
  unreachable, !dbg !1143

bb18.i24:                                         ; preds = %"_ZN4core6result19Result$LT$T$C$E$GT$6unwrap17h3a16bf34e019861bE.exit"
  %18 = icmp eq i64 %t.1.i, 0
  br i1 %18, label %bb21, label %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit93

_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit93: ; preds = %bb18.i24
  %19 = tail call noundef ptr @malloc(i64 noundef range(i64 0, -9223372036854775808) %t.1.i) #64, !dbg !1146, !noalias !1331
  %20 = icmp eq ptr %19, null
  br i1 %20, label %_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i25.split, label %bb20

_RNvXs_NtCslNYArtu3iFV_5alloc5allocNtB4_6GlobalNtNtCsgEmfK2I1SDS_4core5alloc9Allocator8allocate.exit.i25.split: ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit93
; call alloc::raw_vec::handle_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc7raw_vec12handle_error(i64 noundef 1, i64 %t.1.i) #105
  unreachable

bb21:                                             ; preds = %bb18.i24, %bb20
  %21 = phi ptr [ %19, %bb20 ], [ inttoptr (i64 1 to ptr), %bb18.i24 ]
  %_83 = icmp eq i64 %t.1.i4, %t.1.i
  br i1 %_83, label %bb25, label %bb27

bb20:                                             ; preds = %_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc.exit93
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %19, ptr nonnull align 1 %t.0.i, i64 %t.1.i, i1 false)
  br label %bb21

bb25:                                             ; preds = %bb21
  %bcmp = tail call i32 @bcmp(ptr nonnull %.ph7299, ptr nonnull %21, i64 %t.1.i4)
  %22 = icmp eq i32 %bcmp, 0
  br label %bb27

bb27:                                             ; preds = %bb21, %bb25
  %_0.sroa.0.0 = phi i1 [ %22, %bb25 ], [ false, %bb21 ]
  br i1 %18, label %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit", label %bb2.i.i.i.i.i

bb2.i.i.i.i.i:                                    ; preds = %bb27
  tail call void @free(ptr noundef nonnull %21) #64, !dbg !615
  br label %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit"

"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit": ; preds = %bb27, %bb2.i.i.i.i.i
  br i1 %6, label %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit31", label %bb2.i.i.i.i

bb2.i.i.i.i:                                      ; preds = %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit"
  tail call void @free(ptr noundef nonnull %15) #64, !dbg !615
  tail call void @free(ptr noundef nonnull %.ph7299) #64, !dbg !615
  br label %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit31"

"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit31": ; preds = %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit", %bb2.i.i.i.i
  %bytes.val = load i64, ptr %bytes, align 8, !range !628, !noundef !40
  %23 = icmp eq i64 %bytes.val, 0
  br i1 %23, label %"_ZN4core3ptr46drop_in_place$LT$alloc..vec..Vec$LT$u8$GT$$GT$17h03a0ac7f144aad2eE.exit33", label %bb2.i.i.i.i32

bb2.i.i.i.i32:                                    ; preds = %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit31"
  tail call void @free(ptr noundef nonnull %_14) #64, !dbg !615
  br label %"_ZN4core3ptr46drop_in_place$LT$alloc..vec..Vec$LT$u8$GT$$GT$17h03a0ac7f144aad2eE.exit33"

"_ZN4core3ptr46drop_in_place$LT$alloc..vec..Vec$LT$u8$GT$$GT$17h03a0ac7f144aad2eE.exit33": ; preds = %"_ZN4core3ptr42drop_in_place$LT$alloc..string..String$GT$17hba00e27a67800c0bE.exit31", %bb2.i.i.i.i32
  ret i1 %_0.sroa.0.0
}
