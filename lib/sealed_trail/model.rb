# frozen_string_literal: true

module SealedTrail
  # Adds the +has_sealed_trail+ macro to Active Record models.
  module Model
    EVENTS = %i[create update destroy].freeze

    # Per-model settings built by has_sealed_trail.
    Options = Struct.new(:only, :ignore, :redact, :events, :meta, keyword_init: true)

    module ClassMethods
      # Records an audit entry after every create, update and destroy.
      #
      #   class Patient < ApplicationRecord
      #     has_sealed_trail ignore: [:last_seen_at], redact: [:ssn]
      #   end
      #
      # Options:
      # only::    record changes to these attributes only
      # ignore::  never record these attributes (an update touching only
      #           ignored attributes records nothing)
      # redact::  record that these attributes changed, but store their values
      #           as "[REDACTED]" (added to the global redaction rules)
      # on::      events to record, any of :create, :update, :destroy
      # meta::    Hash of extra metadata stored with each entry; values may be
      #           static, a Symbol (method called on the record) or a Proc
      #           (called with the record)
      # if/unless:: standard Active Record callback conditions
      #
      # Entries are written inside the same database transaction as the change,
      # so a rolled-back change leaves no entry and a failed entry rolls the
      # change back.
      def has_sealed_trail(only: nil, ignore: [], redact: [], on: EVENTS, meta: {}, **callback_options)
        if respond_to?(:sealed_trail_options) && sealed_trail_options
          raise ArgumentError, "has_sealed_trail is already declared on #{name}"
        end

        events = Array(on).map(&:to_sym)
        unknown = events - EVENTS
        raise ArgumentError, "Unknown has_sealed_trail event(s): #{unknown.join(", ")}" if unknown.any?

        unknown_options = callback_options.keys - %i[if unless]
        raise ArgumentError, "Unknown has_sealed_trail option(s): #{unknown_options.join(", ")}" if unknown_options.any?

        class_attribute :sealed_trail_options, instance_writer: false
        self.sealed_trail_options = Options.new(
          only: only && Array(only).map(&:to_s),
          ignore: Array(ignore).map(&:to_s),
          redact: Array(redact),
          events: events,
          meta: meta.to_h
        ).freeze

        has_many :audit_entries,
          -> { chronological },
          as: :item,
          class_name: "SealedTrail::Entry",
          inverse_of: false

        after_create(**callback_options) { SealedTrail::Recorder.new(self, :create).record } if events.include?(:create)
        after_update(**callback_options) { SealedTrail::Recorder.new(self, :update).record } if events.include?(:update)
        after_destroy(**callback_options) { SealedTrail::Recorder.new(self, :destroy).record } if events.include?(:destroy)
      end

      def sealed_trail?
        respond_to?(:sealed_trail_options) && sealed_trail_options.present?
      end
    end
  end
end
