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
      expect(Bullematic::Fixer.detection_queue).to be_empty
    end
  end

  it "rejects malformed evidence before planning" do
    Tempfile.create do |file|
      file.write('{"type":"unknown","associations":[],"call_stack":[]}')
      file.flush

      expect { described_class.read(file.path) }.to raise_error(Bullematic::Error, /invalid evidence type/)
    end
  end
end
