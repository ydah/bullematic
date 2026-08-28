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

    it "retains detections until the suite applies fixes" do
      user = create(:user)
      create(:post, user: user)

      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["app/controllers/posts_controller.rb:2:in `index'"]
      )
      Bullematic::Fixer.queue(detection)

      expect(Bullematic::Fixer.detection_queue).to include(detection)
    end
  end

  describe "suite retention", order: :defined do
    before(:context) { Bullematic::Fixer.clear }
    after(:context) { Bullematic::Fixer.clear }

    it "queues a detection in one example" do
      Bullematic::Fixer.queue(Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["app/controllers/posts_controller.rb:2:in `index'"]
      ))
    end

    it "still has the prior example detection" do
      expect(Bullematic::Fixer.detection_queue.map(&:model_class_name)).to include("Post")
    end
  end

  describe "disabled teardown" do
    before(:context) { Bullematic.configure { |config| config.enabled = true } }
    after(:context) do
      Bullet.enable = true
      Bullematic.configure { |config| config.enabled = true }
      Bullet.end_request if Bullet.start?
    end

    it "disables Bullematic while a request is active" do
      expect(Bullet.start?).to be true
      expect(Bullet).to receive(:end_request).and_call_original
      Bullematic.configuration.enabled = false
      Bullet.enable = false
    end
  end
end
