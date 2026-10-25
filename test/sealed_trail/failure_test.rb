# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class FailureTest < ActiveSupport::TestCase
  setup do
    @log = StringIO.new
    SealedTrail.config.logger = Logger.new(@log)
  end

  # Makes the audit INSERT fail inside the database (NOT NULL violation), which
  # aborts the surrounding transaction on PostgreSQL unless a savepoint is used.
  def with_failing_writes(&)
    failing = ->(*) { SealedTrail::Entry.connection.execute("INSERT INTO sealed_trail_entries (item_type) VALUES (NULL)") }
    SealedTrail::Entry.stub(:create!, failing, &)
  end

  test "defaults to :log" do
    assert_equal :log, SealedTrail.config.on_failure
  end

  test ":log lets the save succeed and logs the error" do
    post = with_failing_writes { Post.create!(title: "Saved anyway") }

    assert post.persisted?
    assert Post.exists?(post.id)
    assert_equal 0, SealedTrail::Entry.count
    assert_match "[SealedTrail] Failed to write audit entry for Post##{post.id} (create)", @log.string
  end

  test ":log keeps the outer transaction usable after a database error" do
    Post.transaction do
      with_failing_writes { Post.create!(title: "First") }
      Post.create!(title: "Second")
    end

    assert_equal 2, Post.where(title: %w[First Second]).count
    assert_equal [ "Second" ], SealedTrail::Entry.all.map { |e| e.change_for(:title).last }
  end

  test ":log instruments write_failed.sealed_trail with the error and entry" do
    events = []
    callback = ->(*args) { events << ActiveSupport::Notifications::Event.new(*args) }

    ActiveSupport::Notifications.subscribed(callback, "write_failed.sealed_trail") do
      with_failing_writes { Post.create!(title: "x") }
    end

    assert_equal 1, events.size
    payload = events.first.payload
    assert_kind_of ActiveRecord::ActiveRecordError, payload[:error]
    assert_equal "Post", payload[:entry][:item_type]
    assert_equal "create", payload[:entry][:event]
  end

  test ":log calls the error_handler, and survives one that raises" do
    calls = []
    SealedTrail.config.error_handler = ->(error, payload) { calls << [ error, payload ] }
    with_failing_writes { Post.create!(title: "x") }

    assert_equal 1, calls.size
    assert_equal "Post", calls.first.last[:entry][:item_type]

    SealedTrail.config.error_handler = ->(*) { raise "handler down" }
    assert with_failing_writes { Post.create!(title: "y") }.persisted?
    assert_match "error_handler raised RuntimeError: handler down", @log.string
  end

  test ":log handles validation failures too" do
    SealedTrail::Entry.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      assert Post.create!(title: "x").persisted?
    end
  end

  test "entries are still rolled back with the outer transaction in :log mode" do
    assert_no_difference -> { SealedTrail::Entry.count } do
      ActiveRecord::Base.transaction(requires_new: true) do
        Post.create!(title: "Nope")
        raise ActiveRecord::Rollback
      end
    end
  end

  test ":raise rolls the change back" do
    SealedTrail.config.on_failure = :raise

    assert_no_difference -> { Post.count } do
      assert_raises(ActiveRecord::ActiveRecordError) do
        ActiveRecord::Base.transaction(requires_new: true) do
          with_failing_writes { Post.create!(title: "Rolled back") }
        end
      end
    end
  end

  test ":raise still instruments the failure" do
    SealedTrail.config.on_failure = :raise
    count = 0
    ActiveSupport::Notifications.subscribed(->(*) { count += 1 }, "write_failed.sealed_trail") do
      assert_raises(ActiveRecord::RecordInvalid) do
        SealedTrail::Entry.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) { Post.create!(title: "x") }
      end
    end
    assert_equal 1, count
  end

  test "a callable on_failure is called instead of logging" do
    received = nil
    SealedTrail.config.on_failure = ->(error, payload) { received = [ error, payload ] }
    post = with_failing_writes { Post.create!(title: "x") }

    assert post.persisted?
    assert_kind_of ActiveRecord::ActiveRecordError, received.first
    assert_equal post.id.to_s, received.last[:entry][:item_id]
    assert_empty @log.string
  end

  test "a callable on_failure can raise to block the save" do
    SealedTrail.config.on_failure = ->(error, _payload) { raise error }

    assert_raises(ActiveRecord::ActiveRecordError) do
      ActiveRecord::Base.transaction(requires_new: true) do
        with_failing_writes { Post.create!(title: "x") }
      end
    end
  end

  test "an invalid on_failure setting raises a configuration error" do
    SealedTrail.config.on_failure = :ignore

    assert_raises(SealedTrail::ConfigurationError) do
      with_failing_writes { Post.create!(title: "x") }
    end
  end
end
