# frozen_string_literal: true

RSpec.describe Bullematic::Configuration do
  subject(:config) { described_class.new }

  describe "default values" do
    it "has enabled set to true" do
      expect(config.enabled).to be true
    end

    it "has auto_fix set to true" do
      expect(config.auto_fix).to be true
    end

    it "has default target_paths" do
      expect(config.target_paths).to eq(%w[app/controllers app/models app/services])
    end

    it "has empty skip_paths" do
      expect(config.skip_paths).to eq([])
    end

    it "has dry_run set to false" do
      expect(config.dry_run).to be false
    end

    it "has backup set to false" do
      expect(config.backup).to be false
    end

    it "has fix_strategy set to :includes" do
      expect(config.fix_strategy).to eq(:includes)
    end

    it "has debug set to false" do
      expect(config.debug).to be false
    end
  end

  describe "#logger" do
    it "returns a Logger instance" do
      expect(config.logger).to be_a(Logger)
    end
  end

  describe "#fix_strategy=" do
    it "rejects unsupported strategies" do
      expect { config.fix_strategy = :destroy }.to raise_error(ArgumentError, /invalid fix strategy/)
    end
  end
end
