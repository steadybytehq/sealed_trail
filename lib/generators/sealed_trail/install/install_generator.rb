# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module SealedTrail
  module Generators
    # rails generate sealed_trail:install
    #
    # Creates the sealed_trail_entries migration and an initializer.
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :json_type,
        type: :string,
        enum: %w[json jsonb],
        desc: "Column type for object_changes and metadata (default: jsonb on PostgreSQL, json otherwise)"

      desc "Creates the SealedTrail migration and initializer."

      def create_migration_file
        migration_template "create_sealed_trail_entries.rb.tt", "db/migrate/create_sealed_trail_entries.rb"
      end

      def create_initializer
        template "sealed_trail.rb.tt", "config/initializers/sealed_trail.rb"
      end

      private

      def json_type
        options[:json_type] || (postgresql? ? "jsonb" : "json")
      end

      def postgresql?
        ActiveRecord::Base.connection_db_config&.adapter.to_s.match?(/postg/i)
      rescue StandardError
        false
      end

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
