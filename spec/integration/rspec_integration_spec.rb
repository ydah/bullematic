# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RSpec Integration", type: :integration do
  around do |example|
    original = ENV.fetch("BULLEMATIC", nil)
    ENV["BULLEMATIC"] = "1"
    example.run
  ensure
    if original
      ENV["BULLEMATIC"] = original
    else
      ENV.delete("BULLEMATIC")
    end
  end

  describe "Bullematic::Integrations::RSpec" do
    it "adds hooks to RSpec.configure" do
      hooks = RSpec.configuration.hooks
      before_hooks = hooks.instance_variable_get(:@before_example_hooks)
      after_hooks = hooks.instance_variable_get(:@after_example_hooks)

      before_items = before_hooks.instance_variable_get(:@items_and_filters)
      after_items = after_hooks.instance_variable_get(:@items_and_filters)

      expect(before_items).not_to be_empty
      expect(after_items).not_to be_empty
    end
  end

  describe "test lifecycle" do
    before do
      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = false
      end
    end

    it "starts and ends Bullet around each example" do
      expect(Bullet).to be_enable

      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Post.all.each { |p| p.comments.to_a }

      expect(Bullet.notification?).to be true
    end

    it "clears detections per example" do
      Bullematic::Fixer.clear

      user = create(:user)
      create(:post, user: user)

      expect(Bullematic::Fixer.detection_queue).to be_empty
    end
  end
end
