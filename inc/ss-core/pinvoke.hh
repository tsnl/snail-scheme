#pragma once

#include <functional>
#include <optional>

#include "ss-core/vthread.hh"

#include "common.hh"

namespace ss {
  class ArgView {
  private:
    VmStack& m_stack;
    my_ssize_t m_offset;
    my_ssize_t m_count;
  public:
    ArgView(VmStack& s, my_ssize_t offset, my_ssize_t count) 
    : m_stack(s),
      m_offset(offset),
      m_count(count) {}
  public:
    my_ssize_t size() const { return m_count; }
    OBJECT operator[](my_ssize_t idx) const {
      if (0 <= idx && idx < m_count) {
        return m_stack.index(m_offset, idx);
      } else {
        error("out-of-bounds stack access: cannot reach arg at index " + std::to_string(idx));
        throw SsiError();
      }
    }
  };

  using PlatformProcCb = std::function<OBJECT(ArgView const& args)>;
  using PlatformProcID = size_t;

  struct PlatformProcMetadata {
    IntStr name;
    my_ssize_t arity;
    std::string docstring;
    std::vector<IntStr> args;

    PlatformProcMetadata(IntStr name, my_ssize_t arity, std::string docstring, std::vector<IntStr> args)
    : name(name), arity(arity), docstring(std::move(docstring)), args(std::move(args)) 
    {}
  };

  class PlatformProcTable {
  public:
    inline static size_t const INIT_CAPACITY = 512;
    
  private:
    std::vector<PlatformProcCb> m_cb_table;
    std::vector<PlatformProcMetadata> m_metadata_table;
    UnstableHashMap<IntStr, PlatformProcID> m_id_symtab;
    
  public:
    explicit PlatformProcTable(size_t init_capacity=PlatformProcTable::INIT_CAPACITY);

  public:
    PlatformProcID define(
      IntStr platform_proc_name, 
      std::vector<IntStr> arg_names, 
      PlatformProcCb callable_cb,
      std::string docstring, bool is_variadic
    );
  public:
    std::optional<PlatformProcID> lookup(IntStr proc_name);
    PlatformProcCb const& cb(PlatformProcID proc_id) const { return m_cb_table[proc_id]; }
    PlatformProcMetadata const& metadata(PlatformProcID proc_id) const { return m_metadata_table[proc_id]; }
  };
}
