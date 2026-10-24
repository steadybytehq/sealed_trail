# frozen_string_literal: true

module Api
  # Authentication runs after SealedTrail's before_action, so this checks that
  # the actor is resolved lazily.
  class PostsController < ActionController::API
    before_action :authenticate

    def create
      post = Post.create!(title: params[:title])
      render json: { id: post.id }
    end

    private

    attr_reader :current_user

    def authenticate
      @current_user = User.find_by(name: request.headers["X-Api-User"])
    end
  end
end
