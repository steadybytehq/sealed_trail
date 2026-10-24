# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/sealed_trail/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests SealedTrail::Generators::InstallGenerator
  destination File.expand_path("../tmp/generator", __dir__)
  setup :prepare_destination

  test "creates the migration with indexes and the current migration version" do
    run_generator

    assert_migration "db/migrate/create_sealed_trail_entries.rb" do |migration|
      assert_match "ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]", migration
      assert_match "create_table :sealed_trail_entries", migration
      assert_match "t.string :item_id, null: false", migration
      assert_match "index_sealed_trail_entries_on_item", migration
      assert_match "index_sealed_trail_entries_on_actor", migration
    end
  end

  test "uses jsonb on PostgreSQL and json elsewhere" do
    run_generator
    expected = ActiveRecord::Base.connection.adapter_name.match?(/postg/i) ? "jsonb" : "json"

    assert_migration "db/migrate/create_sealed_trail_entries.rb", /t\.#{expected} :object_changes/
  end

  test "the column type can be chosen" do
    run_generator %w[--json-type=jsonb]

    assert_migration "db/migrate/create_sealed_trail_entries.rb", /t\.jsonb :metadata/
  end

  test "creates the initializer" do
    run_generator

    assert_file "config/initializers/sealed_trail.rb", /SealedTrail\.configure do \|config\|/
  end
end
