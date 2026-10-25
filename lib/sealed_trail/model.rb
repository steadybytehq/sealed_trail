# frozen_string_literal: true

module SealedTrail
  # Adds the +has_sealed_trail+ macro to Active Record models.
  module Model
    EVENTS = %i[create update destroy].freeze
    OPTIONAL_EVENTS = %i[touch].freeze
    BULK_EVENTS = %w[bulk_update bulk_delete bulk_insert bulk_upsert].freeze
    ALL_EVENTS = (EVENTS + OPTIONAL_EVENTS).map(&:to_s) + BULK_EVENTS

    # Per-model settings built by has_sealed_trail.
    Options = Struct.new(:only, :ignore, :redact, :events, :meta, :bulk, keyword_init: true)

    module ClassMethods
      # Records an audit entry for every create, update and destroy.
      #
      #   class Patient < ApplicationRecord
      #     has_sealed_trail ignore: [:last_seen_at], redact: { ssn: :mask, email: :fingerprint }
      #   end
      #
      # Options:
      # only::    record changes to these attributes only
      # ignore::  never record these attributes (an update touching only
      #           ignored attributes records nothing)
      # redact::  attribute names/Regexps (Array), or a Hash of name/Regexp =>
      #           strategy (:redact, :fingerprint, :mask, a callable, or false
      #           to opt out of a global rule). Checked before the global rules.
      # on::      events to record: any of :create, :update, :destroy (default:
      #           all three) and :touch (opt-in)
      # meta::    Hash of extra metadata stored with each entry; values may be
      #           static, a Symbol (method called on the record) or a Proc
      #           (called with the record)
      # bulk::    record update_all/delete_all/insert_all/upsert_all summaries
      #           (default: true)
      # if/unless:: standard Active Record callback conditions (callbacks only)
      def has_sealed_trail(only: nil, ignore: [], redact: [], on: EVENTS, meta: {}, bulk: true, **callback_options)
        if respond_to?(:sealed_trail_options) && sealed_trail_options
          raise ArgumentError, "has_sealed_trail is already declared on #{name}"
        end

        events = Array(on).map(&:to_sym)
        unknown = events - EVENTS - OPTIONAL_EVENTS
        raise ArgumentError, "Unknown has_sealed_trail event(s): #{unknown.join(", ")}" if unknown.any?

        unknown_options = callback_options.keys - %i[if unless]
        raise ArgumentError, "Unknown has_sealed_trail option(s): #{unknown_options.join(", ")}" if unknown_options.any?

        Redactor.validate_rules!(redact)

        class_attribute :sealed_trail_options, instance_writer: false
        self.sealed_trail_options = Options.new(
          only: only && Array(only).map(&:to_s),
          ignore: Array(ignore).map(&:to_s),
          redact: redact.is_a?(Hash) ? redact : Array(redact),
          events: events,
          meta: meta.to_h,
          bulk: bulk
        ).freeze

        has_many :audit_entries,
          -> { chronological },
          as: :item,
          class_name: "SealedTrail::Entry",
          inverse_of: false

        prepend SealedTrail::Model::InstanceHooks
        singleton_class.prepend(SealedTrail::Bulk::InsertHooks) unless SealedTrail::Bulk.relation_inserts?

        after_create(**callback_options) { SealedTrail::Recorder.new(self, :create).record } if events.include?(:create)
        after_update(**callback_options) { SealedTrail::Recorder.new(self, :update).record } if events.include?(:update)
        after_destroy(**callback_options) { SealedTrail::Recorder.new(self, :destroy).record } if events.include?(:destroy)
      end

      def sealed_trail?
        respond_to?(:sealed_trail_options) && sealed_trail_options.present?
      end
    end

    # Records the persistence methods that skip callbacks: update_column(s)
    # and delete, plus touch when opted in with on: [:touch].
    module InstanceHooks
      def update_columns(attributes)
        return super unless sealed_trail_event?(:update)

        before = self.attributes
        result = super
        record_sealed_trail_diff(:update, before, "update_columns")
        result
      end

      def touch(*names, time: nil)
        return super unless sealed_trail_event?(:touch)

        before = attributes
        result = super
        record_sealed_trail_diff(:touch, before, "touch") if result
        result
      end

      def delete
        return super unless persisted? && sealed_trail_event?(:destroy)

        snapshot = attributes.compact.transform_values { |value| [ value, nil ] }
        result = super
        SealedTrail::Recorder.new(self, :destroy, changes: snapshot, via: "delete").record
        result
      end

      private

      def sealed_trail_event?(event)
        SealedTrail.tracking? && sealed_trail_options.events.include?(event)
      end

      def record_sealed_trail_diff(event, before, via)
        after = attributes
        changes = after.each_with_object({}) do |(name, value), result|
          result[name] = [ before[name], value ] unless before[name] == value
        end
        SealedTrail::Recorder.new(self, event, changes: changes, via: via).record
      end
    end
  end
end
