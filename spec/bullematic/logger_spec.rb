# frozen_string_literal: true

require "stringio"

RSpec.describe Bullematic::BullematicLogger do
  it "counts dry-run changes as planned rather than fixed" do
    output = StringIO.new
    logger = described_class.new(Logger.new(output))
    detection = Bullematic::Detection.new(
      type: :n_plus_one,
      base_class: "Post",
      associations: [:comments],
      call_stack: []
    )

    logger.log_plan("posts.rb", detection)
    logger.log_summary

    expect(logger.stats).to include(fixed: 0, planned: 1)
    expect(output.string).to include("0 fixed, 1 planned")
  end

  it "reports an insertion without marking shifted lines as changed" do
    output = StringIO.new
    logger = described_class.new(Logger.new(output))

    logger.log_dry_run("posts.rb", "a\nb\n", "x\na\nb\n")

    expect(output.string).to include("@@ -1,0 +1,1 @@\n+x\n")
    expect(output.string).not_to include("-a\n")
  end
end
