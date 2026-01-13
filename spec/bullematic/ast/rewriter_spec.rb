# frozen_string_literal: true

require "prism"

RSpec.describe Bullematic::AST::Rewriter do
  before do
    Bullematic.configure do |config|
      config.fix_strategy = :includes
    end
  end

  after { Bullematic.reset! }

  def find_query(source, model_name)
    result = Prism.parse(source)
    finder = Bullematic::AST::Finder.new(result)
    finder.find_model_queries(model_name).first
  end

  describe "#add_includes" do
    it "adds single association" do
      source = "@posts = Post.all"
      rewriter = described_class.new(source)
      query = find_query(source, "Post")

      rewriter.add_includes(query, [:comments])
      result = rewriter.rewrite

      expect(result).to eq("@posts = Post.includes(:comments).all")
    end

    it "adds multiple associations" do
      source = "@posts = Post.all"
      rewriter = described_class.new(source)
      query = find_query(source, "Post")

      rewriter.add_includes(query, %i[comments author])
      result = rewriter.rewrite

      expect(result).to eq("@posts = Post.includes(:comments, :author).all")
    end
  end

  describe "#rewrite" do
    it "returns original source when no modifications" do
      source = "@posts = Post.all"
      rewriter = described_class.new(source)

      expect(rewriter.rewrite).to eq(source)
    end

    it "applies multiple modifications in correct order" do
      source = <<~RUBY
        @posts = Post.all
        @users = User.all
      RUBY

      rewriter = described_class.new(source)
      result = Prism.parse(source)
      finder = Bullematic::AST::Finder.new(result)

      post_query = finder.find_model_queries("Post").first
      user_query = finder.find_model_queries("User").first

      rewriter.add_includes(post_query, [:comments])
      rewriter.add_includes(user_query, [:posts])

      output = rewriter.rewrite

      expect(output).to include("Post.includes(:comments).all")
      expect(output).to include("User.includes(:posts).all")
    end
  end

  describe "fix_strategy" do
    it "uses preload when configured" do
      Bullematic.configuration.fix_strategy = :preload
      source = "@posts = Post.all"
      rewriter = described_class.new(source)
      query = find_query(source, "Post")

      rewriter.add_includes(query, [:comments])
      result = rewriter.rewrite

      expect(result).to eq("@posts = Post.preload(:comments).all")
    end

    it "uses eager_load when configured" do
      Bullematic.configuration.fix_strategy = :eager_load
      source = "@posts = Post.all"
      rewriter = described_class.new(source)
      query = find_query(source, "Post")

      rewriter.add_includes(query, [:comments])
      result = rewriter.rewrite

      expect(result).to eq("@posts = Post.eager_load(:comments).all")
    end
  end
end
