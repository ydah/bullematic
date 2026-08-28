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

  it "preserves child command flags after the separator" do
    expect(described_class).to receive(:record).with(["command", "--verify"]).and_return(1)

    expect(described_class.run(["fix", "--", "command", "--verify"])).to eq(1)
  end

  it "refuses to overwrite a symlink command file" do
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      evidence = File.join(directory, "evidence.jsonl")
      File.write(target, "keep")
      File.symlink(target, "#{evidence}.command.json")

      expect do
        described_class.send(:write_command, evidence, ["true"])
      end.to raise_error(Bullematic::Error, /symlink/)
      expect(File.read(target)).to eq("keep")
    end
  end

  it "refuses a command symlink swapped in after validation" do
    skip "File::NOFOLLOW is unavailable" unless File.const_defined?(:NOFOLLOW)

    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      evidence = File.join(directory, "evidence.jsonl")
      command_path = "#{evidence}.command.json"
      File.write(target, "keep")
      allow(File).to receive(:symlink?).and_call_original
      allow(File).to receive(:symlink?).with(command_path) do
        File.symlink(target, command_path)
        false
      end

      expect do
        described_class.send(:write_command, evidence, ["true"])
      end.to raise_error(Bullematic::Error, /symlink/)
      expect(File.read(target)).to eq("keep")
    end
  end

  it "refuses to read a command through a symlink" do
    Dir.mktmpdir do |directory|
      evidence = File.join(directory, "evidence.jsonl")
      target = File.join(directory, "command.json")
      File.write(target, JSON.generate(["unexpected-command"]))
      File.symlink(target, "#{evidence}.command.json")

      expect { described_class.send(:read_command, evidence) }.to raise_error(Bullematic::Error, /symlink/)
    end
  end

  it "ignores non-N+1 warnings during verification" do
    n_plus_one = instance_double(Bullematic::Detection, type: :n_plus_one)
    unused = instance_double(Bullematic::Detection, type: :unused_eager_loading)
    allow(Bullematic::EvidenceStore).to receive(:read).and_return([n_plus_one], [unused])
    allow(described_class).to receive(:read_command).and_return(["true"])
    allow(described_class).to receive(:run_command).and_return(0)

    expect { expect(described_class.run(["verify"])).to eq(0) }
      .to output(/verification passed/).to_stdout
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
