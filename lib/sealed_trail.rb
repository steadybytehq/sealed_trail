# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/module/attribute_accessors"
require "active_record"

require "sealed_trail/version"
require "sealed_trail/configuration"
require "sealed_trail/current"
require "sealed_trail/redactor"
require "sealed_trail/recorder"
require "sealed_trail/model"
require "sealed_trail/controller"

# SealedTrail records an audit trail of create, update and destroy events on
# Active Record models: what changed, who changed it, when, and from which
# request.
module SealedTrail
  REDACTED = "[REDACTED]"

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

    # The actor that will be recorded right now, if any.
    def actor
      Current.resolved_actor
    end
  end
end

require "sealed_trail/railtie" if defined?(Rails::Railtie)
