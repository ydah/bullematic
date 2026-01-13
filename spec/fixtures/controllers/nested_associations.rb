# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    @posts = Post.all
    @posts.each do |post|
      post.comments.each { |comment| comment.likes.to_a }
    end
  end
end
