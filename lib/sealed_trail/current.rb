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
    attribute :request_id
    attribute :remote_ip
    attribute :metadata
    attribute :tracking_disabled

    def resolved_actor
      return actor unless actor.nil?

      actor_resolver&.call
    end
  end
end
