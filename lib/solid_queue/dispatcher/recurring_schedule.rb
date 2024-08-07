# frozen_string_literal: true

module SolidQueue
  class Dispatcher::RecurringSchedule
    include AppExecutor

    attr_reader :configured_tasks, :scheduled_tasks

    def initialize(tasks)
      @configured_tasks = Array(tasks).map { |task| Dispatcher::RecurringTask.wrap(task) }
      @scheduled_tasks = Concurrent::Hash.new
    end

    def empty?
      configured_tasks.empty?
    end

    def load_tasks
      configured_tasks.each do |task|
        load_task(task)
      end
    end

    def load_task(task)
      scheduled_tasks[task.key] = schedule(task)
    end

    def unload_tasks
      scheduled_tasks.values.each(&:cancel)
      scheduled_tasks.clear
    end

    def tasks
      configured_tasks.each_with_object({}) { |task, hsh| hsh[task.key] = task.to_h }
    end

    def inspect
      configured_tasks.map(&:to_s).join(" | ")
    end

    private
      def schedule(task)
        scheduled_task = Concurrent::ScheduledTask.new(task.delay_from_now, args: [ self, task, task.next_time ]) do |thread_schedule, thread_task, thread_task_run_at|
          thread_schedule.load_task(thread_task)

          wrap_in_app_executor do
            thread_task.enqueue(at: thread_task_run_at)
          end
        end

        scheduled_task.add_observer do |_, _, error|
          # Don't notify on task cancellation before execution, as this will happen normally
          # as part of unloading tasks
          handle_thread_error(error) if error && !error.is_a?(Concurrent::CancelledOperationError)
        end

        scheduled_task.tap(&:execute)
      end
  end
end
