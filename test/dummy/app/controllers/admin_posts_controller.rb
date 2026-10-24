# frozen_string_literal: true

class AdminPostsController < ApplicationController
  def create
    post = Post.create!(title: params[:title])
    render json: { id: post.id }
  end

  private

  def sealed_trail_actor
    "admin:#{request.headers["X-Admin"]}"
  end

  def sealed_trail_metadata
    { user_agent: request.user_agent }
  end
end
