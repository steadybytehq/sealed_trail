# frozen_string_literal: true

require "test_helper"

class ModelTest < ActiveSupport::TestCase
  test "records a create with every non-nil attribute as [nil, value]" do
    post = Post.create!(title: "Hello", body: "World")
    entry = last_entry

    assert_equal "create", entry.event
    assert_predicate entry, :create?
    assert_equal "Post", entry.item_type
    assert_equal post.id.to_s, entry.item_id
    assert_equal [ nil, "Hello" ], entry.change_for(:title)
    assert_equal [ nil, "World" ], entry.change_for(:body)
    assert_equal [ nil, "draft" ], entry.change_for(:status)
    assert_equal [ nil, post.id ], entry.change_for(:id)
    assert_nil entry.change_for(:user_id), "nil attributes are left out of a create"
    assert_not_nil entry.created_at
  end

  test "records an update with only the changed attributes" do
    post = Post.create!(title: "Hello")
    post.update!(title: "Hi", status: "published")
    entry = last_entry

    assert_equal "update", entry.event
    assert_equal [ "Hello", "Hi" ], entry.change_for(:title)
    assert_equal [ "draft", "published" ], entry.change_for(:status)
    assert_nil entry.change_for(:body)
    assert_includes entry.changed_attribute_names, "updated_at"
  end

  test "does not record a save without changes" do
    post = Post.create!(title: "Hello")

    assert_no_difference -> { SealedTrail::Entry.count } do
      post.save!
      post.update!(title: "Hello")
    end
  end

  test "records a destroy with the final values as [value, nil]" do
    post = Post.create!(title: "Bye")
    id = post.id
    post.destroy!
    entry = last_entry

    assert_equal "destroy", entry.event
    assert_predicate entry, :destroy?
    assert_equal id.to_s, entry.item_id
    assert_equal [ "Bye", nil ], entry.change_for(:title)
  end

  test "keeps entries after the record is destroyed" do
    post = Post.create!(title: "Bye")
    id = post.id
    post.destroy!

    assert_equal %w[create destroy], SealedTrail::Entry.for_item(Post, id).chronological.pluck(:event)
  end

  test "record.audit_entries returns the record's entries oldest first" do
    post = Post.create!(title: "v1")
    post.update!(title: "v2")
    post.update!(title: "v3")
    Post.create!(title: "other")

    assert_equal %w[create update update], post.audit_entries.map(&:event)
    assert_equal [ "v2", "v3" ], post.audit_entries.last.change_for(:title)
    assert_equal post, post.audit_entries.first.item
  end

  test "serialises values as JSON-friendly data" do
    post = Post.create!(title: "Hello", views_count: 3)
    entry = SealedTrail::Entry.find(last_entry.id)

    assert_equal [ nil, 3 ], entry.change_for(:views_count)
    assert_kind_of String, entry.change_for(:created_at).last
  end

  test "rolling back the change also rolls back the entry" do
    assert_no_difference -> { SealedTrail::Entry.count } do
      ActiveRecord::Base.transaction(requires_new: true) do
        Post.create!(title: "Nope")
        raise ActiveRecord::Rollback
      end
    end
  end

  test "only: records just the listed attributes" do
    article = Article.create!(title: "T", body: "B", slug: "t")

    assert_equal %w[body title], last_entry.changed_attribute_names.sort

    assert_no_difference -> { SealedTrail::Entry.count } do
      article.update!(slug: "new-slug")
    end

    article.update!(title: "T2", slug: "t2")
    assert_equal %w[title], last_entry.changed_attribute_names
  end

  test "ignore: leaves attributes out and skips updates that touch only them" do
    comment = Comment.create!(body: "Nice", likes: 1)

    assert_not_includes last_entry.changed_attribute_names, "likes"
    assert_not_includes last_entry.changed_attribute_names, "updated_at"

    assert_no_difference -> { SealedTrail::Entry.count } do
      comment.update!(likes: 2)
    end
  end

  test "config.ignore_attributes applies to every model" do
    SealedTrail.config.ignore_attributes = [ :updated_at, "created_at" ]
    post = Post.create!(title: "x")
    post.update!(title: "y")

    assert_equal %w[title], last_entry.changed_attribute_names
  end

  test "on: limits the recorded events" do
    invoice = Invoice.create!(number: "INV-1", amount_cents: 1000)

    assert_no_difference -> { SealedTrail::Entry.count } do
      invoice.update!(amount_cents: 2000)
    end

    invoice.destroy!
    assert_equal %w[create destroy], invoice.audit_entries.map(&:event)
  end

  test "if/unless: conditions are honoured" do
    assert_no_difference -> { SealedTrail::Entry.count } do
      Invoice.create!(number: "DRAFT", draft: true)
    end
  end

  test "meta: stores static, symbol and proc metadata" do
    Invoice.create!(number: "INV-7", amount_cents: 1250)

    assert_equal({ "source" => "billing", "number" => "INV-7", "amount" => 12.5 }, last_entry.metadata)
  end

  test "metadata is nil when there is none" do
    Post.create!(title: "x")

    assert_nil last_entry.metadata
  end

  test "STI records store the base class as item_type" do
    car = Car.create!(name: "Beetle")

    assert_equal "Vehicle", last_entry.item_type
    assert_equal [ nil, "Car" ], last_entry.change_for(:type)
    assert_equal 1, car.audit_entries.count
    assert_equal car, last_entry.item
  end

  test "works with string (UUID) primary keys" do
    document = Document.create!(title: "Policy")
    document.update!(title: "Policy v2")

    assert_match(/\A\h{8}-/, document.id)
    assert_equal %w[create update], document.audit_entries.map(&:event)
    assert_equal 2, SealedTrail::Entry.for_item(Document, document.id).count
    assert_equal document, last_entry.item
  end

  test "entries are read-only once saved" do
    Post.create!(title: "x")
    entry = last_entry

    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(event: "update") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
  end

  test "models without has_sealed_trail are not tracked" do
    assert_no_difference -> { SealedTrail::Entry.count } do
      User.create!(name: "Ann")
    end
    assert_not User.sealed_trail?
    assert Post.sealed_trail?
  end

  test "rejects invalid options and double declaration" do
    klass = Class.new(ActiveRecord::Base) { self.table_name = "posts" }

    assert_raises(ArgumentError) { klass.has_sealed_trail(on: [ :touch ]) }
    assert_raises(ArgumentError) { klass.has_sealed_trail(skip: [ :title ]) }
    assert_raises(ArgumentError) { Post.has_sealed_trail }
  end
end
