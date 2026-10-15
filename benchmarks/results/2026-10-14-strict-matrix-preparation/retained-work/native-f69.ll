define internal tailcc i64 @f.69(i64 %arg0, i64 %arg1) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot13 = alloca i64, align 8
  %slot94 = alloca i64, align 8
  %slot323 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [20 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 20)
  store i64 %arg0, ptr %slot1, align 1
  store i64 %arg1, ptr %slot2, align 1
  store i64 0, ptr %slot3, align 1
  %v4 = getelementptr i64, ptr %roots, i64 3
  store i64 0, ptr %v4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v5, align 1
  %v6 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v6, align 1
  %v7 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v7, align 1
  %v8 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v8, align 1
  %v9 = getelementptr i64, ptr %roots, i64 8
  store i64 0, ptr %v9, align 1
  %v10 = getelementptr i64, ptr %roots, i64 9
  store i64 0, ptr %v10, align 1
  %v11 = getelementptr i64, ptr %roots, i64 10
  store i64 0, ptr %v11, align 1
  %v12 = getelementptr i64, ptr %roots, i64 11
  store i64 0, ptr %v12, align 1
  %v15 = load i32, ptr @g.136, align 1
  %v16 = icmp eq i32 %v15, 0
  %v17 = zext i1 %v16 to i32
  %v21 = icmp ne i32 %v17, 0
  br i1 %v21, label %then20, label %else19
then20:
  call void @native_trap()
  unreachable
else19:
  br label %block18
block18:
  %v22 = load i64, ptr @g.135, align 1
  %v23 = icmp ne i64 %v22, 0
  br i1 %v23, label %ok25, label %trap24
trap24:
  call void @native_trap()
  unreachable
ok25:
  store i64 %v22, ptr %v4, align 1
  %v26 = load i32, ptr @g.134, align 1
  %v27 = icmp eq i32 %v26, 0
  %v28 = zext i1 %v27 to i32
  %v32 = icmp ne i32 %v28, 0
  br i1 %v32, label %then31, label %else30
then31:
  call void @native_trap()
  unreachable
else30:
  br label %block29
block29:
  %v33 = load i64, ptr @g.133, align 1
  %v34 = icmp ne i64 %v33, 0
  br i1 %v34, label %ok36, label %trap35
trap35:
  call void @native_trap()
  unreachable
ok36:
  %v37 = load i32, ptr @g.132, align 1
  %v38 = icmp eq i32 %v37, 0
  %v39 = zext i1 %v38 to i32
  %v43 = icmp ne i32 %v39, 0
  br i1 %v43, label %then42, label %else41
then42:
  call void @native_trap()
  unreachable
else41:
  br label %block40
block40:
  %v44 = load i64, ptr @g.131, align 1
  %v45 = icmp ne i64 %v44, 0
  br i1 %v45, label %ok47, label %trap46
trap46:
  call void @native_trap()
  unreachable
ok47:
  %v48 = inttoptr i64 %v44 to ptr
  %v49 = getelementptr i64, ptr %v48, i64 2
  %v50 = load i64, ptr %v49, align 1
  %v51 = load i64, ptr %slot2, align 1
  %v52 = getelementptr i64, ptr %roots, i64 12
  store i64 %v50, ptr %v52, align 1
  %v53 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v53, align 1
  %v54 = call tailcc i64 @f.64(i64 %v50, i64 %v51)
  store i64 %v54, ptr %slot3, align 1
  %v55 = load i32, ptr @g.130, align 1
  %v56 = icmp eq i32 %v55, 0
  %v57 = zext i1 %v56 to i32
  %v61 = icmp ne i32 %v57, 0
  br i1 %v61, label %then60, label %else59
then60:
  call void @native_trap()
  unreachable
else59:
  br label %block58
block58:
  %v62 = load i64, ptr @g.129, align 1
  %v63 = icmp ne i64 %v62, 0
  br i1 %v63, label %ok65, label %trap64
trap64:
  call void @native_trap()
  unreachable
ok65:
  %v66 = inttoptr i64 %v62 to ptr
  %v67 = getelementptr i64, ptr %v66, i64 2
  %v68 = load i64, ptr %v67, align 1
  %v69 = load i32, ptr @g.45, align 1
  %v70 = icmp eq i32 %v69, 0
  %v71 = zext i1 %v70 to i32
  %v75 = icmp ne i32 %v71, 0
  br i1 %v75, label %then74, label %else73
then74:
  call void @native_trap()
  unreachable
else73:
  br label %block72
block72:
  %v76 = load i64, ptr @g.44, align 1
  %v77 = icmp ne i64 %v76, 0
  br i1 %v77, label %ok79, label %trap78
trap78:
  call void @native_trap()
  unreachable
ok79:
  %v80 = load i32, ptr @g.66, align 1
  %v81 = icmp eq i32 %v80, 0
  %v82 = zext i1 %v81 to i32
  %v86 = icmp ne i32 %v82, 0
  br i1 %v86, label %then85, label %else84
then85:
  call void @native_trap()
  unreachable
else84:
  br label %block83
block83:
  %v87 = load i64, ptr @g.65, align 1
  %v88 = icmp ne i64 %v87, 0
  br i1 %v88, label %ok90, label %trap89
trap89:
  call void @native_trap()
  unreachable
ok90:
  %v91 = load i64, ptr %slot3, align 1
  %v92 = icmp slt i64 %v91, 2
  %v93 = zext i1 %v92 to i32
  %v98 = icmp ne i32 %v93, 0
  br i1 %v98, label %then97, label %else96
then97:
  store i64 2, ptr %slot94, align 1
  br label %block95
else96:
  %v99 = load i64, ptr %slot3, align 1
  %v100 = load i64, ptr @g.50, align 1
  %v101 = getelementptr i64, ptr %roots, i64 12
  store i64 %v100, ptr %v101, align 1
  %v102 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v102, align 1
  %v103 = call i64 @native_alloc(i64 16)
  %v104 = icmp ne i64 %v103, 0
  br i1 %v104, label %ok106, label %trap105
trap105:
  call void @native_trap()
  unreachable
ok106:
  %v107 = inttoptr i64 %v103 to ptr
  %v108 = getelementptr i64, ptr %v107, i64 0
  store i64 154, ptr %v108, align 1
  %v109 = icmp ne i64 %v103, 0
  br i1 %v109, label %ok111, label %trap110
