# frozen_string_literal: true

require "test_helper"
require "rake"

class ActorFallbackTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @user = User.create!(name: "Ann") }
  teardown { SealedTrail.process_actor_label = nil }

  test "records config.default_actor ('system') when no actor is set" do
    Post.create!(title: "x")

    assert_nil last_entry.actor_type
    assert_equal "system", last_entry.actor_id
    assert_equal 1, SealedTrail::Entry.for_actor("system").count
  end

  test "default_actor can be a record, a callable or nil" do
    SealedTrail.config.default_actor = @user
    Post.create!(title: "a")
    assert_equal @user, last_entry.actor

    SealedTrail.config.default_actor = -> { "cron" }
    Post.create!(title: "b")
    assert_equal "cron", last_entry.actor_id

    SealedTrail.config.default_actor = nil
    Post.create!(title: "c")
    assert_nil last_entry.actor_id
  end

  test "labels entries 'console' in rails console" do
    SealedTrail::Railtie.instance.send(:run_console_blocks, Rails.application)
    Post.create!(title: "from console")

    assert_equal "console", last_entry.actor_id
  end

  test "an explicit actor still wins over the console label" do
    SealedTrail.process_actor_label = "console"
    SealedTrail.with_actor(@user) { Post.create!(title: "x") }

    assert_equal @user, last_entry.actor
  end

  test "labels entries 'rake:<task>' while a rake task runs" do
    SealedTrail::RakeContext.install!
    app = Rake::Application.new
    Rake.with_application(app) do
      Rake::Task.define_task("sealed_trail:demo") { Post.create!(title: "from rake") }
      Rake::Task["sealed_trail:demo"].invoke
    end

    assert_equal "rake:sealed_trail:demo", last_entry.actor_id
    assert_nil SealedTrail.process_actor_label, "the label is cleared when the task ends"
  end

  test "process labels can be switched off" do
    SealedTrail.config.detect_process_context = false
    SealedTrail.process_actor_label = "console"
    Post.create!(title: "x")

    assert_equal "system", last_entry.actor_id
  end

  test "jobs inherit the enqueuing actor, request id and metadata" do
    post = Post.create!(title: "Old")
    SealedTrail::Current.request_id = "req-job-1"
    SealedTrail.with_actor(@user) do
      SealedTrail.with_metadata(reason: "bulk rename") { RenamePostJob.perform_later(post.id, "New") }
    end
    SealedTrail::Current.reset

    perform_enqueued_jobs

    entry = last_entry
    assert_equal [ "Old", "New" ], entry.change_for(:title)
    assert_equal @user, entry.actor
    assert_equal "req-job-1", entry.request_id
    assert_equal({ "reason" => "bulk rename" }, entry.metadata)
  end

  test "jobs carry a label actor" do
    post = Post.create!(title: "Old")
    SealedTrail.with_actor("importer") { RenamePostJob.perform_later(post.id, "New") }

    perform_enqueued_jobs
    assert_equal "importer", last_entry.actor_id
  end

  test "jobs enqueued from a controller carry the signed-in user" do
    post = Post.create!(title: "Old")
    SealedTrail::Current.actor_resolver = -> { @user }
    RenamePostJob.perform_later(post.id, "New")
    SealedTrail::Current.reset

    perform_enqueued_jobs
    assert_equal @user, last_entry.actor
  end

  test "jobs without an enqueuing actor are labelled job:<JobClass>" do
    post = Post.create!(title: "Old")
    RenamePostJob.perform_later(post.id, "New")

    perform_enqueued_jobs
    assert_equal "job:RenamePostJob", last_entry.actor_id
  end

  test "perform_now keeps the caller's actor" do
    post = Post.create!(title: "Old")
    SealedTrail.with_actor(@user) { RenamePostJob.perform_now(post.id, "New") }

    assert_equal @user, last_entry.actor
  end

  test "a deleted actor is recorded by its GlobalID" do
    post = Post.create!(title: "Old")
    gone = User.create!(name: "Gone")
    SealedTrail.with_actor(gone) { RenamePostJob.perform_later(post.id, "New") }
    gone.destroy!

    perform_enqueued_jobs
    assert_equal "gid://dummy/User/#{gone.id}", last_entry.actor_id
  end

  test "the job integration can be switched off" do
    SealedTrail.config.active_job_integration = false
    post = Post.create!(title: "Old")
    SealedTrail.with_actor(@user) { RenamePostJob.perform_later(post.id, "New") }

    assert_nil enqueued_jobs.last["sealed_trail"]
    perform_enqueued_jobs
    assert_equal "system", last_entry.actor_id
  end
end
