# frozen_string_literal: true

require "test_helper"

class LifecycleHooksTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "run lifecycle hooks" do
    SolidQueue.on_start { JobResult.create!(status: :hook_called, value: :start) }
    SolidQueue.on_stop { JobResult.create!(status: :hook_called, value: :stop) }

    SolidQueue.on_worker_start { JobResult.create!(status: :hook_called, value: :worker_start) }
    SolidQueue.on_worker_stop { JobResult.create!(status: :hook_called, value: :worker_stop) }

    SolidQueue.on_dispatcher_start { JobResult.create!(status: :hook_called, value: :dispatcher_start) }
    SolidQueue.on_dispatcher_stop { JobResult.create!(status: :hook_called, value: :dispatcher_stop) }

    SolidQueue.on_scheduler_start { JobResult.create!(status: :hook_called, value: :scheduler_start) }
    SolidQueue.on_scheduler_stop { JobResult.create!(status: :hook_called, value: :scheduler_stop) }

    pid = run_supervisor_as_fork(workers: [ { queues: "*" } ], dispatchers: [ { batch_size: 100 } ], skip_recurring: false)
    wait_for_registered_processes(4)

    terminate_process(pid)
    wait_for_registered_processes(0)

    results = skip_active_record_query_cache do
      assert_equal 8, JobResult.count
      JobResult.last(8)
    end

    assert_equal({ "hook_called" => 8 }, results.map(&:status).tally)
    assert_equal %w[start stop worker_start worker_stop dispatcher_start dispatcher_stop scheduler_start scheduler_stop].sort, results.map(&:value).sort
  ensure
    SolidQueue::Supervisor.clear_hooks
    SolidQueue::Worker.clear_hooks
    SolidQueue::Dispatcher.clear_hooks
    SolidQueue::Scheduler.clear_hooks
  end

  test "handle errors on lifecycle hooks" do
    previous_on_thread_error, SolidQueue.on_thread_error = SolidQueue.on_thread_error, ->(error) { JobResult.create!(status: :error, value: error.message) }
    SolidQueue.on_start { raise RuntimeError, "everything is broken" }

    pid = run_supervisor_as_fork
    wait_for_registered_processes(4)

    terminate_process(pid)
    wait_for_registered_processes(0)

    result = skip_active_record_query_cache { JobResult.last }

    assert_equal "error", result.status
    assert_equal "everything is broken", result.value
  ensure
    SolidQueue.on_thread_error = previous_on_thread_error
    SolidQueue::Supervisor.clear_hooks
    SolidQueue::Worker.clear_hooks
    SolidQueue::Dispatcher.clear_hooks
    SolidQueue::Scheduler.clear_hooks
  end
end
