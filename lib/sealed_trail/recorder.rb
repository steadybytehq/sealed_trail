# frozen_string_literal: true

module SealedTrail
  # Builds and saves one Entry for one record event.
  class Recorder
    # +changes+ overrides the changes read from the record (used for
    # update_columns, touch and delete); +via+ is stored in the metadata.
    def initialize(record, event, changes: nil, via: nil)
      @record = record
      @event = event.to_sym
      @options = record.class.sealed_trail_options
      @changes = changes
      @via = via
    end

    # Returns the saved Entry, or nil when nothing was recorded.
    def record
      return unless SealedTrail.tracking?

      changes = AttributeFilter.new(@record.class).call(raw_changes)
      return if %i[update touch].include?(@event) && changes.empty?

      Writer.write(
        item_type: @record.class.polymorphic_name,
        item_id: @record.id,
        event: @event,
        object_changes: changes,
        metadata: metadata
      )
    end

    private

    def raw_changes
      return @changes if @changes

      case @event
      when :create then @record.attributes.compact.transform_values { |value| [ nil, value ] }
      when :update then @record.saved_changes
      when :destroy then @record.attributes.compact.transform_values { |value| [ value, nil ] }
      end
    end

    def metadata
      model_meta = @options.meta.to_h do |key, value|
        [ key.to_s, resolve_meta(value) ]
      end
      model_meta["via"] = @via if @via
      model_meta
    end

    def resolve_meta(value)
      case value
      when Proc then value.arity.zero? ? @record.instance_exec(&value) : value.call(@record)
      when Symbol then @record.public_send(value)
      else value
      end
    end
  end

  # Applies a model's only/ignore and redaction rules to a changes hash of
  # {"attribute" => [before, after]}.
  class AttributeFilter
    def initialize(model)
      @model = model
      @options = model.sealed_trail_options
    end

    def call(changes)
      redactor = self.redactor
      changes.each_with_object({}) do |(name, values), result|
        name = name.to_s
        next unless tracked?(name)

        result[name] = values.map { |value| redactor.apply(name, value) }
      end
    end

    def tracked?(name)
      name = name.to_s
      return false if @options.only && !@options.only.include?(name)
      return false if @options.ignore.include?(name)

      !SealedTrail.config.ignore_attributes.map(&:to_s).include?(name)
    end

    def redactor
      global = Array(SealedTrail.config.redact_attributes)
      if SealedTrail.config.redact_encrypted_attributes && @model.respond_to?(:encrypted_attributes)
        global += Array(@model.encrypted_attributes).map(&:to_s)
      end
      Redactor.new(@options.redact, global)
    end
  end
end
