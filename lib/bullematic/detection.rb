# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  class Detection
    # @rbs @type: Symbol
    # @rbs @base_class: untyped
    # @rbs @associations: Array[Symbol]
    # @rbs @call_stack: Array[String]
    # @rbs @source_file: String?
    # @rbs @line_number: Integer?
    # @rbs @method_name: String?

    # @rbs!
    #   attr_reader type: Symbol
    #   attr_reader base_class: untyped
    #   attr_reader associations: Array[Symbol]
    #   attr_reader call_stack: Array[String]
    #   attr_reader source_file: String?
    #   attr_reader line_number: Integer?
    #   attr_reader method_name: String?
    attr_reader :type, :base_class, :associations, :call_stack,
                :source_file, :line_number, :method_name

    # @rbs type: Symbol
    # @rbs base_class: untyped
    # @rbs associations: untyped
    # @rbs call_stack: Array[String]
    # @rbs return: void
    def initialize(type:, base_class:, associations:, call_stack:)
      @type = type
      @base_class = base_class
      @associations = normalize_associations(associations)
      @call_stack = call_stack
      parse_source_location
    end

    #: () -> String
    def model_class_name
      base_class.to_s
    end

    #: () -> bool
    def fixable?
      !source_file.nil? &&
        !source_file.empty? &&
        !associations.empty? &&
        target_path? &&
        !skip_path?
    end

    #: () -> Array[untyped]
    def fingerprint
      [source_file, line_number, model_class_name, associations.sort]
    end

    private

    # @rbs assocs: untyped
    # @rbs return: Array[Symbol]
    def normalize_associations(assocs)
      Array(assocs).filter_map do |association|
        association.to_sym if association.is_a?(String) || association.is_a?(Symbol)
      end.uniq
    end

    #: () -> void
    def parse_source_location
      config = Bullematic.configuration
      return unless config

      target_paths = config.target_paths

      @call_stack.each do |raw_frame|
        frame = raw_frame.to_s

        match = frame.match(/\A(.+):(\d+)(?::in `(.+)')?/)
        next unless match

        filepath = match[1]
        line = match[2].to_i
        method = match[3]

        next unless filepath && target_paths.any? { |path| filepath.include?(path) }

        @source_file = filepath
        @line_number = line
        @method_name = method
        break
      end
    end

    #: () -> bool
    def target_path?
      return false if source_file.nil?

      config = Bullematic.configuration
      return false unless config

      config.target_paths.any? do |path|
        source_file&.include?(path)
      end
    end

    #: () -> bool
    def skip_path?
      return false if source_file.nil?

      config = Bullematic.configuration
      return false unless config

      config.skip_paths.any? do |path|
        source_file&.include?(path)
      end
    end
  end
end
