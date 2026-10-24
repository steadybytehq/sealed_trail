# frozen_string_literal: true

module SealedTrail
  # Captures the actor, request id and remote IP for every request.
  #
  # Included automatically into ActionController::Base and ActionController::API
  # (set config.auto_include_controller = false to include it yourself).
  #
  # The actor is resolved lazily by calling #sealed_trail_actor the first time
  # an entry is recorded, so it works with authentication that runs in a later
  # before_action. Override #sealed_trail_actor to customise it:
  #
  #   def sealed_trail_actor
  #     current_admin || current_user
  #   end
  module Controller
    extend ActiveSupport::Concern

    included do
      before_action :set_sealed_trail_context
    end

    private

    # The actor recorded for this request. By default calls the method named by
    # SealedTrail.config.actor_method (:current_user) when the controller has it.
    def sealed_trail_actor
      method_name = SealedTrail.config.actor_method
      send(method_name) if method_name && respond_to?(method_name, true)
    end

    # Extra metadata stored with every entry recorded in this request.
    # Override to add, e.g., { "user_agent" => request.user_agent }.
    def sealed_trail_metadata
      {}
    end

    def set_sealed_trail_context
      current = SealedTrail::Current
      current.request_id = request.request_id
      current.remote_ip = request.remote_ip
      current.actor_resolver = -> { sealed_trail_actor }
      metadata = sealed_trail_metadata
      current.metadata = (current.metadata || {}).merge(metadata.to_h.stringify_keys) if metadata.present?
    end
  end
end
