# frozen_string_literal: true

class RenamePostJob < ApplicationJob
  def perform(post_id, title)
    Post.find(post_id).update!(title: title)
  end
end
