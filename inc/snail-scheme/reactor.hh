// #pragma once

// #include <string>
// #include <vector>
// #include <mutex>
// #include <condition_variable>
// #include <thread>
// #include <queue>
// #include <variant>
// #include <functional>

// #include "intern.hh"
// #include "module.hh"
// #include "object.hh"
// #include "memory.hh"
// #include "vm.hh"

// class Reactor {
// public:
//     using Flags = size_t;
//     using CppCallback = std::function<void(OBJECT)>;
//     using ScmCallback = OBJECT;
//     using AnyCallback = std::variant<CppCallback, ScmCallback>;
//     using EventTypeID = size_t;
//     using SubscriptionID = size_t;

// public:
//     enum class Flag: Flags {
//         IsStarted   = 0x1,
//         IsRunning   = 0x2,      // may be false after IsStarted when paused, allows workers to work
//         InDebugMode = 0x4,
//     };

// private:
//     struct Callback { AnyCallback impl; size_t id; };
//     struct CbList   { std::vector<Callback> content; size_t counter; };

// public:
//     struct Event { 
//         IntStr name; 
//         OBJECT args; 
//     };
//     class EventType {
//     private:
//         IntStr m_name;
//         std::string m_desc;
//         size_t m_uid;
//         CbList m_cb_list;
//     public:
//         EventType(IntStr name, std::string desc, size_t uid);
//     public:
//         void subscribe(CppCallback callback);
//         void subscribe(ScmCallback callback);
//         void broadcast(Reactor* reactor, OBJECT args);
//     public:
//         CbList& cb_list() { return m_cb_list; }
//     };

// private:
//     struct Job {
//         AnyCallback cb;
//         Event event;
//     };
//     class Worker {
//     private:
//         std::thread m_thread;
//         StackAllocator m_stack;
//         VirtualMachine* m_vm;
//     public:
//         Worker(Worker&& other);
//         Worker(Reactor* reactor, StackAllocator&& stack);
//         ~Worker();
//     private:
//         void worker_main(Reactor* reactor);
//     public:
//         std::thread& thread() { return m_thread; }
//         StackAllocator& stack() { return m_stack; }
//         VirtualMachine* vm() { return m_vm; }
//     };

// private:
//     friend EventType;
//     friend Event;
//     friend Worker;
//     friend Job;

// private:
//     ModuleGraph m_module_graph;
//     std::vector<EventType> m_event_types;

//     std::mutex m_work_mutex;
//     std::condition_variable m_work_cv;
//     std::vector<Worker> m_worker_pool;
//     std::queue<Job> m_work_queue;

//     RootStackAllocator m_root_stack;

//     Flags m_flags;
    
// public:
//     Reactor(ModuleGraph&& module_graph, std::vector<EventType>&& event_defs, bool in_debug_mode=false);

// public:
//     EventTypeID define_event_type(IntStr name, std::string desc);

// public:
//     void start_reactor(int max_thread_count);
//     void unpause_reactor(int max_thread_count);
//     void pause_reactor();
//     void stop_reactor();
    
//     SubscriptionID subscribe_event(EventTypeID event_type, CppCallback callabck);
//     SubscriptionID subscribe_event(EventTypeID event_type, ScmCallback callback);
    
//     void broadcast_event(EventTypeID event_type, OBJECT args);

// public:
//     RootStackAllocator& root_stack() { return m_root_stack; }
// };