trap110:
  call void @native_trap()
  unreachable
ok111:
  %v112 = inttoptr i64 %v103 to ptr
  %v113 = getelementptr i64, ptr %v112, i64 1
  store i64 %v100, ptr %v113, align 1
  %v114 = getelementptr i64, ptr %roots, i64 12
  store i64 %v103, ptr %v114, align 1
  %v115 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v115, align 1
  %v116 = call i64 @native_alloc(i64 24)
  %v117 = icmp ne i64 %v116, 0
  br i1 %v117, label %ok119, label %trap118
trap118:
  call void @native_trap()
  unreachable
ok119:
  %v120 = inttoptr i64 %v116 to ptr
  %v121 = getelementptr i64, ptr %v120, i64 0
  store i64 158, ptr %v121, align 1
  %v122 = icmp ne i64 %v116, 0
  br i1 %v122, label %ok124, label %trap123
trap123:
  call void @native_trap()
  unreachable
ok124:
  %v125 = inttoptr i64 %v116 to ptr
  %v126 = getelementptr i64, ptr %v125, i64 1
  store i64 2, ptr %v126, align 1
  %v127 = icmp ne i64 %v116, 0
  br i1 %v127, label %ok129, label %trap128
trap128:
  call void @native_trap()
  unreachable
ok129:
  %v130 = inttoptr i64 %v116 to ptr
  %v131 = getelementptr i64, ptr %v130, i64 2
  store i64 %v103, ptr %v131, align 1
  store i64 %v116, ptr %v5, align 1
  %v132 = load i64, ptr %v5, align 1
  %v133 = getelementptr i64, ptr %roots, i64 12
  store i64 %v132, ptr %v133, align 1
  %v134 = getelementptr i64, ptr %roots, i64 13
  store i64 %v116, ptr %v134, align 1
  %v135 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v135, align 1
  %v136 = call i64 @native_alloc(i64 16)
  %v137 = icmp ne i64 %v136, 0
  br i1 %v137, label %ok139, label %trap138
trap138:
  call void @native_trap()
  unreachable
ok139:
  %v140 = inttoptr i64 %v136 to ptr
  %v141 = getelementptr i64, ptr %v140, i64 0
  store i64 154, ptr %v141, align 1
  %v142 = icmp ne i64 %v136, 0
  br i1 %v142, label %ok144, label %trap143
trap143:
  call void @native_trap()
  unreachable
ok144:
  %v145 = inttoptr i64 %v136 to ptr
  %v146 = getelementptr i64, ptr %v145, i64 1
  store i64 %v132, ptr %v146, align 1
  %v147 = getelementptr i64, ptr %roots, i64 12
  store i64 %v116, ptr %v147, align 1
  %v148 = getelementptr i64, ptr %roots, i64 13
  store i64 %v136, ptr %v148, align 1
  %v149 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v149, align 1
  %v150 = call tailcc i64 @f.63(i64 %v99, i64 %v116, i64 %v136, i32 0, i32 0, i32 1, i64 3)
  store i64 %v150, ptr %slot94, align 1
  br label %block95
block95:
  %v151 = load i64, ptr %slot94, align 1
  store i64 %v151, ptr %slot3, align 1
  %v152 = load i32, ptr @g.128, align 1
  %v153 = icmp eq i32 %v152, 0
  %v154 = zext i1 %v153 to i32
  %v158 = icmp ne i32 %v154, 0
  br i1 %v158, label %then157, label %else156
then157:
  call void @native_trap()
  unreachable
else156:
  br label %block155
block155:
  %v159 = load i64, ptr @g.127, align 1
  %v160 = icmp ne i64 %v159, 0
  br i1 %v160, label %ok162, label %trap161
trap161:
  call void @native_trap()
  unreachable
ok162:
  %v163 = load i32, ptr @g.126, align 1
  %v164 = icmp eq i32 %v163, 0
  %v165 = zext i1 %v164 to i32
  %v169 = icmp ne i32 %v165, 0
  br i1 %v169, label %then168, label %else167
then168:
  call void @native_trap()
  unreachable
else167:
  br label %block166
block166:
  %v170 = load i64, ptr @g.125, align 1
  %v171 = icmp ne i64 %v170, 0
  br i1 %v171, label %ok173, label %trap172
trap172:
  call void @native_trap()
  unreachable
ok173:
  %v174 = load i32, ptr @g.120, align 1
  %v175 = icmp eq i32 %v174, 0
  %v176 = zext i1 %v175 to i32
  %v180 = icmp ne i32 %v176, 0
  br i1 %v180, label %then179, label %else178
then179:
  call void @native_trap()
  unreachable
else178:
  br label %block177
block177:
  %v181 = load i64, ptr @g.119, align 1
  %v182 = icmp ne i64 %v181, 0
  br i1 %v182, label %ok184, label %trap183
trap183:
  call void @native_trap()
  unreachable
ok184:
  %v185 = load i32, ptr @g.118, align 1
  %v186 = icmp eq i32 %v185, 0
  %v187 = zext i1 %v186 to i32
  %v191 = icmp ne i32 %v187, 0
  br i1 %v191, label %then190, label %else189
then190:
  call void @native_trap()
  unreachable
else189:
  br label %block188
block188:
  %v192 = load i64, ptr @g.117, align 1
  %v193 = icmp ne i64 %v192, 0
  br i1 %v193, label %ok195, label %trap194
trap194:
  call void @native_trap()
  unreachable
ok195:
  %v196 = load i64, ptr %slot3, align 1
  %v197 = load i64, ptr %slot3, align 1
  %v198 = sub i64 %v197, 1
  %v199 = load i64, ptr %slot3, align 1
  %v200 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.59 to i64), ptr %v200, align 1
  %v201 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v201, align 1
  %v202 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v202, align 1
  %v203 = call i64 @native_alloc(i64 16)
  %v204 = icmp ne i64 %v203, 0
  br i1 %v204, label %ok206, label %trap205
trap205:
  call void @native_trap()
  unreachable
ok206:
  %v207 = inttoptr i64 %v203 to ptr
  %v208 = getelementptr i64, ptr %v207, i64 0
  store i64 174, ptr %v208, align 1
  %v209 = icmp ne i64 %v203, 0
  br i1 %v209, label %ok211, label %trap210
trap210:
  call void @native_trap()
  unreachable
