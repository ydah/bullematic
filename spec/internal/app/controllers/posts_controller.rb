# frozen_string_literal: true

class PostsController < ActionController::Base
  def index
    @posts = Post.all
    render plain: "ok"
  end

  def show
    @post = Post.find(params[:id])
    render plain: "ok"
  end
end
