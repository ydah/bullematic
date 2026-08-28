# rbs_inline: enabled
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tempfile"
require "tmpdir"

module Bullematic
  class Fixer
    class << self
      #: () -> Array[Detection]
      def detection_queue
        queue_mutex.synchronize { queue_store.dup }
      end

      # @rbs detection: Detection
      # @rbs return: void
      def queue(detection)
        if EvidenceStore.recording?
          EvidenceStore.append(detection)
          return
        end

        queue_mutex.synchronize do
          queue_store << detection unless queue_store.any? { |queued| queued.fingerprint == detection.fingerprint }
        end
      end

      #: () -> void
      def clear
        queue_mutex.synchronize { @detection_queue = [] }
      end

      #: () -> Hash[Symbol, Integer]
      def apply_fixes
        logger = BullematicLogger.new
        pending = drain_queue
        return logger.stats if pending.empty?

        grouped = pending.group_by(&:source_file)

        grouped.each do |filepath, detections|
          next unless filepath

          process_file(filepath, detections, logger)
        rescue ParseError, FixError => e
          logger.log_error(filepath, e)
        rescue StandardError => e
          logger.log_error(filepath, e)
          raise if Bullematic.configuration&.debug
        end

        logger.log_summary
        logger.stats
      end

      private

      #: () -> Array[Detection]
      def queue_store
        @detection_queue ||= [] #: Array[Detection]
      end

      #: () -> Mutex
      def queue_mutex
        @queue_mutex ||= Mutex.new
      end

      #: () -> Array[Detection]
      def drain_queue
        queue_mutex.synchronize do
          pending = queue_store
          @detection_queue = []
          pending
        end
      end

      # @rbs filepath: String
      # @rbs detections: Array[Detection]
      # @rbs logger: BullematicLogger
      # @rbs return: void
      def process_file(filepath, detections, logger)
        return unless File.exist?(filepath)

        original_source = File.binread(filepath)
        expected_digest = Digest::SHA256.digest(original_source)
        current_hexdigest = Digest::SHA256.hexdigest(original_source)
        detections = detections.reject do |detection|
          stale = detection.source_digest && detection.source_digest != current_hexdigest
          logger.log_skip(filepath, detection, "source changed since detection") if stale
          stale
        end
        return if detections.empty?

        parse_result = AST::Parser.new(original_source, filepath: filepath).parse
        finder = AST::Finder.new(parse_result)
        rewriter = AST::Rewriter.new(original_source)
        changed = [] #: Array[Detection]

        build_requests(finder, detections, logger, filepath).each do |request|
          detection = request[:detection]
          result = rewriter.add_includes(request[:location], request[:associations])
          if result == :changed
            changed << detection
          else
            logger.log_skip(filepath, detection, result.to_s.tr("_", " "))
          end
        end

        new_source = rewriter.rewrite

        return if new_source == original_source

        AST::Parser.new(new_source, filepath: filepath).parse

        if Bullematic.configuration&.dry_run
          logger.log_dry_run(filepath, original_source, new_source)
          changed.each { |detection| logger.log_plan(filepath, detection) }
        else
          atomic_write(filepath, new_source, expected_digest)
          changed.each { |detection| logger.log_fix(filepath, detection) }
        end
      end

      # @rbs finder: AST::Finder
      # @rbs detection: Detection
      # @rbs return: AST::Finder::QueryLocation?
      def find_query_location(finder, detection)
        queries = if detection.line_number
                    finder.find_model_queries(
                      detection.model_class_name,
                      line_number: detection.line_number
                    )
                  else
                    []
                  end

        return queries.first if queries.size == 1
        return nil if queries.size > 1

        return nil unless detection.line_number

        variable_queries = finder.find_model_queries_for_variables_at_line(
          detection.model_class_name,
          detection.line_number
        )
        variable_queries.one? ? variable_queries.first : nil
      end

      # @rbs finder: AST::Finder
      # @rbs detections: Array[Detection]
      # @rbs logger: BullematicLogger
      # @rbs filepath: String
      # @rbs return: Array[Hash[Symbol, untyped]]
      def build_requests(finder, detections, logger, filepath)
        requests = [] #: Array[Hash[Symbol, untyped]]
        unresolved = [] #: Array[Detection]

        detections.each do |detection|
          unless valid_associations?(detection)
            logger.log_skip(filepath, detection, "invalid association")
            next
          end

          location = find_query_location(finder, detection)
          if location
            requests << { detection: detection, location: location, associations: detection.associations }
          else
            unresolved << detection
          end
        end

        consumed = [] #: Array[Detection]
        requests.each do |request|
          request[:associations] = association_tree(request[:detection], unresolved, consumed, [])
        end
        (unresolved - consumed).each { |detection| logger.log_skip(filepath, detection, "could not locate query") }
        requests
      end

      # @rbs detection: Detection
      # @rbs return: bool
      def valid_associations?(detection)
        model = constantize_model(detection.model_class_name)
        return false unless model&.respond_to?(:reflect_on_association)

        detection.associations.all? do |association|
          reflection = model.reflect_on_association(association)
          reflection && !reflection.polymorphic?
        end
      rescue NameError
        false
      end

      # @rbs detection: Detection
      # @rbs candidates: Array[Detection]
      # @rbs consumed: Array[Detection]
      # @rbs seen: Array[String]
      # @rbs return: Array[untyped]
      def association_tree(detection, candidates, consumed, seen)
        return detection.associations if seen.include?(detection.model_class_name)

        detection.associations.map do |association|
          child = nested_detection(detection, association, candidates - consumed)
          next association unless child

          consumed << child
          nested = association_tree(child, candidates, consumed, seen + [detection.model_class_name])
          { association => nested.one? ? nested.first : nested }
        end
      end

      # @rbs parent: Detection
      # @rbs association: Symbol
      # @rbs candidates: Array[Detection]
      # @rbs return: Detection?
      def nested_detection(parent, association, candidates)
        return nil unless parent.context_id

        model = constantize_model(parent.model_class_name)
        return nil unless model&.respond_to?(:reflect_on_association)

        reflection = model.reflect_on_association(association)
        return nil unless reflection && !reflection.polymorphic?

        matches = candidates.select do |candidate|
          candidate.context_id == parent.context_id &&
            same_execution_location?(parent, candidate) &&
            candidate.model_class_name == reflection.klass.name
        end
        matches.one? ? matches.first : nil
      rescue NameError
        nil
      end

      # @rbs detection: Detection
      # @rbs return: String?
      def normalized_method(detection)
        detection.method_name&.split(" in ")&.last&.sub(/\Ablock /, "")&.split("#")&.last
      end

      # @rbs left: Detection
      # @rbs right: Detection
      # @rbs return: bool
      def same_execution_location?(left, right)
        left_method = normalized_method(left)
        right_method = normalized_method(right)
        return left_method == right_method if left_method && right_method

        left.line_number == right.line_number
      end

      # @rbs name: String
      # @rbs return: untyped
      def constantize_model(name)
        normalized = name.delete_prefix("::")
        return nil unless normalized.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)

        normalized.split("::").reduce(Object) { |scope, constant| scope.const_get(constant, false) }
      end

      # @rbs filepath: String
      # @rbs source: String
      # @rbs expected_digest: String
      # @rbs return: void
      def atomic_write(filepath, source, expected_digest)
        raise FixError, "symlink sources are unsupported" if File.symlink?(filepath)

        lock_name = "bullematic-#{Digest::SHA256.hexdigest(File.expand_path(filepath))}.lock"
        File.open(File.join(Dir.tmpdir, lock_name), File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          current_source = File.binread(filepath)
          raise FixError, "source changed while planning fix" unless Digest::SHA256.digest(current_source) == expected_digest

          backup_file(filepath) if Bullematic.configuration&.backup
          mode = File.stat(filepath).mode
          Tempfile.create([".bullematic", ".tmp"], File.dirname(filepath)) do |tempfile|
            tempfile.binmode
            tempfile.write(source)
            tempfile.flush
            tempfile.fsync
            File.chmod(mode, tempfile.path)
            File.rename(tempfile.path, filepath)
          end
          begin
            File.open(File.dirname(filepath), File::RDONLY, &:fsync)
          rescue Errno::EACCES, Errno::EINVAL, Errno::EISDIR
            # Directory fsync is unavailable on some filesystems and Windows.
          end
        end
      end

      # @rbs filepath: String
      # @rbs return: void
      def backup_file(filepath)
        backup_path = "#{filepath}.bullematic.bak"
        FileUtils.cp(filepath, backup_path) unless File.exist?(backup_path)
      end
    end
  end
end
