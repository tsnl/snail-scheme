define internal fastcc void @_ZN6matrix13collect_tests17h1cc028c08694081aE(ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(8) %new, ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(8) %universe, i64 noundef %needed, i64 noundef %remaining, ptr noalias noundef nonnull align 8 captures(none) dereferenceable(24) %prefix, ptr noalias noundef nonnull align 8 captures(none) dereferenceable(32) %tests) unnamed_addr #1 personality ptr @rust_eh_personality {
start:
  %_24 = alloca [16 x i8], align 8
  %_819 = icmp ult i64 %remaining, %needed
  br i1 %_819, label %bb13, label %bb2.lr.ph

bb2.lr.ph:                                        ; preds = %start
  %0 = icmp eq i64 %needed, 0
  %1 = getelementptr inbounds nuw i8, ptr %prefix, i64 16
  %2 = getelementptr inbounds nuw i8, ptr %prefix, i64 8
  %_22 = add i64 %needed, -1
  %3 = getelementptr inbounds nuw i8, ptr %_24, i64 8
  br i1 %0, label %bb5, label %bb2

bb2:                                              ; preds = %bb2.lr.ph, %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit"
  %remaining.tr21 = phi i64 [ %_23, %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit" ], [ %remaining, %bb2.lr.ph ]
  %universe.tr20 = phi ptr [ %_21, %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit" ], [ %universe, %bb2.lr.ph ]
  %_9 = icmp eq i64 %remaining.tr21, %needed
  br i1 %_9, label %bb6, label %bb4

bb5:                                              ; preds = %bb2.lr.ph
  %_9.us = icmp eq i64 %remaining, 0
  br i1 %_9.us, label %bb6, label %bb8

bb4:                                              ; preds = %bb2
  %4 = load ptr, ptr %universe.tr20, align 8, !noundef !31
  %.not = icmp eq ptr %4, null
  br i1 %.not, label %bb15, label %bb16, !prof !1319

bb16:                                             ; preds = %bb4
  %5 = getelementptr inbounds nuw i8, ptr %4, i64 16
  %6 = load ptr, ptr %5, align 8, !noundef !31
  %.not1 = icmp eq ptr %6, null
  br i1 %.not1, label %bb31, label %bb33

bb15:                                             ; preds = %bb4
; call core::option::unwrap_failed
  tail call fastcc void @_RNvNtCsgEmfK2I1SDS_4core6option13unwrap_failed(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_47449b82affda1cf2c23e873225ae348) #104
  unreachable

bb33:                                             ; preds = %bb16
  %_76 = load i64, ptr %6, align 8, !noundef !31
  %_77 = icmp ne i64 %_76, 0
  tail call void @llvm.assume(i1 %_77)
  %_78 = add i64 %_76, 1
  store i64 %_78, ptr %6, align 8
  %7 = icmp eq i64 %_78, 0
  br i1 %7, label %bb34, label %bb36, !prof !1319

bb31:                                             ; preds = %bb16, %bb36
  %_19.sroa.0.0 = phi ptr [ %_73, %bb36 ], [ null, %bb16 ]
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1421)
  %len.i = load i64, ptr %1, align 8, !alias.scope !1421, !noundef !31
  %self1.i = load i64, ptr %prefix, align 8, !range !1117, !alias.scope !1421, !noundef !31
  %_4.i = icmp eq i64 %len.i, %self1.i
  br i1 %_4.i, label %bb1.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h34885bed54f134d5E.exit"

bb1.i:                                            ; preds = %bb31
; call alloc::raw_vec::RawVec<T,A>::grow_one
  tail call fastcc void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1a8a596198001465E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %prefix) #103
  br label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h34885bed54f134d5E.exit"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h34885bed54f134d5E.exit": ; preds = %bb31, %bb1.i
  %_14.i = load ptr, ptr %2, align 8, !alias.scope !1421, !nonnull !31, !noundef !31
  %end.i = getelementptr inbounds nuw ptr, ptr %_14.i, i64 %len.i
  store ptr %_19.sroa.0.0, ptr %end.i, align 8, !noalias !1421
  %8 = add i64 %len.i, 1
  store i64 %8, ptr %1, align 8, !alias.scope !1421
  %_21 = getelementptr inbounds nuw i8, ptr %4, i64 24
  %_23 = add i64 %remaining.tr21, -1
