# frozen_string_literal: true

module SealedTrail
  # Saves entries, adding the actor and request context, and applies
  # config.on_failure when a write fails.
  module Writer
    FAILURE_EVENT = "write_failed.sealed_trail"

    module_function

    # Returns the saved Entry, or nil when the write failed and the failure was
    # handled (:log or a callable).
    def write(item_type:, item_id:, event:, object_changes: nil, metadata: nil)
      attributes = { item_type: item_type, item_id: item_id.to_s, event: event.to_s }

      begin
        actor_type, actor_id = actor_columns(SealedTrail.actor)
        attributes.merge!(
          object_changes: object_changes.presence&.as_json,
          metadata: (Current.metadata || {}).merge(metadata || {}).presence&.as_json,
          actor_type: actor_type,
          actor_id: actor_id,
          request_id: Current.request_id,
          remote_ip: Current.remote_ip
        )

        if SealedTrail.config.on_failure == :raise
          SealedTrail::Entry.create!(attributes)
        else
          # A savepoint, so a failed INSERT does not abort the caller's
          # transaction (PostgreSQL); still rolled back with it.
          SealedTrail::Entry.transaction(requires_new: true) { SealedTrail::Entry.create!(attributes) }
        end
      rescue StandardError => error
        handle_failure(error, attributes)
      end
    end

    def handle_failure(error, attributes)
      payload = { error: error, entry: attributes }
      ActiveSupport::Notifications.instrument(FAILURE_EVENT, payload)

      mode = SealedTrail.config.on_failure
      case mode
      when :raise
        raise error
      when :log
        log(error, attributes)
        notify_error_handler(error, payload)
      else
        raise ConfigurationError, "config.on_failure must be :log, :raise or a callable" unless mode.respond_to?(:call)

        mode.call(error, payload)
      end
      nil
    end

    def log(error, attributes)
      SealedTrail.config.logger&.error(
        "[SealedTrail] Failed to write audit entry for #{attributes[:item_type]}##{attributes[:item_id]} " \
        "(#{attributes[:event]}): #{error.class}: #{error.message}"
      )
    end

    def notify_error_handler(error, payload)
      SealedTrail.config.error_handler&.call(error, payload)
    rescue StandardError => handler_error
      SealedTrail.config.logger&.error("[SealedTrail] error_handler raised #{handler_error.class}: #{handler_error.message}")
    end

    def actor_columns(actor)
      case actor
      when nil then [ nil, nil ]
      when ActiveRecord::Base then [ actor.class.polymorphic_name, actor.id.to_s ]
      else [ nil, actor.to_s ]
      end
    end
  end
end
