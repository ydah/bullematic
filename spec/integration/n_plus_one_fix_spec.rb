# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

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
      expect(fixed_content).to include("includes(:user, :comments)")
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
      expect(fixed_content).to match(/includes.*comments.*likes/m)
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
end
