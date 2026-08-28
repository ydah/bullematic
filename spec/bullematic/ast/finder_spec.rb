# frozen_string_literal: true

require "prism"

RSpec.describe Bullematic::AST::Finder do
  describe "#find_model_queries" do
    it "finds simple query" do
      source = "@posts = Post.all"
      result = Prism.parse(source)
      finder = described_class.new(result)

      queries = finder.find_model_queries("Post")
      expect(queries.size).to eq(1)
      expect(queries.first.method_name).to eq(:all)
    end

    it "finds where query" do
      source = "@posts = Post.where(published: true)"
      result = Prism.parse(source)
      finder = described_class.new(result)

      queries = finder.find_model_queries("Post")
      expect(queries.size).to eq(1)
      expect(queries.first.method_name).to eq(:where)
    end

    it "finds chained queries as single query" do
      source = "@posts = Post.where(published: true).order(:created_at)"
      result = Prism.parse(source)
      finder = described_class.new(result)

      queries = finder.find_model_queries("Post")
      expect(queries.size).to eq(1)
      expect(queries.first.method_name).to eq(:order)
    end

    it "finds query at specific line" do
      source = <<~RUBY
        def index
          @users = User.all
          @posts = Post.all
        end
      RUBY
      result = Prism.parse(source)
      finder = described_class.new(result)

      queries = finder.find_model_queries("Post", line_number: 3)
      expect(queries.size).to eq(1)
    end

    it "ignores queries for different models" do
      source = "@posts = Post.all\n@users = User.all"
      result = Prism.parse(source)
      finder = described_class.new(result)

      queries = finder.find_model_queries("Post")
      expect(queries.size).to eq(1)
    end

    it "finds namespaced and root constants" do
      source = "Admin::Post.all\n::Post.all"
      finder = described_class.new(Prism.parse(source))

      expect(finder.find_model_queries("Admin::Post").size).to eq(1)
      expect(finder.find_model_queries("Post").size).to eq(1)
    end

    it "does not treat non-query assignments as queries" do
      source = "@post = Post.new\n@count = Post.count"
      finder = described_class.new(Prism.parse(source))

      expect(finder.find_model_queries("Post")).to be_empty
    end
  end

  describe "#find_model_queries_for_variables_at_line" do
    it "links the accessed variable to its model query" do
      source = <<~RUBY
        def index
          @featured = Post.where(featured: true)
          @posts = Post.all
          @posts.each { |post| post.comments.to_a }
        end
      RUBY
      finder = described_class.new(Prism.parse(source))

      queries = finder.find_model_queries_for_variables_at_line("Post", 4)

      expect(queries.size).to eq(1)
      expect(queries.first.target_name).to eq(:@posts)
    end

    it "supports local relation variables" do
      source = "posts = Post.all\nposts.each { |post| post.comments.to_a }"
      finder = described_class.new(Prism.parse(source))

      queries = finder.find_model_queries_for_variables_at_line("Post", 2)

      expect(queries.size).to eq(1)
      expect(queries.first.target_name).to eq(:posts)
    end

    it "traces a block parameter back to its relation variable" do
      source = <<~RUBY
        @posts = Post.all
        @posts.each do |post|
          post.comments.to_a
        end
      RUBY
      finder = described_class.new(Prism.parse(source))

      queries = finder.find_model_queries_for_variables_at_line("Post", 3)

      expect(queries.map(&:target_name)).to eq([:@posts])
    end

    it "rejects a relation variable reassigned before the access" do
      source = <<~RUBY
        def index
          posts = Post.all
          posts = fallback_posts
          posts.each { |post| post.comments.to_a }
        end
      RUBY
      finder = described_class.new(Prism.parse(source))

      expect(finder.find_model_queries_for_variables_at_line("Post", 4)).to be_empty
    end

    it "rejects a relation query from another method" do
      source = <<~RUBY
        def load_posts
          @posts = Post.all
        end

        def index
          @posts.each { |post| post.comments.to_a }
        end
      RUBY
      finder = described_class.new(Prism.parse(source))

      expect(finder.find_model_queries_for_variables_at_line("Post", 6)).to be_empty
    end

    it "rejects a relation query that occurs after the access" do
      source = <<~RUBY
        def index
          posts.each { |post| post.comments.to_a }
          posts = Post.all
        end
      RUBY
      finder = described_class.new(Prism.parse(source))

      expect(finder.find_model_queries_for_variables_at_line("Post", 2)).to be_empty
    end
  end

  describe "#nested_association?" do
    it "requires the child access to use the parent's block variable" do
      nested = <<~RUBY
        post.comments.each do |comment|
          comment.likes.to_a
        end
      RUBY
      shadowed = "post.comments.each { |comment| others.each { |comment| comment.likes.to_a } }"
      reassigned = "post.comments.each { |comment| comment = other; comment.likes.to_a }"

      expect(described_class.new(Prism.parse(nested)).nested_association?(:comments, [:likes], 2)).to be true
      expect(described_class.new(Prism.parse(shadowed)).nested_association?(:comments, [:likes], 1)).to be false
      expect(described_class.new(Prism.parse(reassigned)).nested_association?(:comments, [:likes], 1)).to be false
    end
  end
end
