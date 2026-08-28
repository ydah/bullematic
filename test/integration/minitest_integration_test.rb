# frozen_string_literal: true

require "test_helper"
require "tempfile"

class MinitestIntegrationTest < ActionDispatch::IntegrationTest
  include Bullematic::Integrations::Minitest::TestHelper
  fixtures :all

  def setup
    super
    @user = users(:one)
    @post = posts(:one)
  end

  test "detects N+1 with Bullematic integration" do
    Bullematic.configure do |config|
      config.enabled = true
      config.auto_fix = false
    end

    get posts_url

    assert_response :success
  end

  test "applies fixes" do
    Tempfile.create(["posts", ".rb"]) do |file|
      file.write("Post.all")
      file.flush

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [File.dirname(file.path)]
        config.dry_run = false
        config.backup = false
      end
      Bullematic::Fixer.queue(Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["#{file.path}:1:in `index'"]
      ))

      Bullematic::Fixer.apply_fixes

      assert_equal "Post.includes(:comments).all", File.read(file.path)
    end
  end

  test "setup preserves detections collected earlier in the run" do
    detection = Bullematic::Detection.new(
      type: :n_plus_one,
      base_class: "Post",
      associations: [:comments],
      call_stack: []
    )
    Bullematic::Fixer.queue(detection)
    base = Class.new { def setup; end }
    test_case = Class.new(base) { include Bullematic::Integrations::Minitest::TestHelper }.new

    test_case.setup

    assert_includes Bullematic::Fixer.detection_queue, detection
  ensure
    Bullet.end_request if Bullet.start?
  end
end
