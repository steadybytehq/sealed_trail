# frozen_string_literal: true

module SealedTrail
  # Per-request (and per-job) state, isolated per thread or fiber according to
  # Rails' isolation level and reset automatically by the Rails executor.
  class Current < ActiveSupport::CurrentAttributes
    # Explicit actor: an Active Record object, or a String/Symbol label.
    attribute :actor
    # A callable that returns the actor; used when +actor+ is not set. The
    # controller concern stores one so authentication can run later.
    attribute :actor_resolver
    # Fallback label for this unit of work, e.g. "anonymous" in a request or
    # "job:ImportJob" in a job.
    attribute :context_label
    attribute :request_id
    attribute :remote_ip
    attribute :metadata
    attribute :tracking_disabled

    # The explicit or request actor, without fallbacks.
    def identified_actor
      return actor unless actor.nil?

      actor_resolver&.call
    end
  end
end
