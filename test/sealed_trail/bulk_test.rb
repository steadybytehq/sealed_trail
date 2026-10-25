# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BulkTest < ActiveSupport::TestCase
  setup do
    @posts = %w[a b c].map { |title| Post.create!(title: title) }
    @user = User.create!(name: "Ann")
  end

  def mysql?
    ActiveRecord::Base.connection.adapter_name.match?(/mysql|trilogy/i)
  end

  test "update_all with a Hash records one bulk_update summary" do
    rows = SealedTrail.with_actor(@user) { Post.where(title: %w[a b]).update_all(status: "archived") }
    entry = last_entry

    assert_equal 2, rows
    assert_equal "bulk_update", entry.event
    assert_predicate entry, :bulk?
    assert_equal "Post", entry.item_type
    assert_equal "*", entry.item_id
    assert_equal({ "status" => [ nil, "archived" ] }, entry.object_changes)
    assert_equal @posts.first(2).map { |p| p.id.to_s }.sort, entry.bulk_ids.sort
    assert_equal "update_all", entry.bulk_summary["operation"]
    assert_equal 2, entry.bulk_summary["row_count"]
    assert_equal false, entry.bulk_summary["ids_truncated"]
    assert_match "title", entry.bulk_summary["where_sql"]
    assert_equal @user, entry.actor
  end

  test "update_all redacts values like any other change" do
    Account.create!(name: "Acme")
    Account.update_all(api_token: "tok_bulk", name: "Renamed")

    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:api_token)
    assert_equal [ nil, "Renamed" ], last_entry.change_for(:name)
  end

  test "update_all touching only ignored attributes records nothing" do
    Comment.create!(body: "x")

    assert_no_difference -> { SealedTrail::Entry.count } do
      Comment.update_all(likes: 5)
    end
  end

  test "update_all with SQL stores the SET clause with string literals masked" do
    Post.where(id: @posts.first.id).update_all([ "title = ?", "secret title" ])

    summary = last_entry.bulk_summary
    assert_nil last_entry.object_changes
    assert_match(/title = '\?'/, summary["set_sql"])
    assert_not_includes summary.to_json, "secret title"
  end

  test "bulk_sql can store full SQL or none" do
    SealedTrail.config.bulk_sql = :full
    Post.where(title: "a").update_all("views_count = views_count + 1")
    assert_match "'a'", last_entry.bulk_summary["where_sql"]
    assert_match "views_count + 1", last_entry.bulk_summary["set_sql"]

    SealedTrail.config.bulk_sql = :none
    Post.where(title: "a").update_all(status: "x")
    assert_nil last_entry.bulk_summary["where_sql"]
  end

  test "where_sql is masked by default" do
    Post.where(title: "b").update_all(status: "x")

    assert_match(/'\?'/, last_entry.bulk_summary["where_sql"])
    assert_no_match(/'b'/, last_entry.bulk_summary["where_sql"])
  end

  test "delete_all records a bulk_delete summary with the deleted ids" do
    ids = @posts.first(2).map(&:id)
    rows = Post.where(id: ids).delete_all

    assert_equal 2, rows
    assert_equal "bulk_delete", last_entry.event
    assert_equal ids.map(&:to_s).sort, last_entry.bulk_ids.sort
    assert_equal 2, last_entry.bulk_summary["row_count"]
    assert_nil last_entry.object_changes
  end

  test "Model.delete(id) is recorded as a bulk_delete" do
    Post.delete(@posts.last.id)

    assert_equal "bulk_delete", last_entry.event
    assert_equal [ @posts.last.id.to_s ], last_entry.bulk_ids
  end

  test "ids are capped by bulk_id_limit with a truncated flag and the full row count" do
    SealedTrail.config.bulk_id_limit = 2
    Post.update_all(status: "capped")

    summary = last_entry.bulk_summary
    assert_equal 2, summary["ids"].size
    assert_equal true, summary["ids_truncated"]
    assert_equal 3, summary["row_count"]
  end

  test "insert_all records a bulk_insert summary" do
    result = Post.insert_all([ { title: "x", body: "1" }, { title: "y", body: "2" } ])
    summary = last_entry.bulk_summary

    assert_equal "bulk_insert", last_entry.event
    assert_equal "insert_all", summary["operation"]
    assert_equal 2, summary["attempted_count"]
    assert_equal %w[body title], summary["columns"]

    if mysql?
      assert_nil summary["ids"], "MySQL does not return inserted ids"
    else
      assert_equal result.rows.flatten.map(&:to_s).sort, summary["ids"].sort
      assert_equal 2, summary["row_count"]
    end
  end

  test "insert_all!, insert and upsert_all are recorded" do
    Post.insert_all!([ { title: "bang" } ])
    assert_equal [ "bulk_insert", "insert_all!" ], [ last_entry.event, last_entry.bulk_summary["operation"] ]

    Post.insert({ title: "single" })
    assert_equal "bulk_insert", last_entry.event

    Post.upsert_all([ { id: @posts.first.id, title: "upserted" } ])
    assert_equal [ "bulk_upsert", "upsert_all" ], [ last_entry.event, last_entry.bulk_summary["operation"] ]
    assert_equal "upserted", @posts.first.reload.title
  end

  test "update_counters (counter caches, increment_counter) are recorded as bulk updates" do
    Post.increment_counter(:views_count, @posts.first.id)

    assert_equal "bulk_update", last_entry.event
    assert_equal [ @posts.first.id.to_s ], last_entry.bulk_ids
    assert_includes last_entry.changed_attribute_names, "views_count"
  end

  test "untracked models and without_tracking record nothing" do
    assert_no_difference -> { SealedTrail::Entry.count } do
      User.update_all(name: "x")
      User.insert_all([ { name: "y" } ])
      SealedTrail.without_tracking do
        Post.update_all(status: "quiet")
        Post.insert_all([ { title: "quiet" } ])
        Post.where(title: "quiet").delete_all
      end
    end
  end

  test "bulk tracking can be switched off globally or per model" do
    SealedTrail.config.track_bulk_operations = false
    assert_no_difference -> { SealedTrail::Entry.count } do
      Post.update_all(status: "x")
    end

    SealedTrail.config.track_bulk_operations = true
    Invoice.create!(number: "I-1", amount_cents: 1)
    assert_no_difference -> { SealedTrail::Entry.count } do
      Invoice.update_all(amount_cents: 2)
    end
  end

  test "bulk writes respect the failure mode" do
    SealedTrail.config.logger = Logger.new(nil)
    SealedTrail::Entry.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      assert_equal 3, Post.update_all(status: "logged")

      SealedTrail.config.on_failure = :raise
      assert_raises(ActiveRecord::RecordInvalid) { Post.update_all(status: "raised") }
    end
  end

  test "Entry.bulk and Entry.affecting find bulk operations for a record" do
    target = @posts[1]
    Post.where(id: target.id).update_all(status: "hit")
    Post.where(id: @posts[0].id).update_all(status: "miss")

    assert_equal 2, SealedTrail::Entry.bulk.count
    assert_equal %w[create bulk_update], SealedTrail::Entry.affecting(target).chronological.pluck(:event)
    assert_equal 2, SealedTrail::Entry.affecting(Post, target.id).count
    assert_equal 1, SealedTrail::Entry.for_item(target).count
  end

  test "STI bulk operations use the base class as item_type" do
    Car.create!(name: "Beetle")
    Car.update_all(name: "Golf")

    assert_equal "Vehicle", last_entry.item_type
  end
