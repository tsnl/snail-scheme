#pragma once

#include <queue>
#include <optional>
#include <mutex>
#include <condition_variable>

namespace ss {

    // Based on...
    // https://www.justsoftwaresolutions.co.uk/threading/implementing-a-thread-safe-queue-using-condition-variables.html
    template <typename T>
    class SmtFifo {
    private:
        std::queue<T> m_queue;
        std::mutex m_mutex;
        std::condition_variable m_cv;
    public:
        SmtFifo();
    public:
        bool empty() const;
        void enqueue(T v);
        std::optional<T> try_dequeue();
        T wait_and_dequeue();
    };

}   // namespace ss