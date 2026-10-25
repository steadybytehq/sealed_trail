# frozen_string_literal: true

module SealedTrail
  # Labels entries recorded while a rake task runs as "rake:<task name>".
  module RakeContext
    module_function

    def install!
      return unless defined?(::Rake::Task)
      return if ::Rake::Task.ancestors.include?(TaskHook)

      ::Rake::Task.prepend(TaskHook)
    end

    module TaskHook
      def execute(*args)
        previous = SealedTrail.process_actor_label
        SealedTrail.process_actor_label = "rake:#{name}"
        super
      ensure
        SealedTrail.process_actor_label = previous
      end
    end
  end
end