ok211:
  %v212 = inttoptr i64 %v203 to ptr
  %v213 = getelementptr i64, ptr %v212, i64 1
  store i64 %v199, ptr %v213, align 1
  %v214 = getelementptr i64, ptr %roots, i64 12
  store i64 %v203, ptr %v214, align 1
  %v215 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.59 to i64), ptr %v215, align 1
  %v216 = getelementptr i64, ptr %roots, i64 14
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v216, align 1
  %v217 = getelementptr i64, ptr %roots, i64 2
  store i64 12, ptr %v217, align 1
  %v218 = call i64 @native_alloc(i64 24)
  %v219 = icmp ne i64 %v218, 0
  br i1 %v219, label %ok221, label %trap220
trap220:
  call void @native_trap()
  unreachable
ok221:
  %v222 = inttoptr i64 %v218 to ptr
  %v223 = getelementptr i64, ptr %v222, i64 0
  store i64 638, ptr %v223, align 1
  %v224 = icmp ne i64 %v218, 0
  br i1 %v224, label %ok226, label %trap225
trap225:
  call void @native_trap()
  unreachable
ok226:
  %v227 = inttoptr i64 %v218 to ptr
  %v228 = getelementptr i64, ptr %v227, i64 1
  store i64 ptrtoint (ptr @ref.59 to i64), ptr %v228, align 1
  %v229 = icmp ne i64 %v218, 0
  br i1 %v229, label %ok231, label %trap230
trap230:
  call void @native_trap()
  unreachable
ok231:
  %v232 = inttoptr i64 %v218 to ptr
  %v233 = getelementptr i64, ptr %v232, i64 2
  store i64 %v203, ptr %v233, align 1
  %v234 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v234, align 1
  %v235 = getelementptr i64, ptr %roots, i64 13
  store i64 %v218, ptr %v235, align 1
  %v236 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v236, align 1
  %v237 = call tailcc i64 @f.38(i64 %v198, i64 %v218)
  %v238 = getelementptr i64, ptr %roots, i64 12
  store i64 %v237, ptr %v238, align 1
  %v239 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v239, align 1
  %v240 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v240, align 1
  %v241 = call i64 @native_alloc(i64 24)
  %v242 = icmp ne i64 %v241, 0
  br i1 %v242, label %ok244, label %trap243
trap243:
  call void @native_trap()
  unreachable
ok244:
  %v245 = inttoptr i64 %v241 to ptr
  %v246 = getelementptr i64, ptr %v245, i64 0
  store i64 162, ptr %v246, align 1
  %v247 = icmp ne i64 %v241, 0
  br i1 %v247, label %ok249, label %trap248
trap248:
  call void @native_trap()
  unreachable
ok249:
  %v250 = inttoptr i64 %v241 to ptr
  %v251 = getelementptr i64, ptr %v250, i64 1
  store i64 %v196, ptr %v251, align 1
  %v252 = icmp ne i64 %v241, 0
  br i1 %v252, label %ok254, label %trap253
trap253:
  call void @native_trap()
  unreachable
ok254:
  %v255 = inttoptr i64 %v241 to ptr
  %v256 = getelementptr i64, ptr %v255, i64 2
  store i64 %v237, ptr %v256, align 1
  %v257 = getelementptr i64, ptr %roots, i64 12
  store i64 %v241, ptr %v257, align 1
  %v258 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v258, align 1
  %v259 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v259, align 1
  %v260 = call i64 @native_alloc(i64 24)
  %v261 = icmp ne i64 %v260, 0
  br i1 %v261, label %ok263, label %trap262
trap262:
  call void @native_trap()
  unreachable
ok263:
  %v264 = inttoptr i64 %v260 to ptr
  %v265 = getelementptr i64, ptr %v264, i64 0
  store i64 638, ptr %v265, align 1
  %v266 = icmp ne i64 %v260, 0
  br i1 %v266, label %ok268, label %trap267
trap267:
  call void @native_trap()
  unreachable
ok268:
  %v269 = inttoptr i64 %v260 to ptr
  %v270 = getelementptr i64, ptr %v269, i64 1
  store i64 ptrtoint (ptr @ref.60 to i64), ptr %v270, align 1
  %v271 = icmp ne i64 %v260, 0
  br i1 %v271, label %ok273, label %trap272
trap272:
  call void @native_trap()
  unreachable
ok273:
  %v274 = inttoptr i64 %v260 to ptr
  %v275 = getelementptr i64, ptr %v274, i64 2
  store i64 %v241, ptr %v275, align 1
  store i64 %v260, ptr %v6, align 1
  %v276 = load i32, ptr @g.124, align 1
  %v277 = icmp eq i32 %v276, 0
  %v278 = zext i1 %v277 to i32
  %v282 = icmp ne i32 %v278, 0
  br i1 %v282, label %then281, label %else280
then281:
  call void @native_trap()
  unreachable
else280:
  br label %block279
block279:
  %v283 = load i64, ptr @g.123, align 1
  %v284 = icmp ne i64 %v283, 0
  br i1 %v284, label %ok286, label %trap285
trap285:
  call void @native_trap()
  unreachable
ok286:
  %v287 = load i32, ptr @g.49, align 1
  %v288 = icmp eq i32 %v287, 0
  %v289 = zext i1 %v288 to i32
  %v293 = icmp ne i32 %v289, 0
  br i1 %v293, label %then292, label %else291
then292:
  call void @native_trap()
  unreachable
else291:
  br label %block290
block290:
  %v294 = load i64, ptr @g.48, align 1
  %v295 = icmp ne i64 %v294, 0
  br i1 %v295, label %ok297, label %trap296
trap296:
  call void @native_trap()
  unreachable
ok297:
  %v298 = load i64, ptr %slot1, align 1
  %v299 = sub i64 %v298, 1
  %v300 = getelementptr i64, ptr %roots, i64 12
  store i64 0, ptr %v300, align 1
  %v301 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.90 to i64), ptr %v301, align 1
  %v302 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v302, align 1
  %v303 = call i64 @native_alloc(i64 24)
  %v304 = icmp ne i64 %v303, 0
  br i1 %v304, label %ok306, label %trap305
trap305:
  call void @native_trap()
  unreachable
ok306:
  %v307 = inttoptr i64 %v303 to ptr
  %v308 = getelementptr i64, ptr %v307, i64 0
  store i64 358, ptr %v308, align 1
  %v309 = icmp ne i64 %v303, 0
  br i1 %v309, label %ok311, label %trap310
