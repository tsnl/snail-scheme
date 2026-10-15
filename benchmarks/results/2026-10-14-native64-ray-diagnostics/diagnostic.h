void native_diagnostic_constructor(uint64_t, uint64_t);
void native_diagnostic_allocation(size_t);
void native_diagnostic_enter(uint64_t);
void native_diagnostic_leave(uint64_t);
void native_diagnostic_gc_report(const char *);
void native_diagnostic_report(const char *);
