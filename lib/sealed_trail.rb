# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/module/attribute_accessors"
require "active_record"

require "sealed_trail/version"
require "sealed_trail/configuration"
require "sealed_trail/current"
require "sealed_trail/redactor"
require "sealed_trail/writer"
require "sealed_trail/recorder"
require "sealed_trail/model"
require "sealed_trail/bulk"
require "sealed_trail/controller"
require "sealed_trail/rake_context"

# SealedTrail records an audit trail of changes to Active Record models: what
# changed, who changed it, when, and from which request.
module SealedTrail
  REDACTED = "[REDACTED]"

  class Error < StandardError; end
  class ConfigurationError < Error; end

  autoload :Entry, "sealed_trail/entry"

  class << self
    # Global configuration. See SealedTrail::Configuration.
    def config
      @config ||= Configuration.new
    end

    # Yields the global configuration, typically from
    # config/initializers/sealed_trail.rb.
    def configure
      yield config
    end

    # Restores the default configuration. Mostly useful in tests.
    def reset_config!
      @config = Configuration.new
    end

    # Process-wide fallback actor label, set to "console" in rails console and
    # "rake:<task>" while a rake task runs.
    attr_accessor :process_actor_label

    # True unless tracking is switched off globally (config.enabled = false)
    # or for the current block (SealedTrail.without_tracking).
    def tracking?
      config.enabled && !Current.tracking_disabled
    end

    # Runs the block without recording any audit entries on the current
    # thread/fiber. Returns the block's value.
    def without_tracking(&)
      Current.set(tracking_disabled: true, &)
    end

    # Runs the block with tracking forced back on, even inside
    # without_tracking. Returns the block's value.
    def with_tracking(&)
      Current.set(tracking_disabled: false, &)
    end

    # Attributes every entry recorded inside the block to +actor+. The actor
    # can be an Active Record object (stored polymorphically) or a String or
    # Symbol label such as "system" or :nightly_import. Returns the block's
    # value.
    def with_actor(actor, &)
      Current.set(actor: actor, &)
    end

    # Merges +metadata+ into the metadata of every entry recorded inside the
    # block. Nested calls are merged. Returns the block's value.
    def with_metadata(metadata, &)
      merged = (Current.metadata || {}).merge(metadata.to_h.stringify_keys)
      Current.set(metadata: merged, &)
    end

    # The actor that will be recorded right now. In order: the explicit actor
    # (with_actor / Current.actor), the request's actor, the request or job
    # label ("anonymous", "job:<JobClass>"), the console/rake label, then
    # config.default_actor.
    def actor
      identified = Current.identified_actor
      return identified unless identified.nil?
      return Current.context_label if Current.context_label.present?
      return process_actor_label if config.detect_process_context && process_actor_label.present?

      default = config.default_actor
      default.respond_to?(:call) ? default.call : default
    end

    # The HMAC-SHA256 fingerprint stored by the :fingerprint redaction
    # strategy, e.g. "hmac:3f2a...". Use it to find entries for a value
    # without storing the value:
    #
    #   SealedTrail::Entry.with_fingerprint("jane@example.com")
    def fingerprint(value)
      return nil if value.nil?

      digest = OpenSSL::HMAC.hexdigest("SHA256", config.fingerprint_secret, Redactor.stringify(value))
      "hmac:#{digest}"
    end
  end
end

if defined?(Rails::Railtie)
  require "sealed_trail/railtie"
end