trap310:
  call void @native_trap()
  unreachable
ok311:
  %v312 = inttoptr i64 %v303 to ptr
  %v313 = getelementptr i64, ptr %v312, i64 1
  store i64 ptrtoint (ptr @ref.90 to i64), ptr %v313, align 1
  %v314 = icmp ne i64 %v303, 0
  br i1 %v314, label %ok316, label %trap315
trap315:
  call void @native_trap()
  unreachable
ok316:
  %v317 = inttoptr i64 %v303 to ptr
  %v318 = getelementptr i64, ptr %v317, i64 2
  store i64 0, ptr %v318, align 1
  %v319 = getelementptr i64, ptr %roots, i64 12
  store i64 %v303, ptr %v319, align 1
  %v320 = getelementptr i64, ptr %roots, i64 13
  store i64 0, ptr %v320, align 1
  %v321 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v321, align 1
  %v322 = call tailcc i64 @f.75(i64 %v299, i64 %v303, i64 0)
  %v325 = load i32, ptr @g.25, align 1
  %v326 = icmp eq i32 %v325, 0
  %v327 = zext i1 %v326 to i32
  %v331 = icmp ne i32 %v327, 0
  br i1 %v331, label %then330, label %else329
then330:
  call void @native_trap()
  unreachable
else329:
  br label %block328
block328:
  %v332 = load i64, ptr @g.24, align 1
  %v333 = icmp ne i64 %v332, 0
  br i1 %v333, label %ok335, label %trap334
trap334:
  call void @native_trap()
  unreachable
ok335:
  %v336 = getelementptr i64, ptr %roots, i64 12
  store i64 0, ptr %v336, align 1
  %v337 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.78 to i64), ptr %v337, align 1
  %v338 = getelementptr i64, ptr %roots, i64 14
  store i64 %v322, ptr %v338, align 1
  %v339 = getelementptr i64, ptr %roots, i64 2
  store i64 12, ptr %v339, align 1
  %v340 = call i64 @native_alloc(i64 24)
  %v341 = icmp ne i64 %v340, 0
  br i1 %v341, label %ok343, label %trap342
trap342:
  call void @native_trap()
  unreachable
ok343:
  %v344 = inttoptr i64 %v340 to ptr
  %v345 = getelementptr i64, ptr %v344, i64 0
  store i64 358, ptr %v345, align 1
  %v346 = icmp ne i64 %v340, 0
  br i1 %v346, label %ok348, label %trap347
trap347:
  call void @native_trap()
  unreachable
ok348:
  %v349 = inttoptr i64 %v340 to ptr
  %v350 = getelementptr i64, ptr %v349, i64 1
  store i64 ptrtoint (ptr @ref.78 to i64), ptr %v350, align 1
  %v351 = icmp ne i64 %v340, 0
  br i1 %v351, label %ok353, label %trap352
trap352:
  call void @native_trap()
  unreachable
ok353:
  %v354 = inttoptr i64 %v340 to ptr
  %v355 = getelementptr i64, ptr %v354, i64 2
  store i64 0, ptr %v355, align 1
  store i64 %v340, ptr %slot323, align 1
  br label %block324
block324:
  %v356 = load i64, ptr %slot323, align 1
  %v357 = getelementptr i64, ptr %roots, i64 12
  store i64 %v322, ptr %v357, align 1
  %v358 = getelementptr i64, ptr %roots, i64 13
  store i64 %v356, ptr %v358, align 1
  %v359 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v359, align 1
  %v360 = call tailcc i64 @f.22(i64 %v322, i64 %v356)
  store i64 %v360, ptr %v8, align 1
  %v361 = icmp ne i64 %v360, 0
  br i1 %v361, label %ok363, label %trap362
trap362:
  call void @native_trap()
  unreachable
ok363:
  %v364 = inttoptr i64 %v360 to ptr
  %v365 = getelementptr i64, ptr %v364, i64 1
  %v366 = load i64, ptr %v365, align 1
  store i64 %v366, ptr %v9, align 1
  %v367 = load i32, ptr @g.56, align 1
  %v368 = icmp eq i32 %v367, 0
  %v369 = zext i1 %v368 to i32
  %v373 = icmp ne i32 %v369, 0
  br i1 %v373, label %then372, label %else371
then372:
  call void @native_trap()
  unreachable
else371:
  br label %block370
block370:
  %v374 = load i64, ptr @g.55, align 1
  %v375 = icmp ne i64 %v374, 0
  br i1 %v375, label %ok377, label %trap376
trap376:
  call void @native_trap()
  unreachable
ok377:
  %v378 = load i64, ptr %slot2, align 1
  %v379 = load i64, ptr %v4, align 1
  %v380 = load i64, ptr %slot3, align 1
  %v381 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.55 to i64), ptr %v381, align 1
  %v382 = getelementptr i64, ptr %roots, i64 13
  store i64 %v379, ptr %v382, align 1
  %v383 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v383, align 1
  %v384 = call i64 @native_alloc(i64 16)
  %v385 = icmp ne i64 %v384, 0
  br i1 %v385, label %ok387, label %trap386
trap386:
  call void @native_trap()
  unreachable
ok387:
  %v388 = inttoptr i64 %v384 to ptr
  %v389 = getelementptr i64, ptr %v388, i64 0
  store i64 190, ptr %v389, align 1
  %v390 = icmp ne i64 %v384, 0
  br i1 %v390, label %ok392, label %trap391
trap391:
  call void @native_trap()
  unreachable
ok392:
  %v393 = inttoptr i64 %v384 to ptr
  %v394 = getelementptr i64, ptr %v393, i64 1
  store i64 %v380, ptr %v394, align 1
  %v395 = getelementptr i64, ptr %roots, i64 12
  store i64 %v384, ptr %v395, align 1
  %v396 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.55 to i64), ptr %v396, align 1
  %v397 = getelementptr i64, ptr %roots, i64 14
  store i64 %v379, ptr %v397, align 1
  %v398 = getelementptr i64, ptr %roots, i64 2
  store i64 12, ptr %v398, align 1
  %v399 = call i64 @native_alloc(i64 24)
  %v400 = icmp ne i64 %v399, 0
  br i1 %v400, label %ok402, label %trap401
trap401:
  call void @native_trap()
  unreachable
