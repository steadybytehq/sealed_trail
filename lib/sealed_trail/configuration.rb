# frozen_string_literal: true

module SealedTrail
  # Global settings. Change them with:
  #
  #   SealedTrail.configure do |config|
  #     config.redact_attributes += [:ssn, /\Abank_/]
  #   end
  class Configuration
    # Attribute names (Strings/Symbols, matched exactly) or Regexps whose
    # values are always stored as "[REDACTED]".
    DEFAULT_REDACT_ATTRIBUTES = [
      /passw(or)?d/i,
      /token/i,
      /secret/i,
      /\Aencrypted_/i,
      /api_?key/i,
      /private_?key/i,
      /\Aotp_/i,
      /salt\z/i
    ].freeze

    # Switch all tracking off (for example in a seed task). Default: true.
    attr_accessor :enabled

    # Attributes to redact in every tracked model, in addition to the
    # per-model +redact:+ option. Default: DEFAULT_REDACT_ATTRIBUTES.
    attr_accessor :redact_attributes

    # Also redact attributes declared with Rails' +encrypts+. Default: true.
    attr_accessor :redact_encrypted_attributes

    # Attributes never recorded in any model (they are still saved, just not
    # logged). Default: none.
    attr_accessor :ignore_attributes

    # The controller method used to find the actor for a request. It is called
    # lazily, the first time an entry is recorded in that request, so it works
    # with authentication that runs in a later before_action.
    # Default: :current_user.
    attr_accessor :actor_method

    # Automatically include SealedTrail::Controller into ActionController::Base
    # and ActionController::API. Default: true.
    attr_accessor :auto_include_controller

    def initialize
      @enabled = true
      @redact_attributes = DEFAULT_REDACT_ATTRIBUTES.dup
      @redact_encrypted_attributes = true
      @ignore_attributes = []
      @actor_method = :current_user
      @auto_include_controller = true
    end
  end
end
