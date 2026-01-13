# frozen_string_literal: true

RSpec.describe Bullematic::AST::Parser do
  describe "#parse" do
    it "parses valid Ruby code" do
      source = "@posts = Post.all"
      parser = described_class.new(source)

      result = parser.parse
      expect(result).to be_success
    end

    it "raises ParseError for invalid Ruby code" do
      source = "def foo("
      parser = described_class.new(source)

      expect { parser.parse }.to raise_error(Bullematic::ParseError)
    end
  end

  describe ".cache" do
    after { described_class.clear_cache }

    it "returns empty hash initially" do
      described_class.clear_cache
      expect(described_class.cache).to eq({})
    end
  end

  describe ".clear_cache" do
    it "clears the cache" do
      described_class.cache["test"] = "value"
      described_class.clear_cache

      expect(described_class.cache).to eq({})
    end
  end
end
