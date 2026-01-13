# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    @posts = Post.all
    @posts.each { |post| post.comments.to_a }
  end

  def show
    @post = Post.find(params[:id])
  end
end
