# frozen_string_literal: true

require "test_helper"

class SealedTrailTest < ActiveSupport::TestCase
  test "has a version number" do
    assert_match(/\A\d+\.\d+\.\d+/, SealedTrail::VERSION)
  end

  test "the entries table has the expected JSON column type" do
    expected = ActiveRecord::Base.connection.adapter_name.match?(/postg/i) ? :jsonb : :json
    column = SealedTrail::Entry.columns_hash["object_changes"]

    assert_equal expected, column.type
  end

  test "the controller concern is included automatically" do
    assert_includes ActionController::Base.ancestors, SealedTrail::Controller
    assert_includes ActionController::API.ancestors, SealedTrail::Controller
  end

  test "configure yields the configuration and reset_config! restores defaults" do
    SealedTrail.configure { |config| config.actor_method = :current_admin }
    assert_equal :current_admin, SealedTrail.config.actor_method

    SealedTrail.reset_config!
    assert_equal :current_user, SealedTrail.config.actor_method
  end
end
