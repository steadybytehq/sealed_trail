# frozen_string_literal: true

module SealedTrail
  # Builds and saves one Entry for one model event.
  class Recorder
    def initialize(record, event)
      @record = record
      @event = event.to_sym
      @options = record.class.sealed_trail_options
    end

    # Returns the saved Entry, or nil when nothing was recorded.
    def record
      return unless SealedTrail.tracking?

      changes = tracked_changes
      return if @event == :update && changes.empty?

      actor_type, actor_id = actor_columns(SealedTrail.actor)

      SealedTrail::Entry.create!(
        item_type: @record.class.polymorphic_name,
        item_id: @record.id.to_s,
        event: @event.to_s,
        object_changes: redact(changes).as_json,
        metadata: metadata.presence&.as_json,
        actor_type: actor_type,
        actor_id: actor_id,
        request_id: Current.request_id,
        remote_ip: Current.remote_ip
      )
    end

    private

    def tracked_changes
      raw =
        case @event
        when :create then @record.attributes.compact.transform_values { |value| [ nil, value ] }
        when :update then @record.saved_changes
        when :destroy then @record.attributes.compact.transform_values { |value| [ value, nil ] }
        end

      raw.select { |name, _| tracked_attribute?(name) }
    end

    def tracked_attribute?(name)
      return false if @options.only && !@options.only.include?(name)
      return false if @options.ignore.include?(name)

      !SealedTrail.config.ignore_attributes.map(&:to_s).include?(name)
    end

    def redact(changes)
      redactor = Redactor.new(redaction_rules)
      changes.to_h do |name, (before, after)|
        if redactor.redact?(name)
          [ name, [ Redactor.mask(before), Redactor.mask(after) ] ]
        else
          [ name, [ before, after ] ]
        end
      end
    end

    def redaction_rules
      rules = SealedTrail.config.redact_attributes + @options.redact
      if SealedTrail.config.redact_encrypted_attributes && @record.class.respond_to?(:encrypted_attributes)
        rules += Array(@record.class.encrypted_attributes).map(&:to_s)
      end
      rules
    end

    def metadata
      model_meta = @options.meta.to_h do |key, value|
        [ key.to_s, resolve_meta(value) ]
      end
      (Current.metadata || {}).merge(model_meta)
    end

    def resolve_meta(value)
      case value
      when Proc then value.arity.zero? ? @record.instance_exec(&value) : value.call(@record)
      when Symbol then @record.public_send(value)
      else value
      end
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
