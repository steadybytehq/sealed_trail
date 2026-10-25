# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["DB"] ||= "sqlite3"

require_relative "dummy/config/environment"
require "erb"

ActiveRecord::Migration.verbose = false

# Build the schema: the dummy app's tables, plus sealed_trail_entries created by
# the exact migration template the install generator ships.
module SealedTrailTestSchema
  TEMPLATE = File.expand_path("../lib/generators/sealed_trail/install/templates/create_sealed_trail_entries.rb.tt", __dir__)

  def self.json_type
    ActiveRecord::Base.connection.adapter_name.match?(/postg/i) ? "jsonb" : "json"
  end

  def self.migration_version
    "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
  end

  def self.load!
    load File.expand_path("dummy/db/schema.rb", __dir__)
    connection = ActiveRecord::Base.connection
    connection.drop_table(:sealed_trail_entries, if_exists: true)
    source = ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding)
    Object.send(:remove_const, :CreateSealedTrailEntries) if defined?(CreateSealedTrailEntries)
    eval(source, TOPLEVEL_BINDING, TEMPLATE) # rubocop:disable Security/Eval
    CreateSealedTrailEntries.migrate(:up)
    SealedTrail::Entry.reset_column_information
  end
end

if %w[postgresql mysql2 trilogy].include?(ENV["DB"])
  begin
    ActiveRecord::Base.connection.verify!
  rescue ActiveRecord::NoDatabaseError
    ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.connection_db_config)
  end
end

SealedTrailTestSchema.load!

require "rails/test_help"

puts "SealedTrail #{SealedTrail::VERSION} | Ruby #{RUBY_VERSION} | Rails #{Rails.version} | " \
     "#{ActiveRecord::Base.connection.adapter_name} (#{SealedTrailTestSchema.json_type})"

module SealedTrailTestHelpers
  def teardown
    SealedTrail.reset_config!
    SealedTrail::Current.reset
    super
  end

  def last_entry
    SealedTrail::Entry.order(:id).last
  end
end

class ActiveSupport::TestCase
  include SealedTrailTestHelpers
end

class ActionDispatch::IntegrationTest
  include SealedTrailTestHelpers
end