ok402:
  %v403 = inttoptr i64 %v399 to ptr
  %v404 = getelementptr i64, ptr %v403, i64 0
  store i64 650, ptr %v404, align 1
  %v405 = icmp ne i64 %v399, 0
  br i1 %v405, label %ok407, label %trap406
trap406:
  call void @native_trap()
  unreachable
ok407:
  %v408 = inttoptr i64 %v399 to ptr
  %v409 = getelementptr i64, ptr %v408, i64 1
  store i64 ptrtoint (ptr @ref.55 to i64), ptr %v409, align 1
  %v410 = icmp ne i64 %v399, 0
  br i1 %v410, label %ok412, label %trap411
trap411:
  call void @native_trap()
  unreachable
ok412:
  %v413 = inttoptr i64 %v399 to ptr
  %v414 = getelementptr i64, ptr %v413, i64 2
  store i64 %v384, ptr %v414, align 1
  store i64 %v399, ptr %v10, align 1
  %v415 = load i64, ptr %slot3, align 1
  %v416 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.56 to i64), ptr %v416, align 1
  %v417 = getelementptr i64, ptr %roots, i64 13
  store i64 %v399, ptr %v417, align 1
  %v418 = getelementptr i64, ptr %roots, i64 14
  store i64 %v379, ptr %v418, align 1
  %v419 = getelementptr i64, ptr %roots, i64 2
  store i64 12, ptr %v419, align 1
  %v420 = call i64 @native_alloc(i64 16)
  %v421 = icmp ne i64 %v420, 0
  br i1 %v421, label %ok423, label %trap422
trap422:
  call void @native_trap()
  unreachable
ok423:
  %v424 = inttoptr i64 %v420 to ptr
  %v425 = getelementptr i64, ptr %v424, i64 0
  store i64 186, ptr %v425, align 1
  %v426 = icmp ne i64 %v420, 0
  br i1 %v426, label %ok428, label %trap427
trap427:
  call void @native_trap()
  unreachable
ok428:
  %v429 = inttoptr i64 %v420 to ptr
  %v430 = getelementptr i64, ptr %v429, i64 1
  store i64 %v415, ptr %v430, align 1
  %v431 = getelementptr i64, ptr %roots, i64 12
  store i64 %v420, ptr %v431, align 1
  %v432 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.56 to i64), ptr %v432, align 1
  %v433 = getelementptr i64, ptr %roots, i64 14
  store i64 %v399, ptr %v433, align 1
  %v434 = getelementptr i64, ptr %roots, i64 15
  store i64 %v379, ptr %v434, align 1
  %v435 = getelementptr i64, ptr %roots, i64 2
  store i64 13, ptr %v435, align 1
  %v436 = call i64 @native_alloc(i64 24)
  %v437 = icmp ne i64 %v436, 0
  br i1 %v437, label %ok439, label %trap438
trap438:
  call void @native_trap()
  unreachable
ok439:
  %v440 = inttoptr i64 %v436 to ptr
  %v441 = getelementptr i64, ptr %v440, i64 0
  store i64 646, ptr %v441, align 1
  %v442 = icmp ne i64 %v436, 0
  br i1 %v442, label %ok444, label %trap443
trap443:
  call void @native_trap()
  unreachable
ok444:
  %v445 = inttoptr i64 %v436 to ptr
  %v446 = getelementptr i64, ptr %v445, i64 1
  store i64 ptrtoint (ptr @ref.56 to i64), ptr %v446, align 1
  %v447 = icmp ne i64 %v436, 0
  br i1 %v447, label %ok449, label %trap448
trap448:
  call void @native_trap()
  unreachable
ok449:
  %v450 = inttoptr i64 %v436 to ptr
  %v451 = getelementptr i64, ptr %v450, i64 2
  store i64 %v420, ptr %v451, align 1
  store i64 %v436, ptr %v11, align 1
  %v452 = load i64, ptr %slot3, align 1
  %v453 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.57 to i64), ptr %v453, align 1
  %v454 = getelementptr i64, ptr %roots, i64 13
  store i64 %v436, ptr %v454, align 1
  %v455 = getelementptr i64, ptr %roots, i64 14
  store i64 %v399, ptr %v455, align 1
  %v456 = getelementptr i64, ptr %roots, i64 15
  store i64 %v379, ptr %v456, align 1
  %v457 = getelementptr i64, ptr %roots, i64 2
  store i64 13, ptr %v457, align 1
  %v458 = call i64 @native_alloc(i64 16)
  %v459 = icmp ne i64 %v458, 0
  br i1 %v459, label %ok461, label %trap460
trap460:
  call void @native_trap()
  unreachable
ok461:
  %v462 = inttoptr i64 %v458 to ptr
  %v463 = getelementptr i64, ptr %v462, i64 0
  store i64 182, ptr %v463, align 1
  %v464 = icmp ne i64 %v458, 0
  br i1 %v464, label %ok466, label %trap465
trap465:
  call void @native_trap()
  unreachable
ok466:
  %v467 = inttoptr i64 %v458 to ptr
  %v468 = getelementptr i64, ptr %v467, i64 1
  store i64 %v452, ptr %v468, align 1
  %v469 = getelementptr i64, ptr %roots, i64 12
  store i64 %v458, ptr %v469, align 1
  %v470 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.57 to i64), ptr %v470, align 1
  %v471 = getelementptr i64, ptr %roots, i64 14
  store i64 %v436, ptr %v471, align 1
  %v472 = getelementptr i64, ptr %roots, i64 15
  store i64 %v399, ptr %v472, align 1
  %v473 = getelementptr i64, ptr %roots, i64 16
  store i64 %v379, ptr %v473, align 1
  %v474 = getelementptr i64, ptr %roots, i64 2
  store i64 14, ptr %v474, align 1
  %v475 = call i64 @native_alloc(i64 24)
  %v476 = icmp ne i64 %v475, 0
  br i1 %v476, label %ok478, label %trap477
trap477:
  call void @native_trap()
  unreachable
ok478:
  %v479 = inttoptr i64 %v475 to ptr
  %v480 = getelementptr i64, ptr %v479, i64 0
  store i64 638, ptr %v480, align 1
  %v481 = icmp ne i64 %v475, 0
  br i1 %v481, label %ok483, label %trap482
trap482:
  call void @native_trap()
  unreachable
