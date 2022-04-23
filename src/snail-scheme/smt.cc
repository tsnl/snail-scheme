#include "snail-scheme/smt.hh"

template <typename T>
bool SmtFifo<T>::empty() const {
    std::lock_guard lg{m_mutex};
    return m_queue.empty();
}
template <typename T>
void SmtFifo<T>::enqueue(T v) {
    {
        std::lock_guard lg{m_mutex};
        m_queue.push(std::move(v));
    }
    // NOTE: notify AFTER releasing the lock
    // NOTE: notify on each push => handle multiple consumers
    m_cv.notify_one();
}
template <typename T>
std::optional<T> SmtFifo<T>::try_dequeue() {
    std::lock_guard lg{m_mutex};
    if (m_queue.empty()) {
        return {};
    } else {
        T popped = m_queue.front();
        m_queue.pop();
        return {std::move(popped)};
    }
}
template <typename T>
typename T SmtFifo<T>::wait_and_dequeue() {
    std::lock_guard lg{m_mutex};
    while (m_queue.empty()) {
        m_cv.wait(lg);
    }
    T popped = std::move(m_queue.front());
    m_queue.pop();
    return popped;
}