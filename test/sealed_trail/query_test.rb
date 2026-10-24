# frozen_string_literal: true

require "test_helper"

class QueryTest < ActiveSupport::TestCase
  setup do
    @ann = User.create!(name: "Ann")
    @bob = User.create!(name: "Bob")
    @post = SealedTrail.with_actor(@ann) { Post.create!(title: "one") }
    SealedTrail.with_actor(@bob) { @post.update!(title: "two") }
    @article = SealedTrail.with_actor(@ann) { Article.create!(title: "art") }
    SealedTrail.with_actor("system") { @post.update!(title: "three") }
  end

  test "for_actor finds entries by an Active Record actor" do
    assert_equal [ [ "Post", "create" ], [ "Article", "create" ] ],
      SealedTrail::Entry.for_actor(@ann).chronological.pluck(:item_type, :event)
    assert_equal 1, SealedTrail::Entry.for_actor(@bob).count
  end

  test "for_actor finds entries by a label" do
    assert_equal [ [ "two", "three" ] ], SealedTrail::Entry.for_actor("system").map { |e| e.change_for(:title) }
    assert_equal 1, SealedTrail::Entry.for_actor(:system).count
  end

  test "for_actor does not confuse actors of different types with the same id" do
    SealedTrail.with_actor(@ann.id.to_s) { Post.create!(title: "label actor") }

    assert_equal 2, SealedTrail::Entry.for_actor(@ann).count
  end

  test "for_item accepts a record, a class and id, or a class name and id" do
    assert_equal 3, SealedTrail::Entry.for_item(@post).count
    assert_equal 3, SealedTrail::Entry.for_item(Post, @post.id).count
    assert_equal 3, SealedTrail::Entry.for_item("Post", @post.id.to_s).count
    assert_equal 1, SealedTrail::Entry.for_item(@article).count
  end

  test "for_item_type finds entries for a model" do
    assert_equal 1, SealedTrail::Entry.for_item_type(Article).count
    assert_equal 3, SealedTrail::Entry.for_item_type("Post").count
  end

  test "events filters by one or more events" do
    assert_equal 2, SealedTrail::Entry.events(:update).count
    assert_equal 4, SealedTrail::Entry.events(:create, :update).count
    assert_equal 4, SealedTrail::Entry.events([ "create", "update" ]).count
    assert_equal 0, SealedTrail::Entry.events(:destroy).count
  end

  test "between filters by time, with open ends" do
    old_entry = SealedTrail::Entry.for_item(@article).first
    SealedTrail::Entry.where(id: old_entry.id).update_all(created_at: 3.days.ago)

    assert_equal 3, SealedTrail::Entry.between(1.day.ago, Time.current).count
    assert_equal 1, SealedTrail::Entry.between(4.days.ago, 2.days.ago).count
    assert_equal 1, SealedTrail::Entry.between(nil, 2.days.ago).count
    assert_equal 3, SealedTrail::Entry.between(1.day.ago, nil).count
  end

  test "scopes chain together" do
    assert_equal 1, SealedTrail::Entry.for_item(@post).events(:update).for_actor(@bob).between(1.hour.ago, 1.hour.from_now).count
  end

  test "chronological and reverse_chronological order entries" do
    titles = SealedTrail::Entry.for_item(@post).chronological.map { |e| e.change_for(:title).last }
    assert_equal %w[one two three], titles

    assert_equal "three", SealedTrail::Entry.for_item(@post).reverse_chronological.first.change_for(:title).last
  end

  test "for_request finds everything recorded in one request" do
    SealedTrail::Current.request_id = "req-123"
    Post.create!(title: "a")
    Article.create!(title: "b")

    assert_equal %w[Post Article], SealedTrail::Entry.for_request("req-123").chronological.pluck(:item_type)
  end
end
