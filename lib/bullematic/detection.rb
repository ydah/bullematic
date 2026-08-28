# rbs_inline: enabled
# frozen_string_literal: true

require "pathname"

module Bullematic
  class Detection
    # @rbs @type: Symbol
    # @rbs @base_class: untyped
    # @rbs @associations: Array[Symbol]
    # @rbs @call_stack: Array[String]
    # @rbs @source_file: String?
    # @rbs @line_number: Integer?
    # @rbs @method_name: String?
    # @rbs @context_id: untyped

    # @rbs!
    #   attr_reader type: Symbol
    #   attr_reader base_class: untyped
    #   attr_reader associations: Array[Symbol]
    #   attr_reader call_stack: Array[String]
    #   attr_reader source_file: String?
    #   attr_reader line_number: Integer?
    #   attr_reader method_name: String?
    #   attr_reader context_id: untyped
    attr_reader :type, :base_class, :associations, :call_stack,
                :source_file, :line_number, :method_name, :context_id

    # @rbs type: Symbol
    # @rbs base_class: untyped
    # @rbs associations: untyped
    # @rbs call_stack: Array[String]
    # @rbs context_id: untyped
    # @rbs return: void
    def initialize(type:, base_class:, associations:, call_stack:, context_id: nil)
      @type = type
      @base_class = base_class
      @associations = normalize_associations(associations)
      @call_stack = call_stack
      @context_id = context_id
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
      [context_id, source_file, line_number, model_class_name, associations.sort]
    end

    private

    # @rbs assocs: untyped
    # @rbs return: Array[Symbol]
    def normalize_associations(assocs)
      values = Array(assocs) #: Array[untyped]
      values.filter_map do |association|
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

        match = frame.match(/\A(.+):(\d+)(?::in [`'](.+)')?\z/)
        next unless match

        filepath = match[1]
        line = match[2].to_i
        method = match[3]

        next unless filepath && path_in?(filepath, target_paths)

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

      path_in?(source_file, config.target_paths)
    end

    #: () -> bool
    def skip_path?
      return false if source_file.nil?

      config = Bullematic.configuration
      return false unless config

      path_in?(source_file, config.skip_paths)
    end

    # @rbs filepath: String
    # @rbs paths: Array[String]
    # @rbs return: bool
    def path_in?(filepath, paths)
      source = expand_path(filepath)

      paths.any? do |path|
        next false unless path.is_a?(String) && !path.empty?

        target = expand_path(path)
        source == target || source.to_s.start_with?("#{target}#{File::SEPARATOR}")
      end
    end

    # @rbs path: String
    # @rbs return: Pathname
    def expand_path(path)
      pathname = Pathname.new(path)
      expanded = if pathname.absolute?
                   pathname.expand_path
                 else
                   root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root : Dir.pwd
                   Pathname.new(root).join(pathname).expand_path
                 end
      return expanded unless expanded.exist?

      begin
        expanded.realpath
      rescue Errno::ENOENT, Errno::EACCES
        expanded
      end
    end
  end
end
