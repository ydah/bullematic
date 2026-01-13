# rbs_inline: enabled
# frozen_string_literal: true

require "fileutils"

module Bullematic
  class Fixer
    class << self
      #: () -> Array[Detection]
      def detection_queue
        @detection_queue ||= [] #: Array[Detection]
      end

      # @rbs detection: Detection
      # @rbs return: void
      def queue(detection)
        detection_queue << detection
      end

      #: () -> void
      def clear
        @detection_queue = [] #: Array[Detection]
      end

      #: () -> void
      def apply_fixes
        return if detection_queue.empty?

        logger = BullematicLogger.new

        grouped = detection_queue.group_by(&:source_file)

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
        clear
      end

      private

      # @rbs filepath: String
      # @rbs detections: Array[Detection]
      # @rbs logger: BullematicLogger
      # @rbs return: void
      def process_file(filepath, detections, logger)
        return unless File.exist?(filepath)

        original_source = File.read(filepath)
        parse_result = AST::Parser.parse_file(filepath)
        finder = AST::Finder.new(parse_result)
        rewriter = AST::Rewriter.new(original_source)

        detections.each do |detection|
          location = find_query_location(finder, detection)

          if location.nil?
            logger.log_skip(filepath, detection, "could not locate query")
            next
          end

          rewriter.add_includes(location, detection.associations)
          logger.log_fix(filepath, detection)
        end

        new_source = rewriter.rewrite

        return if new_source == original_source

        if Bullematic.configuration&.dry_run
          logger.log_dry_run(filepath, original_source, new_source)
        else
          backup_file(filepath) if Bullematic.configuration&.backup
          File.write(filepath, new_source)
        end
      end

      # @rbs finder: AST::Finder
      # @rbs detection: Detection
      # @rbs return: AST::Finder::QueryLocation?
      def find_query_location(finder, detection)
        queries = finder.find_model_queries(
          detection.model_class_name,
          line_number: detection.line_number
        )

        return queries.first unless queries.empty?

        return nil unless detection.line_number

        finder.find_query_at_line(detection.line_number)
      end

      # @rbs filepath: String
      # @rbs return: void
      def backup_file(filepath)
        backup_path = "#{filepath}.bullematic.bak"
        FileUtils.cp(filepath, backup_path)
      end
    end
  end
end
