# frozen_string_literal: true

RSpec.describe Bullematic::Detection do
  before do
    Bullematic.configure do |config|
      config.target_paths = %w[app/controllers app/models]
      config.skip_paths = %w[app/controllers/admin]
    end
  end

  after { Bullematic.reset! }

  describe "#initialize" do
    it "normalizes associations to array of symbols" do
      detection = described_class.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: "comments",
        call_stack: []
      )

      expect(detection.associations).to eq([:comments])
    end

    it "handles array of associations" do
      detection = described_class.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: %i[comments author],
        call_stack: []
      )

      expect(detection.associations).to eq(%i[comments author])
    end

    it "drops invalid and duplicate associations" do
      detection = described_class.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments, "comments", nil, Object.new],
        call_stack: []
      )

      expect(detection.associations).to eq([:comments])
    end
  end

  describe "#model_class_name" do
    it "returns string representation of base class" do
      detection = described_class.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      expect(detection.model_class_name).to eq("Post")
    end
  end

  describe "#fixable?" do
    context "when source is in target path" do
      it "returns true" do
        detection = described_class.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["app/controllers/posts_controller.rb:15:in `index'"]
        )

        expect(detection.fixable?).to be true
      end
    end

    context "when source is in skip path" do
      it "returns false" do
        detection = described_class.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["app/controllers/admin/posts_controller.rb:15:in `index'"]
        )

        expect(detection.fixable?).to be false
      end
    end

    context "when source cannot be determined" do
      it "returns false" do
        detection = described_class.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["some/other/path.rb:1"]
        )

        expect(detection.fixable?).to be false
      end
    end

    context "when a path only shares the target prefix" do
      it "returns false" do
        detection = described_class.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["app/controllers_backup/posts_controller.rb:15:in `index'"]
        )

        expect(detection.fixable?).to be false
      end
    end

    context "when associations are empty" do
      it "returns false" do
        detection = described_class.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: nil,
          call_stack: ["app/controllers/posts_controller.rb:15:in `index'"]
        )

        expect(detection.fixable?).to be false
      end
    end
  end

  describe "source location parsing" do
    it "extracts file, line, and method from call stack" do
      detection = described_class.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: [
          "lib/something.rb:1:in `foo'",
          "app/controllers/posts_controller.rb:15:in `index'",
          "app/models/post.rb:20:in `load'"
        ]
      )

      expect(detection.source_file).to eq("app/controllers/posts_controller.rb")
      expect(detection.line_number).to eq(15)
      expect(detection.method_name).to eq("index")
    end
  end
end
