# frozen_string_literal: true

RSpec.describe Bullematic::EvidenceStore do
  around do |example|
    original = ENV.fetch(described_class::ENV_KEY, nil)
    example.run
  ensure
    original ? ENV[described_class::ENV_KEY] = original : ENV.delete(described_class::ENV_KEY)
  end

  it "persists concurrent detections as valid JSON lines without retaining them in memory" do
    Dir.mktmpdir do |directory|
      queued_before = Bullematic::Fixer.detection_queue
      source = File.join(directory, "posts.rb")
      evidence = File.join(directory, "evidence.jsonl")
      File.write(source, "Post.all")
      ENV[described_class::ENV_KEY] = evidence
      Bullematic.configure { |config| config.target_paths = [directory] }

      threads = 10.times.map do |index|
        Thread.new do
          Bullematic::Fixer.queue(Bullematic::Detection.new(
            type: :n_plus_one,
            base_class: "Post",
            associations: [:comments],
            call_stack: ["#{source}:1:in 'index'"],
            context_id: index
          ))
        end
      end
      threads.each(&:join)

      expect(described_class.read(evidence).size).to eq(10)
      expect(Bullematic::Fixer.detection_queue).to eq(queued_before)
    end
  end

  it "rejects malformed evidence before planning" do
    Tempfile.create do |file|
      file.write('{"type":"unknown","associations":[],"call_stack":[]}')
      file.flush

      expect { described_class.read(file.path) }.to raise_error(Bullematic::Error, /invalid evidence type/)
    end
  end

  it "refuses to truncate a symlink evidence file" do
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      evidence = File.join(directory, "evidence.jsonl")
      File.write(target, "keep")
      File.symlink(target, evidence)

      expect { described_class.clear(evidence) }.to raise_error(Bullematic::Error, /symlink/)
      expect(File.read(target)).to eq("keep")
    end
  end

  it "keeps complete JSON lines from parallel worker processes" do
    Dir.mktmpdir do |directory|
      source = File.join(directory, "posts.rb")
      evidence = File.join(directory, "evidence.jsonl")
      script = File.join(directory, "append.rb")
      File.write(source, "Post.all")
      File.write(script, <<~RUBY)
        require "bullematic"
        Bullematic.configure { |config| config.target_paths = [#{directory.inspect}] }
        Bullematic::Fixer.queue(Bullematic::Detection.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: [#{"#{source}:1:in 'index'".inspect}],
          context_id: ARGV.fetch(0)
        ))
      RUBY
      lib = File.expand_path("../../lib", __dir__)
      environment = { described_class::ENV_KEY => evidence }
      pids = 4.times.map do |index|
        Process.spawn(environment, Gem.ruby, "-I#{lib}", script, index.to_s, out: File::NULL, err: File::NULL)
      end

      statuses = pids.map { |pid| Process.wait2(pid).last }

      expect(statuses).to all(be_success)
      expect(described_class.read(evidence).size).to eq(4)
    end
  end
end
