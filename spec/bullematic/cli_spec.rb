# frozen_string_literal: true

require "bullematic/cli"
require "open3"

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
      config_directory = File.join(directory, "config")
      FileUtils.mkdir_p(config_directory)
      File.write(source, "@posts = Post.all\n@posts.each { |post| post.comments.to_a }\n")
      File.write(File.join(config_directory, "environment.rb"), <<~RUBY)
        require "bullematic"
        Reflection = Struct.new(:name) { def polymorphic? = false }
        class Post
          def self.reflect_on_association(name)
            Reflection.new(name) if name == :comments
          end
        end
        Bullematic.configure do |config|
          config.target_paths = [#{directory.inspect}]
          config.logger = Logger.new(File::NULL)
        end
      RUBY
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
      lib = File.expand_path("../../lib", __dir__)
      executable = File.expand_path("../../exe/bullematic", __dir__)
      cli = [Gem.ruby, "-I#{lib}", executable]
      command = [Gem.ruby, "-I#{lib}", script]
      environment = { Bullematic::EvidenceStore::ENV_KEY => evidence }

      _output, error, status = Open3.capture3(environment, *cli, "record", "--", *command, chdir: directory)
      expect(error).to be_empty
      expect(status).to be_success
      expect(Bullematic::EvidenceStore.read(evidence).size).to eq(1)
      _output, error, status = Open3.capture3(environment, *cli, "apply", chdir: directory)
      expect(error).to be_empty
      expect(status).to be_success
      expect(File.read(source)).to include("Post.includes(:comments).all")
      output, error, status = Open3.capture3(environment, *cli, "verify", chdir: directory)
      expect(error).to be_empty
      expect(status).to be_success
      expect(output).to include("verification passed")
    end
  end

  it "reports the installed dependency contract" do
    expect(described_class.run(["doctor"])).to eq(0)
  end

  it "fails when recorded evidence cannot produce a safe fix" do
    Dir.mktmpdir do |directory|
      source = File.join(directory, "posts.rb")
      evidence = File.join(directory, "evidence.jsonl")
      File.write(source, "Post.all\n")
      ENV[Bullematic::EvidenceStore::ENV_KEY] = evidence
      Bullematic.configure { |config| config.target_paths = [directory] }
      Bullematic::EvidenceStore.append(Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "MissingPost",
        associations: [:comments],
        call_stack: ["#{source}:1:in 'index'"]
      ))

      expect { expect(described_class.run(["apply"])).to eq(1) }
        .to output(/no safe fixes were fixed/).to_stderr
    end
  end
end
