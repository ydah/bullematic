# frozen_string_literal: true

RSpec.describe Bullematic do
  it "has a version number" do
    expect(Bullematic::VERSION).not_to be_nil
  end

  describe ".configure" do
    after { Bullematic.reset! }

    it "yields configuration block" do
      Bullematic.configure do |config|
        config.enabled = false
        config.dry_run = true
      end

      expect(Bullematic.configuration.enabled).to be false
      expect(Bullematic.configuration.dry_run).to be true
    end
  end

  describe ".enabled?" do
    after { Bullematic.reset! }

    context "when BULLEMATIC env var is set to 1" do
      around do |example|
        original = ENV.fetch("BULLEMATIC", nil)
        ENV["BULLEMATIC"] = "1"
        example.run
        ENV["BULLEMATIC"] = original
      end

      it "returns true when configuration is enabled" do
        Bullematic.configure { |c| c.enabled = true }
        expect(Bullematic.enabled?).to be true
      end

      it "returns false when configuration is disabled" do
        Bullematic.configure { |c| c.enabled = false }
        expect(Bullematic.enabled?).to be false
      end
    end

    context "when BULLEMATIC env var is not set" do
      around do |example|
        original = ENV.fetch("BULLEMATIC", nil)
        ENV.delete("BULLEMATIC")
        example.run
        ENV["BULLEMATIC"] = original if original
      end

      it "returns false" do
        Bullematic.configure { |c| c.enabled = true }
        expect(Bullematic.enabled?).to be false
      end
    end
  end

  describe ".reset!" do
    it "clears configuration and caches" do
      Bullematic.configure { |c| c.enabled = false }
      Bullematic.reset!

      expect(Bullematic.configuration).to be_nil
    end
  end
end