end

class CallbackSkippingTest < ActiveSupport::TestCase
  test "update_columns and update_column record per-record update entries" do
    post = Post.create!(title: "Old", views_count: 1)
    post.update_columns(title: "New", views_count: 2)
    entry = last_entry

    assert_equal "update", entry.event
    assert_equal post.id.to_s, entry.item_id
    assert_equal({ "title" => [ "Old", "New" ], "views_count" => [ 1, 2 ] }, entry.object_changes)
    assert_equal "update_columns", entry.metadata["via"]

    post.update_column(:status, "published")
    assert_equal({ "status" => [ "draft", "published" ] }, last_entry.object_changes)
  end

  test "update_columns applies redaction and only/ignore" do
    account = Account.create!(name: "Acme", api_token: "a")
    account.update_columns(api_token: "b")
    assert_equal [ "[REDACTED]", "[REDACTED]" ], last_entry.change_for(:api_token)

    comment = Comment.create!(body: "x")
    assert_no_difference -> { SealedTrail::Entry.count } do
      comment.update_columns(likes: 9)
    end
  end

  test "delete records a destroy entry" do
    post = Post.create!(title: "Bye")
    post.delete

    assert_equal "destroy", last_entry.event
    assert_equal [ "Bye", nil ], last_entry.change_for(:title)
    assert_equal "delete", last_entry.metadata["via"]
  end

  test "touch is recorded only when opted in with on: [:touch]" do
    car = Car.create!(name: "Beetle")
    post = Post.create!(title: "x")

    travel 1.minute do
      assert_difference -> { SealedTrail::Entry.count }, 1 do
        car.touch
        post.touch
      end
    end

    assert_equal "touch", last_entry.event
    assert_equal car.id.to_s, last_entry.item_id
    assert_equal [ "updated_at" ], last_entry.changed_attribute_names
  end

  test "callback-skipping methods respect without_tracking" do
    post = Post.create!(title: "x")

    assert_no_difference -> { SealedTrail::Entry.count } do
      SealedTrail.without_tracking do
        post.update_columns(title: "y")
        post.delete
      end
    end
  end
end
