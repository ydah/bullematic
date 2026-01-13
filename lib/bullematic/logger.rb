# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  class BullematicLogger
    # @rbs @logger: Logger
    # @rbs @stats: Hash[Symbol, Integer]

    # @rbs!
    #   attr_reader stats: Hash[Symbol, Integer]
    attr_reader :stats

    # @rbs logger: Logger?
    # @rbs return: void
    def initialize(logger = nil)
      @logger = logger || Bullematic.configuration&.logger || ::Logger.new($stdout)
      @stats = { fixed: 0, skipped: 0, errors: 0 }
    end

    # @rbs message: String
    # @rbs return: void
    def info(message)
      @logger.info("[Bullematic] #{message}")
    end

    # @rbs message: String
    # @rbs return: void
    def warn(message)
      @logger.warn("[Bullematic] #{message}")
    end

    # @rbs message: String
    # @rbs return: void
    def error(message)
      @logger.error("[Bullematic] #{message}")
    end

    # @rbs message: String
    # @rbs return: void
    def debug(message)
      return unless Bullematic.configuration&.debug

      @logger.debug("[Bullematic] #{message}")
    end

    # @rbs filepath: String
    # @rbs detection: Detection
    # @rbs return: void
    def log_fix(filepath, detection)
      @stats[:fixed] += 1
      info("Fixed N+1 query in #{filepath}:#{detection.line_number}")
      info("  Model: #{detection.model_class_name}")
      info("  Association: #{detection.associations.inspect}")
    end

    # @rbs filepath: String
    # @rbs detection: Detection
    # @rbs reason: String
    # @rbs return: void
    def log_skip(filepath, detection, reason)
      @stats[:skipped] += 1
      warn("Skipped #{filepath}:#{detection.line_number} (#{reason})")
      warn("  Model: #{detection.model_class_name}")
      warn("  Association: #{detection.associations.inspect}")
    end

    # @rbs filepath: String
    # @rbs err: Exception
    # @rbs return: void
    def log_error(filepath, err)
      @stats[:errors] += 1
      error("Error processing #{filepath}: #{err.message}")
    end

    # @rbs filepath: String
    # @rbs original: String
    # @rbs modified: String
    # @rbs return: void
    def log_dry_run(filepath, original, modified)
      info("[DRY RUN] Would modify #{filepath}:")

      original_lines = original.lines
      modified_lines = modified.lines

      modified_lines.each_with_index do |line, idx|
        next if original_lines[idx] == line

        info("  - #{original_lines[idx]&.chomp}")
        info("  + #{line.chomp}")
      end
    end

    #: () -> void
    def log_summary
      info("Summary: #{@stats[:fixed]} fixed, #{@stats[:skipped]} skipped, #{@stats[:errors]} errors")
    end

    #: () -> void
    def reset_stats
      @stats = { fixed: 0, skipped: 0, errors: 0 }
    end
  end
end
