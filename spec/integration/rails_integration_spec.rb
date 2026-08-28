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

    it "records a real Bullet notification before Bullet clears it" do
      original_includes = Bullet.stacktrace_includes.dup
      original_excludes = Bullet.stacktrace_excludes.dup
      Dir.mktmpdir do |directory|
        controller = File.join(directory, "posts_controller.rb")
        evidence = File.join(directory, "evidence.jsonl")
        FileUtils.cp(File.expand_path("../fixtures/controllers/simple_n_plus_one.rb", __dir__), controller)
        ENV[Bullematic::EvidenceStore::ENV_KEY] = evidence
        Bullematic.configure do |config|
          config.enabled = true
          config.target_paths = [directory]
        end
        Bullet.stacktrace_includes = [directory]
        Bullet.stacktrace_excludes = []
        Object.send(:remove_const, :PostsController)
        load controller
        app = ->(_env) do
          PostsController.new.index
          [200, {}, ["ok"]]
        end

        Bullet::Rack.new(Bullematic::Middleware.new(app)).call({})

        detection = Bullematic::EvidenceStore.read(evidence).find { |item| item.type == :n_plus_one }
        expect([detection.model_class_name, detection.associations]).to eq(["Post", [:comments]])
      ensure
        ENV.delete(Bullematic::EvidenceStore::ENV_KEY)
        Bullet.stacktrace_includes = original_includes
        Bullet.stacktrace_excludes = original_excludes
        Object.send(:remove_const, :PostsController) if defined?(PostsController)
      end
    end
  end
end
