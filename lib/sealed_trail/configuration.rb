# frozen_string_literal: true

module SealedTrail
  # Global settings. Change them with:
  #
  #   SealedTrail.configure do |config|
  #     config.redact_attributes += [:ssn, { email: :fingerprint }]
  #   end
  class Configuration
    # Attribute names (Strings/Symbols, matched exactly) or Regexps whose
    # values are redacted with config.redaction_strategy. A Hash entry maps a
    # name or Regexp to its own strategy, e.g. { email: :fingerprint }.
    DEFAULT_REDACT_ATTRIBUTES = [
      /passw(or)?d/i,
      /token/i,
      /secret/i,
      /\Aencrypted_/i,
      /api_?key/i,
      /private_?key/i,
      /\Aotp_/i,
      /salt\z/i,
      /(\A|_)e?mail(_address)?\z/i,
      /(\A|_)phone(_number)?\z/i,
      /(\A|_)mobile(_number)?\z/i
    ].freeze

    ON_FAILURE_MODES = %i[log raise].freeze
    BULK_SQL_MODES = %i[masked full none].freeze

    # Switch all tracking off (for example in a seed task). Default: true.
    attr_accessor :enabled

    # Redaction rules applied to every tracked model, after the per-model
    # +redact:+ rules. Default: DEFAULT_REDACT_ATTRIBUTES.
    attr_accessor :redact_attributes

    # How redacted values are stored unless a rule names its own strategy:
    # :redact ("[REDACTED]"), :fingerprint ("hmac:<hex>"), :mask
    # ("j***@example.com", "******1234") or a callable(value, attribute_name).
    # Default: :redact.
    attr_accessor :redaction_strategy

    # Secret for the :fingerprint strategy and SealedTrail.fingerprint.
    # Default: derived from Rails' secret_key_base.
    attr_writer :fingerprint_secret

    # Also redact attributes declared with Rails' +encrypts+. Default: true.
    attr_accessor :redact_encrypted_attributes

    # Attributes never recorded in any model. Default: none.
    attr_accessor :ignore_attributes

    # What to do when an audit entry cannot be written:
    # :log (default) logs it, instruments "write_failed.sealed_trail", calls
    # error_handler and lets the user's save succeed; :raise re-raises so the
    # change is rolled back; a callable(error, payload) is called instead.
    attr_accessor :on_failure

    # Called with (error, payload) when a write fails in :log mode, e.g.
    #   config.error_handler = ->(error, payload) { Rails.error.report(error, context: payload) }
    attr_accessor :error_handler

    # Logger for write failures. Default: Rails.logger.
    attr_writer :logger

    # The controller method used to find the actor for a request. It is called
    # lazily, the first time an entry is recorded in that request.
    # Default: :current_user.
    attr_accessor :actor_method

    # Actor recorded in a request when the actor method returns nil.
    # Default: "anonymous". Set to nil to fall back to default_actor.
    attr_accessor :anonymous_actor

    # Actor recorded when nothing else identifies one (after the explicit
    # actor, the request, the job, and the console/rake context). A label, a
    # record, or a callable returning one. Default: "system".
    attr_accessor :default_actor

    # Label rake tasks ("rake:<task>") and the console ("console").
    # Default: true.
    attr_accessor :detect_process_context

    # Carry the actor, request id and metadata from where a job is enqueued
    # into the job, and label jobs "job:<JobClass>". Default: true.
    attr_accessor :active_job_integration

    # Automatically include SealedTrail::Controller into ActionController::Base
    # and ActionController::API. Default: true.
    attr_accessor :auto_include_controller

    # Record update_all, delete_all, insert_all, insert_all! and upsert_all on
    # tracked models as one summary entry per operation. Default: true.
    attr_accessor :track_bulk_operations

    # Maximum number of affected ids stored in a bulk entry (nil: no limit).
    # Default: 1000.
    attr_accessor :bulk_id_limit

    # How the WHERE/SET SQL of bulk operations is stored: :masked (quoted string
    # literals replaced with '?'), :full, or :none. Default: :masked.
    attr_accessor :bulk_sql

    def initialize
      @enabled = true
      @redact_attributes = DEFAULT_REDACT_ATTRIBUTES.dup
      @redaction_strategy = :redact
      @fingerprint_secret = nil
      @redact_encrypted_attributes = true
      @ignore_attributes = []
      @on_failure = :log
      @error_handler = nil
      @logger = nil
      @actor_method = :current_user
      @anonymous_actor = "anonymous"
      @default_actor = "system"
      @detect_process_context = true
      @active_job_integration = true
      @auto_include_controller = true
      @track_bulk_operations = true
      @bulk_id_limit = 1000
      @bulk_sql = :masked
    end

    def logger
      @logger || (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger) || ActiveRecord::Base.logger
    end

    def fingerprint_secret
      return @fingerprint_secret if @fingerprint_secret.present?

      if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        @derived_fingerprint_secret ||= Rails.application.key_generator.generate_key("sealed_trail/fingerprint", 32)
      else
        raise ConfigurationError, "Set SealedTrail.config.fingerprint_secret to use the :fingerprint strategy"
      end
    end
  end
end
