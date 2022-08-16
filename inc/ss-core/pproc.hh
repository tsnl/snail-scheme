#pragma once

#include <functional>

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
        throw new SsiError();
      }
    }
  };

  using PlatformProcCb = std::function<OBJECT(ArgView const& args)>;
  using PlatformProcID = size_t;
}
