# frozen_string_literal: true

class PostsController < ApplicationController
  def index
    # Dynamic query - not fixable
    @posts = Post.send(params[:scope] || :all)
  end

  def search
    # Ransack - not fixable
    @posts = Post.ransack(params[:q]).result
  end
end
