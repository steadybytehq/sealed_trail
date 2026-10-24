# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "sealed_trail"

module Dummy
  class Application < Rails::Application
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "sealed_trail_dummy_secret_key_base_for_tests_only"
    config.hosts.clear
    config.active_support.deprecation = :stderr
    config.action_controller.allow_forgery_protection = false
    config.active_record.maintain_test_schema = false

    config.active_record.encryption.primary_key = "test-primary-key-for-sealed-trail"
    config.active_record.encryption.deterministic_key = "test-deterministic-key-for-sealed-trail"
    config.active_record.encryption.key_derivation_salt = "test-key-derivation-salt-for-sealed-trail"
  end
end