; call matrix::collect_tests
  tail call fastcc void @_ZN6matrix13collect_tests17h1cc028c08694081aE(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %new, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(8) %_21, i64 noundef %_22, i64 noundef %_23, ptr noalias noundef align 8 dereferenceable(24) %prefix, ptr noalias noundef align 8 dereferenceable(32) %tests) #65
  call void @llvm.lifetime.start.p0(ptr nonnull %_24)
  %_86 = load i64, ptr %1, align 8, !noundef !31
  %9 = icmp eq i64 %_86, 0
  br i1 %9, label %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit", label %bb2.i

bb34:                                             ; preds = %bb33
  tail call void @llvm.trap()
  unreachable

bb36:                                             ; preds = %bb33
  %_73 = load ptr, ptr %5, align 8, !nonnull !31, !noundef !31
  br label %bb31

bb2.i:                                            ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h34885bed54f134d5E.exit"
  %10 = add nsw i64 %_86, -1
  store i64 %10, ptr %1, align 8
  %_94 = load i64, ptr %prefix, align 8, !range !1117, !noundef !31
  %_87 = icmp samesign ult i64 %10, %_94
  tail call void @llvm.assume(i1 %_87)
  %_95 = load ptr, ptr %2, align 8, !nonnull !31, !noundef !31
  %_96 = icmp ult i64 %_86, 1152921504606846977
  tail call void @llvm.assume(i1 %_96)
  %_91 = getelementptr inbounds nuw ptr, ptr %_95, i64 %10
  %_90 = load ptr, ptr %_91, align 8, !noundef !31
  store ptr %_90, ptr %3, align 8
  store i64 1, ptr %_24, align 8
  %11 = icmp eq ptr %_90, null
  br i1 %11, label %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit", label %bb2.i.i

bb2.i.i:                                          ; preds = %bb2.i
  %_8.i.i.i = load i64, ptr %_90, align 8, !noalias !1424, !noundef !31
  %val.i.i.i = add i64 %_8.i.i.i, -1
  store i64 %val.i.i.i, ptr %_90, align 8, !noalias !1424
  %12 = icmp eq i64 %val.i.i.i, 0
  br i1 %12, label %bb1.i.i.i, label %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit"

bb1.i.i.i:                                        ; preds = %bb2.i.i
; call alloc::rc::Rc<T,A>::drop_slow
  call fastcc void @"_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0947af3e06b231f7E"(ptr noalias noundef nonnull readonly align 8 dereferenceable(8) %3) #103
  br label %"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit"

"_ZN4core3ptr112drop_in_place$LT$core..option..Option$LT$core..option..Option$LT$alloc..rc..Rc$LT$matrix..Number$GT$$GT$$GT$$GT$17ha576d46562ec9f4aE.exit": ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h34885bed54f134d5E.exit", %bb2.i, %bb2.i.i, %bb1.i.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_24)
  br label %bb2

bb13:                                             ; preds = %start, %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17h4a84ee01a3bcfe70E.exit"
  ret void

bb6:                                              ; preds = %bb2, %bb5
  %.us-phi2234 = phi ptr [ %universe, %bb5 ], [ %universe.tr20, %bb2 ]
  %13 = load ptr, ptr %.us-phi2234, align 8, !noundef !31
  %.not2 = icmp eq ptr %13, null
  br i1 %.not2, label %bb8, label %bb19

bb8:                                              ; preds = %bb19, %bb6, %bb5
  %suffix.sroa.0.0 = phi ptr [ null, %bb6 ], [ null, %bb5 ], [ %13, %bb19 ]
  %_45 = load ptr, ptr %2, align 8, !nonnull !31, !noundef !31
  %_44 = load i64, ptr %1, align 8, !noundef !31
  %14 = icmp eq i64 %_44, 0
  br i1 %14, label %_ZN4core4iter6traits12double_ended19DoubleEndedIterator5rfold17h4f720bd1da6c2c36E.exit, label %bb3.i.preheader

bb3.i.preheader:                                  ; preds = %bb8
  %_49.idx = shl nuw nsw i64 %_44, 3
  %_49 = getelementptr inbounds nuw i8, ptr %_45, i64 %_49.idx
  br label %bb3.i

