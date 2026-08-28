# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "logger"
require "stringio"

RSpec.describe "N+1 Auto Fix Integration", type: :integration do
  include FileHelpers

  let(:fixture_dir) { File.join(__dir__, "..", "fixtures", "controllers") }
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(temp_dir) }
  after do
    Object.send(:remove_const, :PostsController) if defined?(PostsController)
  end

  around do |example|
    original = ENV.fetch("BULLEMATIC", nil)
    ENV["BULLEMATIC"] = "1"
    original_includes = Bullet.stacktrace_includes.dup
    original_excludes = Bullet.stacktrace_excludes.dup
    Bullet.stacktrace_includes = [temp_dir]
    Bullet.stacktrace_excludes = []
    example.run
  ensure
    if original
      ENV["BULLEMATIC"] = original
    else
      ENV.delete("BULLEMATIC")
    end
    Bullet.stacktrace_includes = original_includes
    Bullet.stacktrace_excludes = original_excludes
  end

  describe "simple N+1 fix" do
    let(:source_file) { File.join(fixture_dir, "simple_n_plus_one.rb") }
    let(:test_file) { File.join(temp_dir, "posts_controller.rb") }

    before do
      FileUtils.cp(source_file, test_file)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
        config.dry_run = false
      end
    end

    it "adds includes(:comments) to Post.all" do
      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      expect(Bullet.notification?).to be true
      Bullematic::Notifier.process_notifications

      Bullematic::Fixer.apply_fixes

      fixed_content = File.read(test_file)
      expect(fixed_content).to include(".includes(:comments)")
    end

    it "logs detection queue changes when debug is enabled" do
      log_output = StringIO.new
      logger = Logger.new(log_output)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
        config.dry_run = false
        config.debug = true
        config.logger = logger
      end

      Bullematic::Fixer.clear

      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      Bullematic::Notifier.process_notifications

      log_content = log_output.string
      expect(log_content).to include("N+1 Detection created")
      expect(log_content).to include("Base class: Post")
      expect(log_content).to include("Associations: [:comments]")
      expect(log_content).to include("Fixable: true")
      expect(log_content).to include("Queue size before: 0")
      expect(log_content).to include("Queue size after:")

      expect(Bullematic::Fixer.detection_queue.size).to be > 0
    end
  end

  describe "merge into existing includes" do
    let(:source_file) { File.join(fixture_dir, "existing_includes.rb") }
    let(:test_file) { File.join(temp_dir, "posts_controller.rb") }

    before do
      FileUtils.cp(source_file, test_file)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
        config.dry_run = false
      end
    end

    it "adds comments to includes(:user)" do
      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      Bullematic::Notifier.process_notifications
      Bullematic::Fixer.apply_fixes

      fixed_content = File.read(test_file)
      expect(fixed_content).to include("includes(:comments).includes(:user)")
    end
  end

  describe "nested associations" do
    let(:source_file) { File.join(fixture_dir, "nested_associations.rb") }
    let(:test_file) { File.join(temp_dir, "posts_controller.rb") }

    before do
      FileUtils.cp(source_file, test_file)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
        config.dry_run = false
      end
    end

    it "adds nested includes (comments: :likes)" do
      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        comments = create_list(:comment, 2, post: post, user: user)
        comments.each do |comment|
          create_list(:like, 2, comment: comment, user: user)
        end
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      Bullematic::Notifier.process_notifications
      Bullematic::Fixer.apply_fixes

      fixed_content = File.read(test_file)
      expected = File.read(File.join(fixture_dir, "..", "expected", "nested_associations_fixed.rb"))
      expect(fixed_content).to eq(expected)
    end
  end

  describe "unfixable cases" do
    let(:source_file) { File.join(fixture_dir, "unfixable_cases.rb") }
    let(:test_file) { File.join(temp_dir, "posts_controller.rb") }

    before do
      FileUtils.cp(source_file, test_file)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
      end
    end

    it "skips without raising and leaves the file unchanged" do
      original_content = File.read(test_file)

      expect { Bullematic::Fixer.apply_fixes }.not_to raise_error
      expect(File.read(test_file)).to eq(original_content)
    end
  end

  describe "UnusedEagerLoading handling" do
    let(:source_file) { File.join(fixture_dir, "unused_eager_loading.rb") }
    let(:test_file) { File.join(temp_dir, "posts_controller.rb") }
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }

    before do
      FileUtils.cp(source_file, test_file)

      Bullematic.configure do |config|
        config.enabled = true
        config.auto_fix = true
        config.target_paths = [temp_dir]
        config.debug = true
        config.logger = logger
        config.dry_run = false
      end
    end

    it "processes UnusedEagerLoading notifications and logs them" do
      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      original_content = File.read(test_file)

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      expect(Bullet.notification?).to be true
      expect { Bullematic::Notifier.process_notifications }.not_to raise_error

      log_content = log_output.string
      expect(log_content).to include("UnusedEagerLoading detected")
      expect(log_content).to include("Base class: Post")
      expect(log_content).to include("Unused associations:")
      expect(log_content).to include(":comments")

      expect(File.read(test_file)).to eq(original_content)
    end

    it "handles both N+1 and UnusedEagerLoading notifications" do
      mixed_source = File.join(fixture_dir, "existing_includes.rb")
      FileUtils.cp(mixed_source, test_file)

      user = create(:user)
      posts = create_list(:post, 2, user: user)
      posts.each do |post|
        create_list(:comment, 3, post: post, user: user)
      end

      Bullet.end_request if Bullet.start?
      Bullet.start_request

      Object.send(:remove_const, :PostsController) if defined?(PostsController)
      load test_file
      PostsController.new.index

      expect(Bullet.notification?).to be true
      expect { Bullematic::Notifier.process_notifications }.not_to raise_error

      log_content = log_output.string
      expect(log_content).to include("UnusedEagerLoading detected")
      expect(log_content).to include("Base class: Post")

      Bullematic::Fixer.apply_fixes
      fixed_content = File.read(test_file)
      expect(fixed_content).to include("includes(:comments).includes(:user)")
    end
  end
end
