#include "ss-core/smt.hh"
#include <mutex>

namespace ss {

    template <typename T>
    bool SmtFifo<T>::empty() const {
        std::unique_lock lg{m_mutex};
        return m_queue.empty();
    }
    template <typename T>
    void SmtFifo<T>::enqueue(T v) {
        {
            std::unique_lock lg{m_mutex};
            m_queue.push(std::move(v));
        }
        // NOTE: notify AFTER releasing the lock
        // NOTE: notify on each push => handle multiple consumers
        m_cv.notify_one();
    }
    template <typename T>
    std::optional<T> SmtFifo<T>::try_dequeue() {
        std::unique_lock lock{m_mutex};
        lock.lock();

        if (m_queue.empty()) {
            return {};
        } else {
            T popped = m_queue.front();
            m_queue.pop();
            return {std::move(popped)};
        }
    }
    template <typename T>
    T SmtFifo<T>::wait_and_dequeue() {
        std::unique_lock lock{m_mutex};
        lock.lock();

        while (m_queue.empty()) {
            m_cv.wait(lock);
        }
        T popped = std::move(m_queue.front());
        m_queue.pop();
        return popped;
    }

}