ok483:
  %v484 = inttoptr i64 %v475 to ptr
  %v485 = getelementptr i64, ptr %v484, i64 1
  store i64 ptrtoint (ptr @ref.57 to i64), ptr %v485, align 1
  %v486 = icmp ne i64 %v475, 0
  br i1 %v486, label %ok488, label %trap487
trap487:
  call void @native_trap()
  unreachable
ok488:
  %v489 = inttoptr i64 %v475 to ptr
  %v490 = getelementptr i64, ptr %v489, i64 2
  store i64 %v458, ptr %v490, align 1
  store i64 %v475, ptr %v7, align 1
  %v491 = load i64, ptr %slot3, align 1
  %v492 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.58 to i64), ptr %v492, align 1
  %v493 = getelementptr i64, ptr %roots, i64 13
  store i64 %v475, ptr %v493, align 1
  %v494 = getelementptr i64, ptr %roots, i64 14
  store i64 %v436, ptr %v494, align 1
  %v495 = getelementptr i64, ptr %roots, i64 15
  store i64 %v399, ptr %v495, align 1
  %v496 = getelementptr i64, ptr %roots, i64 16
  store i64 %v379, ptr %v496, align 1
  %v497 = getelementptr i64, ptr %roots, i64 2
  store i64 14, ptr %v497, align 1
  %v498 = call i64 @native_alloc(i64 16)
  %v499 = icmp ne i64 %v498, 0
  br i1 %v499, label %ok501, label %trap500
trap500:
  call void @native_trap()
  unreachable
ok501:
  %v502 = inttoptr i64 %v498 to ptr
  %v503 = getelementptr i64, ptr %v502, i64 0
  store i64 178, ptr %v503, align 1
  %v504 = icmp ne i64 %v498, 0
  br i1 %v504, label %ok506, label %trap505
trap505:
  call void @native_trap()
  unreachable
ok506:
  %v507 = inttoptr i64 %v498 to ptr
  %v508 = getelementptr i64, ptr %v507, i64 1
  store i64 %v491, ptr %v508, align 1
  %v509 = getelementptr i64, ptr %roots, i64 12
  store i64 %v498, ptr %v509, align 1
  %v510 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.58 to i64), ptr %v510, align 1
  %v511 = getelementptr i64, ptr %roots, i64 14
  store i64 %v475, ptr %v511, align 1
  %v512 = getelementptr i64, ptr %roots, i64 15
  store i64 %v436, ptr %v512, align 1
  %v513 = getelementptr i64, ptr %roots, i64 16
  store i64 %v399, ptr %v513, align 1
  %v514 = getelementptr i64, ptr %roots, i64 17
  store i64 %v379, ptr %v514, align 1
  %v515 = getelementptr i64, ptr %roots, i64 2
  store i64 15, ptr %v515, align 1
  %v516 = call i64 @native_alloc(i64 24)
  %v517 = icmp ne i64 %v516, 0
  br i1 %v517, label %ok519, label %trap518
trap518:
  call void @native_trap()
  unreachable
ok519:
  %v520 = inttoptr i64 %v516 to ptr
  %v521 = getelementptr i64, ptr %v520, i64 0
  store i64 646, ptr %v521, align 1
  %v522 = icmp ne i64 %v516, 0
  br i1 %v522, label %ok524, label %trap523
trap523:
  call void @native_trap()
  unreachable
ok524:
  %v525 = inttoptr i64 %v516 to ptr
  %v526 = getelementptr i64, ptr %v525, i64 1
  store i64 ptrtoint (ptr @ref.58 to i64), ptr %v526, align 1
  %v527 = icmp ne i64 %v516, 0
  br i1 %v527, label %ok529, label %trap528
trap528:
  call void @native_trap()
  unreachable
ok529:
  %v530 = inttoptr i64 %v516 to ptr
  %v531 = getelementptr i64, ptr %v530, i64 2
  store i64 %v498, ptr %v531, align 1
  store i64 %v516, ptr %v12, align 1
  %v532 = load i64, ptr %v10, align 1
  %v533 = load i64, ptr %v11, align 1
  %v534 = load i64, ptr %v7, align 1
  %v535 = load i64, ptr %v12, align 1
  %v536 = load i64, ptr %v6, align 1
  %v537 = getelementptr i64, ptr %roots, i64 12
  store i64 %v536, ptr %v537, align 1
  %v538 = getelementptr i64, ptr %roots, i64 13
  store i64 %v535, ptr %v538, align 1
  %v539 = getelementptr i64, ptr %roots, i64 14
  store i64 %v534, ptr %v539, align 1
  %v540 = getelementptr i64, ptr %roots, i64 15
  store i64 %v533, ptr %v540, align 1
  %v541 = getelementptr i64, ptr %roots, i64 16
  store i64 %v532, ptr %v541, align 1
  %v542 = getelementptr i64, ptr %roots, i64 17
  store i64 ptrtoint (ptr @ref.40 to i64), ptr %v542, align 1
  %v543 = getelementptr i64, ptr %roots, i64 18
  store i64 %v516, ptr %v543, align 1
  %v544 = getelementptr i64, ptr %roots, i64 19
  store i64 %v475, ptr %v544, align 1
  %v545 = getelementptr i64, ptr %roots, i64 20
  store i64 %v436, ptr %v545, align 1
  %v546 = getelementptr i64, ptr %roots, i64 21
  store i64 %v399, ptr %v546, align 1
  %v547 = getelementptr i64, ptr %roots, i64 22
  store i64 %v379, ptr %v547, align 1
  %v548 = getelementptr i64, ptr %roots, i64 2
  store i64 20, ptr %v548, align 1
  %v549 = call i64 @native_alloc(i64 48)
  %v550 = icmp ne i64 %v549, 0
  br i1 %v550, label %ok552, label %trap551
trap551:
  call void @native_trap()
  unreachable
ok552:
  %v553 = inttoptr i64 %v549 to ptr
  %v554 = getelementptr i64, ptr %v553, i64 0
  store i64 262, ptr %v554, align 1
  %v555 = icmp ne i64 %v549, 0
  br i1 %v555, label %ok557, label %trap556
trap556:
  call void @native_trap()
  unreachable
ok557:
  %v558 = inttoptr i64 %v549 to ptr
  %v559 = getelementptr i64, ptr %v558, i64 1
  store i64 %v532, ptr %v559, align 1
  %v560 = icmp ne i64 %v549, 0
  br i1 %v560, label %ok562, label %trap561
