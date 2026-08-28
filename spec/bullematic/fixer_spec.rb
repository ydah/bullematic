# frozen_string_literal: true

RSpec.describe Bullematic::Fixer do
  before do
    Bullematic.configure do |config|
      config.enabled = true
      config.dry_run = true
    end
    described_class.clear
  end

  after do
    described_class.clear
    Bullematic.reset!
  end

  describe ".queue" do
    it "adds detection to queue" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)

      expect(described_class.detection_queue).to include(detection)
    end

    it "deduplicates the same detection" do
      2.times do
        described_class.queue(Bullematic::Detection.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["app/controllers/posts_controller.rb:2:in `index'"]
        ))
      end

      expect(described_class.detection_queue.size).to eq(1)
    end
  end

  describe ".clear" do
    it "clears the detection queue" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)
      described_class.clear

      expect(described_class.detection_queue).to be_empty
    end
  end

  describe ".apply_fixes" do
    it "clears queue after processing" do
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(detection)
      described_class.apply_fixes

      expect(described_class.detection_queue).to be_empty
    end

    it "reports unavailable sources as skipped" do
      output = StringIO.new
      Bullematic.configuration.logger = Logger.new(output)
      missing_file = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["app/controllers/missing_controller.rb:15:in `index'"]
      )
      unknown_source = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      described_class.queue(missing_file)
      described_class.queue(unknown_source)

      expect(described_class.apply_fixes[:skipped]).to eq(2)
      expect(output.string).to include("source file not found")
      expect(output.string).to include("source unavailable")
    end

    it "refuses evidence captured before the source changed" do
      Dir.mktmpdir do |directory|
        filepath = File.join(directory, "posts.rb")
        original = "@posts = Post.all\n@posts.each { |post| post.comments.to_a }\n"
        File.write(filepath, original)
        Bullematic.configure do |config|
          config.target_paths = [directory]
          config.dry_run = false
          config.backup = false
          config.logger = Logger.new(File::NULL)
        end
        detection = Bullematic::Detection.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["#{filepath}:2:in 'block in PostsController#index'"]
        )
        user_edit = "# user edit\n#{original}"
        File.write(filepath, user_edit)

        described_class.queue(detection)
        described_class.apply_fixes

        expect(File.read(filepath)).to eq(user_edit)
      end
    end

    it "rechecks the configured fix scope before writing" do
      Dir.mktmpdir do |directory|
        filepath = File.join(directory, "posts.rb")
        original = "Post.all\n"
        File.write(filepath, original)
        Bullematic.configure do |config|
          config.target_paths = [directory]
          config.dry_run = false
          config.backup = false
          config.logger = Logger.new(File::NULL)
        end
        detection = Bullematic::Detection.new(
          type: :n_plus_one,
          base_class: "Post",
          associations: [:comments],
          call_stack: ["#{filepath}:1:in 'PostsController#index'"]
        )
        Bullematic.configuration.skip_paths = [directory]

        described_class.queue(detection)
        stats = described_class.apply_fixes

        expect(File.read(filepath)).to eq(original)
        expect(stats[:skipped]).to eq(1)
      end
    end

    it "applies a relative backtrace frame outside the Rails working directory" do
      Dir.mktmpdir do |root|
        filepath = File.join(root, "app/controllers/posts_controller.rb")
        FileUtils.mkdir_p(File.dirname(filepath))
        File.write(filepath, "@posts = Post.all\n@posts.each { |post| post.comments.to_a }\n")
        allow(Rails).to receive(:root).and_return(Pathname(root))
        Bullematic.configure do |config|
          config.target_paths = ["app/controllers"]
          config.dry_run = false
          config.backup = false
          config.logger = Logger.new(File::NULL)
        end

        Dir.mktmpdir do |working_directory|
          Dir.chdir(working_directory) do
            described_class.queue(Bullematic::Detection.new(
              type: :n_plus_one,
              base_class: "Post",
              associations: [:comments],
              call_stack: ["app/controllers/posts_controller.rb:2:in 'block in PostsController#index'"]
            ))
            described_class.apply_fixes
          end
        end

        expect(File.read(filepath)).to start_with("@posts = Post.includes(:comments).all")
      end
    end
  end

  describe "atomic writes" do
    it "refuses to overwrite a source changed after planning" do
      Tempfile.create(["fixer", ".rb"]) do |file|
        file.write("Post.all")
        file.flush
        digest = Digest::SHA256.digest("Post.all")
        file.rewind
        file.truncate(0)
        file.write("User.all")
        file.flush

        expect do
          described_class.send(:atomic_write, file.path, "Post.includes(:comments).all", digest)
        end.to raise_error(Bullematic::FixError, /source changed/)
        expect(File.binread(file.path)).to eq("User.all")
      end
    end

    it "allows only one writer for the same source snapshot" do
      Tempfile.create(["fixer", ".rb"]) do |file|
        file.write("Post.all")
        file.flush
        digest = Digest::SHA256.digest("Post.all")
        errors = Queue.new
        writers = ["Post.includes(:comments).all", "Post.includes(:author).all"].map do |source|
          Thread.new do
            described_class.send(:atomic_write, file.path, source, digest)
          rescue Bullematic::FixError => error
            errors << error
          end
        end

        writers.each(&:join)

        expect(errors.size).to eq(1)
        expect(["Post.includes(:comments).all", "Post.includes(:author).all"]).to include(File.binread(file.path))
      end
    end

    it "refuses to replace a symlink" do
      Dir.mktmpdir do |directory|
        target = File.join(directory, "target.rb")
        link = File.join(directory, "link.rb")
        File.write(target, "Post.all")
        File.symlink(target, link)

        expect do
          described_class.send(
            :atomic_write,
            link,
            "Post.includes(:comments).all",
            Digest::SHA256.digest("Post.all")
          )
        end.to raise_error(Bullematic::FixError, /symlink/)
        expect(File.read(target)).to eq("Post.all")
      end
    end

    it "refuses to replace a read-only source" do
      Tempfile.create(["fixer", ".rb"]) do |file|
        file.write("Post.all")
        file.flush
        File.chmod(0o444, file.path)

        expect do
          described_class.send(
            :atomic_write,
            file.path,
            "Post.includes(:comments).all",
            Digest::SHA256.digest("Post.all")
          )
        end.to raise_error(Bullematic::FixError, /read-only/)
        expect(File.binread(file.path)).to eq("Post.all")
      ensure
        File.chmod(0o600, file.path) if File.exist?(file.path)
      end
    end

    it "refuses to write through a symlink backup" do
      Dir.mktmpdir do |directory|
        source = File.join(directory, "posts.rb")
        outside = File.join(directory, "outside")
        File.write(source, "Post.all")
        File.symlink(outside, "#{source}.bullematic.bak")
        Bullematic.configuration.backup = true

        expect do
          described_class.send(
            :atomic_write,
            source,
            "Post.includes(:comments).all",
            Digest::SHA256.digest("Post.all")
          )
        end.to raise_error(Bullematic::FixError, /symlink backup/)
        expect(File.read(source)).to eq("Post.all")
        expect(File).not_to exist(outside)
      end
    end
  end

  describe "query evidence" do
    it "rejects associations that reflection cannot verify" do
      valid = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )
      invalid = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:missing],
        call_stack: []
      )

      expect(described_class.send(:valid_associations?, valid)).to be true
      expect(described_class.send(:valid_associations?, invalid)).to be false
    end

    it "does not use a file-wide model match without a source location" do
      finder = Bullematic::AST::Finder.new(Prism.parse("Post.all\nputs :done"))
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: []
      )

      expect(described_class.send(:find_query_location, finder, detection)).to be_nil
    end

    it "selects the query assigned to the variable used at the access site" do
      source = <<~RUBY
        def index
          @featured = Post.where(featured: true)
          @posts = Post.all
          @posts.each { |post| post.comments.to_a }
        end
      RUBY
      finder = Bullematic::AST::Finder.new(Prism.parse(source))
      detection = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["app/controllers/posts_controller.rb:4:in 'block in PostsController#index'"]
      )

      query = described_class.send(:find_query_location, finder, detection)

      expect(query.target_name).to eq(:@posts)
    end

    it "does not guess between associations to the same child model" do
      reflection = instance_double(
        ActiveRecord::Reflection::AssociationReflection,
        polymorphic?: false,
        klass: Comment
      )
      allow(Post).to receive(:reflect_on_association).and_call_original
      allow(Post).to receive(:reflect_on_association).with(:review_comments).and_return(reflection)
      parent = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: %i[comments review_comments],
        call_stack: ["app/controllers/posts_controller.rb:1:in 'index'"],
        context_id: 1
      )
      child = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Comment",
        associations: [:likes],
        call_stack: ["app/controllers/posts_controller.rb:1:in 'index'"],
        context_id: 1
      )
      finder = Bullematic::AST::Finder.new(
        Prism.parse("posts.each { |post| post.comments.each { |comment| comment.likes.to_a } }")
      )

      associations = described_class.send(:association_tree, parent, [child], [], [], finder)

      expect(associations).to eq(%i[comments review_comments])
    end

    it "does not merge independent detections from the same line" do
      parent = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Post",
        associations: [:comments],
        call_stack: ["app/controllers/posts_controller.rb:1:in 'index'"],
        context_id: 1
      )
      child = Bullematic::Detection.new(
        type: :n_plus_one,
        base_class: "Comment",
        associations: [:likes],
        call_stack: ["app/controllers/posts_controller.rb:1:in 'index'"],
        context_id: 1
      )
      source = "comments = Comment.all; posts.each { |post| post.comments.to_a }; " \
               "comments.each { |comment| comment.likes.to_a }\n"
      finder = Bullematic::AST::Finder.new(Prism.parse(source))

      associations = described_class.send(:association_tree, parent, [child], [], [], finder)

      expect(associations).to eq([:comments])
    end
  end
end
