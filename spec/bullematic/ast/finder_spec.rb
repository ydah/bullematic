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
  end

  describe "#find_query_at_line" do
    it "finds query at specified line" do
      source = <<~RUBY
        def index
          @posts = Post.all
        end
      RUBY
      result = Prism.parse(source)
      finder = described_class.new(result)

      query = finder.find_query_at_line(2)
      expect(query).not_to be_nil
      expect(query.method_name).to eq(:all)
    end

    it "returns nil when no query at line" do
      source = <<~RUBY
        def index
          puts "hello"
        end
      RUBY
      result = Prism.parse(source)
      finder = described_class.new(result)

      query = finder.find_query_at_line(2)
      expect(query).to be_nil
    end
  end
end
