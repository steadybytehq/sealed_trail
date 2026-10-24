# frozen_string_literal: true

require "test_helper"

class ContextTest < ActiveSupport::TestCase
  setup { @user = User.create!(name: "Ann") }

  test "with_actor attributes entries to an Active Record actor" do
    result = SealedTrail.with_actor(@user) { Post.create!(title: "x") && :done }

    assert_equal :done, result
    assert_equal "User", last_entry.actor_type
    assert_equal @user.id.to_s, last_entry.actor_id
    assert_equal @user, last_entry.actor
  end

  test "with_actor accepts a string or symbol label" do
    SealedTrail.with_actor(:nightly_import) { Post.create!(title: "x") }

    assert_nil last_entry.actor_type
    assert_equal "nightly_import", last_entry.actor_id
    assert_nil last_entry.actor
  end

  test "with_actor restores the previous actor afterwards, including when nested" do
    other = User.create!(name: "Bob")

    SealedTrail.with_actor(@user) do
      SealedTrail.with_actor(other) { Post.create!(title: "inner") }
      assert_equal other.id.to_s, last_entry.actor_id

      Post.create!(title: "outer")
      assert_equal @user.id.to_s, last_entry.actor_id
    end

    assert_nil SealedTrail.actor
    Post.create!(title: "none")
    assert_nil last_entry.actor_id
  end

  test "with_actor restores the previous actor when the block raises" do
    assert_raises(RuntimeError) { SealedTrail.with_actor(@user) { raise "boom" } }
    assert_nil SealedTrail.actor
  end

  test "an explicit actor wins over a lazily resolved one" do
    SealedTrail::Current.actor_resolver = -> { "resolver" }
    Post.create!(title: "a")
    assert_equal "resolver", last_entry.actor_id

    SealedTrail.with_actor(@user) { Post.create!(title: "b") }
    assert_equal @user.id.to_s, last_entry.actor_id
  end

  test "SealedTrail::Current.actor can be assigned directly" do
    SealedTrail::Current.actor = @user
    Post.create!(title: "x")

    assert_equal @user, last_entry.actor
  end

  test "without_tracking records nothing inside the block" do
    post = Post.create!(title: "x")

    assert_no_difference -> { SealedTrail::Entry.count } do
      value = SealedTrail.without_tracking do
        post.update!(title: "y")
        Post.create!(title: "z").destroy!
        :ok
      end
      assert_equal :ok, value
    end

    assert_difference -> { SealedTrail::Entry.count }, 1 do
      post.update!(title: "tracked again")
    end
  end

  test "with_tracking re-enables tracking inside without_tracking" do
    SealedTrail.without_tracking do
      assert_difference -> { SealedTrail::Entry.count }, 1 do
        SealedTrail.with_tracking { Post.create!(title: "x") }
      end
    end
  end

  test "config.enabled = false switches tracking off globally" do
    SealedTrail.configure { |config| config.enabled = false }

    assert_no_difference -> { SealedTrail::Entry.count } do
      Post.create!(title: "x")
    end
    assert_not SealedTrail.tracking?
  end

  test "with_metadata adds metadata, merged when nested and with model meta" do
    SealedTrail.with_metadata(reason: "support ticket 42") do
      SealedTrail.with_metadata("channel" => "console") { Post.create!(title: "x") }
      assert_equal({ "reason" => "support ticket 42", "channel" => "console" }, last_entry.metadata)

      Invoice.create!(number: "INV-9", amount_cents: 100)
      assert_equal "support ticket 42", last_entry.metadata["reason"]
      assert_equal "INV-9", last_entry.metadata["number"]
    end

    Post.create!(title: "y")
    assert_nil last_entry.metadata
  end

  test "context is isolated between threads" do
    SealedTrail.with_actor(@user) do
      seen_in_thread = Thread.new { SealedTrail.actor }.value
      assert_nil seen_in_thread
      assert_equal @user, SealedTrail.actor
    end

    thread_actor = Thread.new { SealedTrail.with_actor("worker") { SealedTrail.actor } }.value
    assert_equal "worker", thread_actor
    assert_nil SealedTrail.actor
  end

  test "context is isolated between fibers when isolation_level is :fiber" do
    previous = ActiveSupport::IsolatedExecutionState.isolation_level
    ActiveSupport::IsolatedExecutionState.isolation_level = :fiber

    SealedTrail.with_actor("outer") do
      assert_nil Fiber.new { SealedTrail.actor }.resume
      assert_equal "outer", SealedTrail.actor
    end
  ensure
    ActiveSupport::IsolatedExecutionState.isolation_level = previous
  end

  test "without_tracking is isolated between threads" do
    SealedTrail.without_tracking do
      assert Thread.new { SealedTrail.tracking? }.value
      assert_not SealedTrail.tracking?
    end
  end
end
