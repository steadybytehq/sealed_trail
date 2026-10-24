# frozen_string_literal: true

require "test_helper"

class ControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.create!(name: "Ann") }

  test "records the current_user, request id and remote IP" do
    post "/posts", params: { title: "Hi" },
      headers: { "X-User-Id" => @user.id.to_s, "X-Request-Id" => "req-abc-123", "REMOTE_ADDR" => "203.0.113.7" }

    assert_response :success
    entry = last_entry
    assert_equal @user, entry.actor
    assert_equal "req-abc-123", entry.request_id
    assert_equal "203.0.113.7", entry.remote_ip
  end

  test "records update and destroy from controllers" do
    record = Post.create!(title: "Old")

    patch "/posts/#{record.id}", params: { title: "New" }, headers: { "X-User-Id" => @user.id.to_s }
    assert_equal [ "Old", "New" ], last_entry.change_for(:title)
    assert_equal @user, last_entry.actor

    delete "/posts/#{record.id}", headers: { "X-User-Id" => @user.id.to_s }
    assert_equal "destroy", last_entry.event
    assert_equal @user, last_entry.actor
  end

  test "records no actor when nobody is signed in, but still the request" do
    post "/posts", params: { title: "Anon" }

    assert_nil last_entry.actor_id
    assert_not_nil last_entry.request_id
    assert_equal "127.0.0.1", last_entry.remote_ip
  end

  test "resolves the actor lazily, after later before_actions have run (ActionController::API)" do
    post "/api/posts", params: { title: "From API" }, headers: { "X-Api-User" => "Ann" }

    assert_response :success
    assert_equal @user, last_entry.actor
  end

  test "sealed_trail_actor and sealed_trail_metadata can be overridden" do
    post "/admin/posts", params: { title: "Admin" }, headers: { "X-Admin" => "root", "User-Agent" => "AuditBot/1.0" }

    assert_nil last_entry.actor_type
    assert_equal "admin:root", last_entry.actor_id
    assert_equal({ "user_agent" => "AuditBot/1.0" }, last_entry.metadata)
  end

  test "request context does not leak into the next request or outside requests" do
    post "/posts", params: { title: "One" }, headers: { "X-User-Id" => @user.id.to_s, "X-Request-Id" => "req-1" }
    post "/posts", params: { title: "Two" }, headers: { "X-Request-Id" => "req-2" }

    assert_nil last_entry.actor_id
    assert_equal "req-2", last_entry.request_id

    Post.create!(title: "Console")
    assert_nil last_entry.request_id
    assert_nil last_entry.actor_id
  end
end
