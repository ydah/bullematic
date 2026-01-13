# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    @posts = Post.includes(:comments).all
    @posts.map(&:title)
  end
end