trap561:
  call void @native_trap()
  unreachable
ok562:
  %v563 = inttoptr i64 %v549 to ptr
  %v564 = getelementptr i64, ptr %v563, i64 2
  store i64 %v533, ptr %v564, align 1
  %v565 = icmp ne i64 %v549, 0
  br i1 %v565, label %ok567, label %trap566
trap566:
  call void @native_trap()
  unreachable
ok567:
  %v568 = inttoptr i64 %v549 to ptr
  %v569 = getelementptr i64, ptr %v568, i64 3
  store i64 %v534, ptr %v569, align 1
  %v570 = icmp ne i64 %v549, 0
  br i1 %v570, label %ok572, label %trap571
trap571:
  call void @native_trap()
  unreachable
ok572:
  %v573 = inttoptr i64 %v549 to ptr
  %v574 = getelementptr i64, ptr %v573, i64 4
  store i64 %v535, ptr %v574, align 1
  %v575 = icmp ne i64 %v549, 0
  br i1 %v575, label %ok577, label %trap576
trap576:
  call void @native_trap()
  unreachable
ok577:
  %v578 = inttoptr i64 %v549 to ptr
  %v579 = getelementptr i64, ptr %v578, i64 5
  store i64 %v536, ptr %v579, align 1
  %v580 = getelementptr i64, ptr %roots, i64 12
  store i64 %v549, ptr %v580, align 1
  %v581 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.40 to i64), ptr %v581, align 1
  %v582 = getelementptr i64, ptr %roots, i64 14
  store i64 %v516, ptr %v582, align 1
  %v583 = getelementptr i64, ptr %roots, i64 15
  store i64 %v475, ptr %v583, align 1
  %v584 = getelementptr i64, ptr %roots, i64 16
  store i64 %v436, ptr %v584, align 1
  %v585 = getelementptr i64, ptr %roots, i64 17
  store i64 %v399, ptr %v585, align 1
  %v586 = getelementptr i64, ptr %roots, i64 18
  store i64 %v379, ptr %v586, align 1
  %v587 = getelementptr i64, ptr %roots, i64 2
  store i64 16, ptr %v587, align 1
  %v588 = call i64 @native_alloc(i64 24)
  %v589 = icmp ne i64 %v588, 0
  br i1 %v589, label %ok591, label %trap590
trap590:
  call void @native_trap()
  unreachable
ok591:
  %v592 = inttoptr i64 %v588 to ptr
  %v593 = getelementptr i64, ptr %v592, i64 0
  store i64 634, ptr %v593, align 1
  %v594 = icmp ne i64 %v588, 0
  br i1 %v594, label %ok596, label %trap595
trap595:
  call void @native_trap()
  unreachable
ok596:
  %v597 = inttoptr i64 %v588 to ptr
  %v598 = getelementptr i64, ptr %v597, i64 1
  store i64 ptrtoint (ptr @ref.40 to i64), ptr %v598, align 1
  %v599 = icmp ne i64 %v588, 0
  br i1 %v599, label %ok601, label %trap600
trap600:
  call void @native_trap()
  unreachable
ok601:
  %v602 = inttoptr i64 %v588 to ptr
  %v603 = getelementptr i64, ptr %v602, i64 2
  store i64 %v549, ptr %v603, align 1
  %v604 = getelementptr i64, ptr %roots, i64 12
  store i64 %v588, ptr %v604, align 1
  %v605 = getelementptr i64, ptr %roots, i64 13
  store i64 %v516, ptr %v605, align 1
  %v606 = getelementptr i64, ptr %roots, i64 14
  store i64 %v475, ptr %v606, align 1
  %v607 = getelementptr i64, ptr %roots, i64 15
  store i64 %v436, ptr %v607, align 1
  %v608 = getelementptr i64, ptr %roots, i64 16
  store i64 %v399, ptr %v608, align 1
  %v609 = getelementptr i64, ptr %roots, i64 17
  store i64 %v379, ptr %v609, align 1
  %v610 = getelementptr i64, ptr %roots, i64 2
  store i64 15, ptr %v610, align 1
  %v611 = call i64 @native_alloc(i64 48)
  %v612 = icmp ne i64 %v611, 0
  br i1 %v612, label %ok614, label %trap613
trap613:
  call void @native_trap()
  unreachable
ok614:
  %v615 = inttoptr i64 %v611 to ptr
  %v616 = getelementptr i64, ptr %v615, i64 0
  store i64 118, ptr %v616, align 1
  %v617 = icmp ne i64 %v611, 0
  br i1 %v617, label %ok619, label %trap618
trap618:
  call void @native_trap()
  unreachable
ok619:
  %v620 = inttoptr i64 %v611 to ptr
  %v621 = getelementptr i64, ptr %v620, i64 1
  store i64 %v399, ptr %v621, align 1
  %v622 = icmp ne i64 %v611, 0
  br i1 %v622, label %ok624, label %trap623
trap623:
  call void @native_trap()
  unreachable
ok624:
  %v625 = inttoptr i64 %v611 to ptr
  %v626 = getelementptr i64, ptr %v625, i64 2
  store i64 %v436, ptr %v626, align 1
  %v627 = icmp ne i64 %v611, 0
  br i1 %v627, label %ok629, label %trap628
trap628:
  call void @native_trap()
  unreachable
ok629:
  %v630 = inttoptr i64 %v611 to ptr
  %v631 = getelementptr i64, ptr %v630, i64 3
  store i64 %v475, ptr %v631, align 1
  %v632 = icmp ne i64 %v611, 0
  br i1 %v632, label %ok634, label %trap633
trap633:
  call void @native_trap()
  unreachable
ok634:
  %v635 = inttoptr i64 %v611 to ptr
  %v636 = getelementptr i64, ptr %v635, i64 4
  store i64 %v516, ptr %v636, align 1
  %v637 = icmp ne i64 %v611, 0
  br i1 %v637, label %ok639, label %trap638
trap638:
  call void @native_trap()
  unreachable
ok639:
  %v640 = inttoptr i64 %v611 to ptr
  %v641 = getelementptr i64, ptr %v640, i64 5
  store i64 %v588, ptr %v641, align 1
  %v642 = getelementptr i64, ptr %roots, i64 12
  store i64 %v611, ptr %v642, align 1
  %v643 = getelementptr i64, ptr %roots, i64 13
  store i64 %v379, ptr %v643, align 1
  %v644 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v644, align 1
  %v645 = call i64 @native_alloc(i64 16)
  %v646 = icmp ne i64 %v645, 0
  br i1 %v646, label %ok648, label %trap647
