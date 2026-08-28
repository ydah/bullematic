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

  describe ".parse_file" do
    it "parses the current contents on every call" do
      Tempfile.create(["parser", ".rb"]) do |file|
        file.write("Post.all")
        file.flush
        first = described_class.parse_file(file.path)

        file.rewind
        file.truncate(0)
        file.write("User.all")
        file.flush
        second = described_class.parse_file(file.path)

        expect(first.value.slice).to eq("Post.all")
        expect(second.value.slice).to eq("User.all")
      end
    end
  end
end
