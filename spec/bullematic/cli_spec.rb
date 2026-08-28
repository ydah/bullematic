# frozen_string_literal: true

require "bullematic/cli"

RSpec.describe Bullematic::CLI do
  around do |example|
    original = ENV.fetch(Bullematic::EvidenceStore::ENV_KEY, nil)
    example.run
  ensure
    original ? ENV[Bullematic::EvidenceStore::ENV_KEY] = original : ENV.delete(Bullematic::EvidenceStore::ENV_KEY)
  end

  it "records, applies, and verifies one warning across processes" do
    Dir.mktmpdir do |directory|
      source = File.join(directory, "posts.rb")
      script = File.join(directory, "record.rb")
      evidence = File.join(directory, "evidence.jsonl")
      File.write(source, "@posts = Post.all\n@posts.each { |post| post.comments.to_a }\n")
      File.write(script, <<~RUBY)
        require "bullematic"
        Bullematic.configure { |config| config.target_paths = [#{directory.inspect}] }
        unless File.read(#{source.inspect}).include?("includes(:comments)")
          Bullematic::Fixer.queue(Bullematic::Detection.new(
            type: :n_plus_one,
            base_class: "Post",
            associations: [:comments],
            call_stack: [#{"#{source}:2:in 'block in PostsController#index'".inspect}],
            context_id: "cli"
          ))
        end
      RUBY
      ENV[Bullematic::EvidenceStore::ENV_KEY] = evidence
      Bullematic.configure do |config|
        config.target_paths = [directory]
        config.logger = Logger.new(File::NULL)
      end
      command = [Gem.ruby, "-I#{File.expand_path('../../lib', __dir__)}", script]

      expect(described_class.run(["record", "--", *command])).to eq(0)
      expect(Bullematic::EvidenceStore.read(evidence).size).to eq(1)
      expect(described_class.run(["apply"])).to eq(0)
      expect(File.read(source)).to include("Post.includes(:comments).all")
      expect(described_class.run(["verify"])).to eq(0)
    end
  end

  it "reports the installed dependency contract" do
    expect(described_class.run(["doctor"])).to eq(0)
  end
end
