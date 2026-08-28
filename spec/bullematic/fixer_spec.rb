# frozen_string_literal: true

RSpec.describe Bullematic::Fixer do
  before do
    Bullematic.configure do |config|
      config.enabled = true
      config.dry_run = true
    end
    described_class.clear
  end

  after do
    described_class.clear
    Bullematic.reset!
  end

  describe ".queue" do
    it "adds detection to queue" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)

      expect(described_class.detection_queue).to include(detection)
    end

    it "deduplicates the same detection" do
      2.times do
        described_class.queue(Bullematic::Detection.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["app/controllers/posts_controller.rb:2:in `index'"]
        ))
      end

      expect(described_class.detection_queue.size).to eq(1)
    end
  end

  describe ".clear" do
    it "clears the detection queue" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)
      described_class.clear

      expect(described_class.detection_queue).to be_empty
    end
  end

  describe ".apply_fixes" do
    it "clears queue after processing" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)
      described_class.apply_fixes

      expect(described_class.detection_queue).to be_empty
    end
  end

  describe "atomic writes" do
    it "refuses to overwrite a source changed after planning" do
      Tempfile.create(["fixer", ".rb"]) do |file|
        file.write("Post.all")
        file.flush
        digest = Digest::SHA256.digest("Post.all")
        file.rewind
        file.truncate(0)
        file.write("User.all")
        file.flush

        expect do
          described_class.send(:atomic_write, file.path, "Post.includes(:comments).all", digest)
        end.to raise_error(Bullematic::FixError, /source changed/)
        expect(File.binread(file.path)).to eq("User.all")
      end
    end
  end
end