bb3.i:                                            ; preds = %bb3.i.preheader, %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i"
  %accum.sroa.0.09.i = phi ptr [ %16, %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i" ], [ %suffix.sroa.0.0, %bb3.i.preheader ]
  %self.sroa.2.08.i = phi ptr [ %_23.i.i, %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i" ], [ %_49, %bb3.i.preheader ]
  %_23.i.i = getelementptr inbounds i8, ptr %self.sroa.2.08.i, i64 -8
  %.val.i = load ptr, ptr %_23.i.i, align 8, !noundef !31
  %.not.i.i = icmp eq ptr %.val.i, null
  br i1 %.not.i.i, label %bb2.i.i5, label %bb5.i1.i

bb5.i1.i:                                         ; preds = %bb3.i
  %_9.i.i = load i64, ptr %.val.i, align 8, !noundef !31
  %_10.i.i = icmp ne i64 %_9.i.i, 0
  tail call void @llvm.assume(i1 %_10.i.i)
  %_11.i2.i = add i64 %_9.i.i, 1
  store i64 %_11.i2.i, ptr %.val.i, align 8
  %15 = icmp eq i64 %_11.i2.i, 0
  br i1 %15, label %bb6.i.i, label %bb2.i.i5, !prof !1319

bb2.i.i5:                                         ; preds = %bb5.i1.i, %bb3.i
  %16 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1431
  %17 = icmp eq ptr %16, null
  br i1 %17, label %bb2.i.i.i.i, label %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i", !prof !1319

bb2.i.i.i.i:                                      ; preds = %bb2.i.i5
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1431
  unreachable

bb6.i.i:                                          ; preds = %bb5.i1.i
  tail call void @llvm.trap()
  unreachable

"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i": ; preds = %bb2.i.i5
  store i64 1, ptr %16, align 8
  %_7.sroa.4.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %16, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i.i.i, align 8
  %_7.sroa.5.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %16, i64 16
  store ptr %.val.i, ptr %_7.sroa.5.0..sroa_idx.i.i.i, align 8
  %_7.sroa.6.0..sroa_idx.i.i.i = getelementptr inbounds nuw i8, ptr %16, i64 24
  store ptr %accum.sroa.0.09.i, ptr %_7.sroa.6.0..sroa_idx.i.i.i, align 8
  %18 = icmp eq ptr %_45, %_23.i.i
  br i1 %18, label %_ZN4core4iter6traits12double_ended19DoubleEndedIterator5rfold17h4f720bd1da6c2c36E.exit, label %bb3.i

_ZN4core4iter6traits12double_ended19DoubleEndedIterator5rfold17h4f720bd1da6c2c36E.exit: ; preds = %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i", %bb8
  %accum.sroa.0.0.lcssa.i = phi ptr [ %suffix.sroa.0.0, %bb8 ], [ %16, %"_ZN6matrix13collect_tests28_$u7b$$u7b$closure$u7d$$u7d$17h985ddfe21e92b9e3E.exit.i" ]
  %19 = load ptr, ptr %new, align 8, !noundef !31
  %.not3 = icmp eq ptr %19, null
  br i1 %.not3, label %bb24, label %bb26

bb19:                                             ; preds = %bb6
  %_33 = load i64, ptr %13, align 8, !noundef !31
  %_34 = icmp ne i64 %_33, 0
  tail call void @llvm.assume(i1 %_34)
  %_35 = add i64 %_33, 1
  store i64 %_35, ptr %13, align 8
  %20 = icmp eq i64 %_35, 0
  br i1 %20, label %bb20, label %bb8, !prof !1319

bb20:                                             ; preds = %bb19
  tail call void @llvm.trap()
  unreachable

bb26:                                             ; preds = %_ZN4core4iter6traits12double_ended19DoubleEndedIterator5rfold17h4f720bd1da6c2c36E.exit
  %_58 = load i64, ptr %19, align 8, !noundef !31
  %_59 = icmp ne i64 %_58, 0
  tail call void @llvm.assume(i1 %_59)
  %_60 = add i64 %_58, 1
  store i64 %_60, ptr %19, align 8
  %21 = icmp eq i64 %_60, 0
  br i1 %21, label %bb27, label %bb24, !prof !1319

bb24:                                             ; preds = %bb26, %_ZN4core4iter6traits12double_ended19DoubleEndedIterator5rfold17h4f720bd1da6c2c36E.exit
  %22 = tail call noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #65, !dbg !1250, !noalias !1434
  %23 = icmp eq ptr %22, null
  br i1 %23, label %bb2.i.i6, label %_ZN6matrix6matrix17he37191504af5b7c1E.exit, !prof !1319

bb2.i.i6:                                         ; preds = %bb24
; call alloc::alloc::handle_alloc_error
  tail call fastcc void @_RNvNtCslNYArtu3iFV_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 32) #105, !noalias !1434
  unreachable

_ZN6matrix6matrix17he37191504af5b7c1E.exit:       ; preds = %bb24
  store i64 1, ptr %22, align 8
  %_7.sroa.4.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %22, i64 8
  store i64 1, ptr %_7.sroa.4.0..sroa_idx.i, align 8
  %_7.sroa.5.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %22, i64 16
  store ptr %19, ptr %_7.sroa.5.0..sroa_idx.i, align 8
  %_7.sroa.6.0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %22, i64 24
  store ptr %accum.sroa.0.0.lcssa.i, ptr %_7.sroa.6.0..sroa_idx.i, align 8
; call matrix::row_reduce
  %_14 = tail call fastcc noundef ptr @_ZN6matrix10row_reduce17h00edd7e88ae65d79E(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(32) %field, ptr noundef nonnull %22) #65
  tail call void @llvm.experimental.noalias.scope.decl(metadata !1437)
  %24 = getelementptr inbounds nuw i8, ptr %tests, i64 24
  %_9.i = load i64, ptr %24, align 8, !alias.scope !1437, !noundef !31
  %self1.i7 = load i64, ptr %tests, align 8, !range !1117, !alias.scope !1437, !noundef !31
  %_3.i = icmp eq i64 %_9.i, %self1.i7
  br i1 %_3.i, label %bb1.i9, label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17h4a84ee01a3bcfe70E.exit"

bb1.i9:                                           ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit
; call alloc::collections::vec_deque::VecDeque<T,A>::grow
  tail call fastcc void @"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4grow17hc695f7f11bdd3346E"(ptr noalias noundef nonnull align 8 dereferenceable(32) %tests) #103
  %self3.pre.i = load i64, ptr %tests, align 8, !range !1117, !alias.scope !1437
  %.pre.i = load i64, ptr %24, align 8, !alias.scope !1437
  br label %"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17h4a84ee01a3bcfe70E.exit"

"_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$14push_front_mut17h4a84ee01a3bcfe70E.exit": ; preds = %_ZN6matrix6matrix17he37191504af5b7c1E.exit, %bb1.i9
  %25 = phi i64 [ %.pre.i, %bb1.i9 ], [ %_9.i, %_ZN6matrix6matrix17he37191504af5b7c1E.exit ]
  %self3.i = phi i64 [ %self3.pre.i, %bb1.i9 ], [ %self1.i7, %_ZN6matrix6matrix17he37191504af5b7c1E.exit ]
  %26 = getelementptr inbounds nuw i8, ptr %tests, i64 16
  %idx.i = load i64, ptr %26, align 8, !alias.scope !1437, !noundef !31
  %self2.i = add i64 %idx.i, -1
  %logical_index.i = add i64 %self2.i, %self3.i
  %_24.not.i = icmp ult i64 %logical_index.i, %self3.i
  %logical_index.self2.i = select i1 %_24.not.i, i64 %logical_index.i, i64 %self2.i
  store i64 %logical_index.self2.i, ptr %26, align 8, !alias.scope !1437
  %27 = add i64 %25, 1
  store i64 %27, ptr %24, align 8, !alias.scope !1437
  %28 = getelementptr inbounds nuw i8, ptr %tests, i64 8
  %_27.i = load ptr, ptr %28, align 8, !alias.scope !1437, !nonnull !31, !noundef !31
  %_25.i = getelementptr inbounds nuw ptr, ptr %_27.i, i64 %logical_index.self2.i
  store ptr %_14, ptr %_25.i, align 8, !noalias !1437
  br label %bb13

bb27:                                             ; preds = %bb26
  tail call void @llvm.trap()
  unreachable
}
