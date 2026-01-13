# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    @posts = Post.includes(:user).all
    @posts.each { |post| post.comments.to_a }
  end
end
