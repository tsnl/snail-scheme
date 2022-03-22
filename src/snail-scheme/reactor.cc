#include "snail-scheme/reactor.hh"

#include <sstream>
#include <stdexcept>
#include <cassert>

#include "config/config.hh"

// DOC
// - on multithreading
//   https://www.justsoftwaresolutions.co.uk/threading/implementing-a-thread-safe-queue-using-condition-variables.html


//
// Constructor
//

Reactor::Reactor(ModuleGraph&& module_graph, std::vector<Reactor::EventType>&& event_types, bool in_debug_mode)
:   m_module_graph(std::move(module_graph)),
    m_event_types(std::move(event_types)),
    m_work_mutex(),
    m_worker_pool(),
    m_flags(
        (in_debug_mode ? static_cast<size_t>(Flag::InDebugMode) : 0)
    )
{}

//
// Start->Stop
//

void Reactor::start_reactor(int thread_count) {
    {
        std::lock_guard lg{m_work_mutex};
        m_flags |= static_cast<size_t>(Flag::IsStarted);
    }
    unpause_reactor(thread_count);
}
void Reactor::unpause_reactor(int thread_count) {
    std::lock_guard lg{m_work_mutex};
    
    assert((m_flags & static_cast<size_t>(Flag::IsStarted)) == 0);
    m_flags |= static_cast<size_t>(Flag::IsRunning);

    if (thread_count < 0) {
        thread_count = static_cast<int>(std::thread::hardware_concurrency());
    }
    assert(m_worker_pool.empty());
    m_worker_pool.reserve(thread_count);
    for (int i = 0; i < thread_count; thread_count++) {
        StackAllocator worker_stack;
        m_worker_pool.emplace_back(this, std::move(worker_stack));
    }
}
void Reactor::pause_reactor() {
    std::lock_guard lg{m_work_mutex};
    m_flags &= ~static_cast<size_t>(Flag::IsRunning);
    m_worker_pool.clear();
    assert(m_worker_pool.empty());
}
void Reactor::stop_reactor() {
    pause_reactor();
    
    {
        std::lock_guard lg{m_work_mutex};
        m_flags &= ~static_cast<size_t>(Flag::IsStarted);
        for (auto& event_type: m_event_types) {
            event_type.cb_list().content.clear();
        }
    }
}

//
// Job queue management:
//

Reactor::Worker::Worker(Reactor* reactor, StackAllocator&& stack) 
:   m_thread(&Reactor::Worker::worker_main, this, reactor),
    m_stack(std::move(stack)),
    m_vm(create_vm())
{}
Reactor::Worker::Worker(Worker&& worker)
:   m_thread(std::move(worker.m_thread)),
    m_stack(std::move(worker.m_stack)),
    m_vm(worker.m_vm)
{}
Reactor::Worker::~Worker() {
    m_thread.join();
    destroy_vm(m_vm);
}
Reactor::EventType::EventType(IntStr name, std::string desc, size_t uid)
:   m_name(name),
    m_desc(std::move(desc)),
    m_uid(uid),
    m_cb_list()
{}
Reactor::EventTypeID Reactor::define_event_type(IntStr name, std::string desc) {
    // Must define all event types before starting the reactor.
    assert((m_flags & static_cast<size_t>(Flag::IsStarted)) == 0);
    
    EventTypeID event_type_id = m_event_types.size();
    m_event_types.emplace_back(name, desc, event_type_id);
    return event_type_id;
}

void Reactor::EventType::subscribe(CppCallback callback) {
    m_cb_list.content.emplace_back(callback, m_cb_list.counter++);
}
void Reactor::EventType::subscribe(ScmCallback callback) {
    m_cb_list.content.emplace_back(callback, m_cb_list.counter++);
}
void Reactor::broadcast_event(EventTypeID event_type, OBJECT args) {
    m_event_types[event_type].broadcast(this, args);
}
void Reactor::EventType::broadcast(Reactor* reactor, OBJECT args) {
    for (auto cb: m_cb_list.content) {
        Job new_job{cb.impl, {m_name, args}};
        
        {
            std::lock_guard lg{reactor->m_work_mutex};
            reactor->m_work_queue.push(std::move(new_job));
        }

        reactor->m_work_cv.notify_one();
    }
}
void Reactor::Worker::worker_main(Reactor* reactor) {
    // TODO: poll the job queue
    // - use m_work_cv.wait, dequeue a job, execute using VM if required
    // - update memory management so that every `OBJECT::make_?` function accepts an allocator
    // - call 'broadcast_event' from external callbacks, need to create data.
}