trap647:
  call void @native_trap()
  unreachable
ok648:
  %v649 = inttoptr i64 %v645 to ptr
  %v650 = getelementptr i64, ptr %v649, i64 0
  store i64 114, ptr %v650, align 1
  %v651 = icmp ne i64 %v645, 0
  br i1 %v651, label %ok653, label %trap652
trap652:
  call void @native_trap()
  unreachable
ok653:
  %v654 = inttoptr i64 %v645 to ptr
  %v655 = getelementptr i64, ptr %v654, i64 1
  store i64 %v611, ptr %v655, align 1
  %v656 = load i64, ptr %v9, align 1
  %v657 = getelementptr i64, ptr %roots, i64 12
  store i64 0, ptr %v657, align 1
  %v658 = getelementptr i64, ptr %roots, i64 13
  store i64 %v656, ptr %v658, align 1
  %v659 = getelementptr i64, ptr %roots, i64 14
  store i64 %v645, ptr %v659, align 1
  %v660 = getelementptr i64, ptr %roots, i64 15
  store i64 %v379, ptr %v660, align 1
  %v661 = getelementptr i64, ptr %roots, i64 2
  store i64 13, ptr %v661, align 1
  %v662 = call i64 @native_alloc(i64 24)
  %v663 = icmp ne i64 %v662, 0
  br i1 %v663, label %ok665, label %trap664
trap664:
  call void @native_trap()
  unreachable
ok665:
  %v666 = inttoptr i64 %v662 to ptr
  %v667 = getelementptr i64, ptr %v666, i64 0
  store i64 422, ptr %v667, align 1
  %v668 = icmp ne i64 %v662, 0
  br i1 %v668, label %ok670, label %trap669
trap669:
  call void @native_trap()
  unreachable
ok670:
  %v671 = inttoptr i64 %v662 to ptr
  %v672 = getelementptr i64, ptr %v671, i64 1
  store i64 %v656, ptr %v672, align 1
  %v673 = icmp ne i64 %v662, 0
  br i1 %v673, label %ok675, label %trap674
trap674:
  call void @native_trap()
  unreachable
ok675:
  %v676 = inttoptr i64 %v662 to ptr
  %v677 = getelementptr i64, ptr %v676, i64 2
  store i64 0, ptr %v677, align 1
  %v678 = load i64, ptr %v8, align 1
  %v679 = icmp ne i64 %v678, 0
  br i1 %v679, label %ok681, label %trap680
trap680:
  call void @native_trap()
  unreachable
ok681:
  %v682 = inttoptr i64 %v678 to ptr
  %v683 = getelementptr i64, ptr %v682, i64 2
  %v684 = load i64, ptr %v683, align 1
  %v685 = getelementptr i64, ptr %roots, i64 12
  store i64 0, ptr %v685, align 1
  %v686 = getelementptr i64, ptr %roots, i64 13
  store i64 %v684, ptr %v686, align 1
  %v687 = getelementptr i64, ptr %roots, i64 14
  store i64 %v662, ptr %v687, align 1
  %v688 = getelementptr i64, ptr %roots, i64 15
  store i64 %v645, ptr %v688, align 1
  %v689 = getelementptr i64, ptr %roots, i64 16
  store i64 %v379, ptr %v689, align 1
  %v690 = getelementptr i64, ptr %roots, i64 2
  store i64 14, ptr %v690, align 1
  %v691 = call i64 @native_alloc(i64 32)
  %v692 = icmp ne i64 %v691, 0
  br i1 %v692, label %ok694, label %trap693
trap693:
  call void @native_trap()
  unreachable
ok694:
  %v695 = inttoptr i64 %v691 to ptr
  %v696 = getelementptr i64, ptr %v695, i64 0
  store i64 134, ptr %v696, align 1
  %v697 = icmp ne i64 %v691, 0
  br i1 %v697, label %ok699, label %trap698
trap698:
  call void @native_trap()
  unreachable
ok699:
  %v700 = inttoptr i64 %v691 to ptr
  %v701 = getelementptr i64, ptr %v700, i64 1
  store i64 -1, ptr %v701, align 1
  %v702 = icmp ne i64 %v691, 0
  br i1 %v702, label %ok704, label %trap703
trap703:
  call void @native_trap()
  unreachable
ok704:
  %v705 = inttoptr i64 %v691 to ptr
  %v706 = getelementptr i64, ptr %v705, i64 2
  store i64 -1, ptr %v706, align 1
  %v707 = icmp ne i64 %v691, 0
  br i1 %v707, label %ok709, label %trap708
trap708:
  call void @native_trap()
  unreachable
ok709:
  %v710 = inttoptr i64 %v691 to ptr
  %v711 = getelementptr i64, ptr %v710, i64 3
  store i64 0, ptr %v711, align 1
  %v712 = getelementptr i64, ptr %roots, i64 12
  store i64 %v379, ptr %v712, align 1
  %v713 = getelementptr i64, ptr %roots, i64 13
  store i64 %v645, ptr %v713, align 1
  %v714 = getelementptr i64, ptr %roots, i64 14
  store i64 %v662, ptr %v714, align 1
  %v715 = getelementptr i64, ptr %roots, i64 15
  store i64 %v684, ptr %v715, align 1
  %v716 = getelementptr i64, ptr %roots, i64 16
  store i64 %v691, ptr %v716, align 1
  %v717 = getelementptr i64, ptr %roots, i64 2
  store i64 14, ptr %v717, align 1
  %v718 = call tailcc i64 @f.79(i64 %v378, i64 %v379, i64 %v645, i32 0, i32 0, i32 1, i64 1, i64 %v662, i64 %v684, i64 %v691)
  %v719 = icmp ne i64 %v718, 0
  br i1 %v719, label %ok721, label %trap720
trap720:
  call void @native_trap()
  unreachable
ok721:
  %v722 = inttoptr i64 %v718 to ptr
  %v723 = getelementptr i64, ptr %v722, i64 3
  %v724 = load i64, ptr %v723, align 1
  store i64 %v724, ptr %slot13, align 1
  br label %return14
return14:
  %v725 = load i64, ptr %slot13, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v725
}
