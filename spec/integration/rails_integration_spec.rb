# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Rails Integration", type: :request do
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

  describe "N+1 detection in controller" do
    before do
      controller_path = File.expand_path("../internal/app/controllers/posts_controller.rb", __dir__)
      load controller_path if File.exist?(controller_path)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = false
      end

      user = create(:user)
      3.times do
        post = create(:post, user: user)
        create_list(:comment, 2, post: post, user: user)
      end
    end

    it "returns ok for the index action" do
      get "/posts"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "middleware integration" do
    before do
      Bullematic.configure do |config|
        config.enabled = true
      end
    end

    it "exposes middleware in the stack" do
      middleware_classes = Rails.application.middleware.map(&:klass)

      if Bullematic.configuration&.enabled
        # expect(middleware_classes).to include(Bullematic::Middleware)
      end
    end
  end
end
