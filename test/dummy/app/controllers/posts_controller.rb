# frozen_string_literal: true

class PostsController < ApplicationController
  def create
    post = Post.create!(title: params[:title])
    render json: { id: post.id }
  end

  def update
    Post.find(params[:id]).update!(title: params[:title])
    head :ok
  end

  def destroy
    Post.find(params[:id]).destroy!
    head :ok
  end
end
