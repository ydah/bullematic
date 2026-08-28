# rbs_inline: enabled
# frozen_string_literal: true

require "pathname"
require "digest"

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
    # @rbs @source_digest: String?

    # @rbs!
    #   attr_reader type: Symbol
    #   attr_reader base_class: untyped
    #   attr_reader associations: Array[Symbol]
    #   attr_reader call_stack: Array[String]
    #   attr_reader source_file: String?
    #   attr_reader line_number: Integer?
    #   attr_reader method_name: String?
    #   attr_reader context_id: untyped
    #   attr_reader source_digest: String?
    attr_reader :type, :base_class, :associations, :call_stack,
                :source_file, :line_number, :method_name, :context_id, :source_digest

    # @rbs type: Symbol
    # @rbs base_class: untyped
    # @rbs associations: untyped
    # @rbs call_stack: Array[String]
    # @rbs context_id: untyped
    # @rbs source_digest: String?
    # @rbs return: void
    def initialize(type:, base_class:, associations:, call_stack:, context_id: nil, source_digest: nil)
      @type = type
      @base_class = base_class
      @associations = normalize_associations(associations)
      @call_stack = call_stack
      @context_id = context_id
      parse_source_location
      @source_digest = source_digest || current_source_digest
    end

    # @rbs data: Hash[String, untyped]
    # @rbs return: Detection
    def self.from_h(data)
      type = data.fetch("type").to_s.to_sym
      associations = data.fetch("associations")
      call_stack = data.fetch("call_stack")
      raise ArgumentError, "invalid evidence type" unless %i[n_plus_one unused_eager_loading].include?(type)
      raise ArgumentError, "invalid evidence associations" unless associations.is_a?(Array)
      raise ArgumentError, "invalid evidence call stack" unless call_stack.is_a?(Array)
      source_digest = data["source_digest"]
      raise ArgumentError, "invalid evidence source digest" unless source_digest.is_a?(String) && source_digest.match?(/\A[0-9a-f]{64}\z/)

      new(
        type: type,
        base_class: data.fetch("base_class"),
        associations: associations,
        call_stack: call_stack,
        context_id: data["context_id"],
        source_digest: source_digest
      )
    end

    # @rbs return: Hash[String, untyped]
    def to_h
      {
        "type" => type.to_s,
        "base_class" => model_class_name,
        "associations" => associations.map(&:to_s),
        "call_stack" => call_stack.map(&:to_s),
        "context_id" => context_id,
        "source_digest" => source_digest
      }
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
      [type, context_id, source_file, line_number, model_class_name, associations.sort]
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

        @source_file = absolute_path(filepath).to_s
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
      expanded = absolute_path(path)
      return expanded unless expanded.exist?

      begin
        expanded.realpath
      rescue Errno::ENOENT, Errno::EACCES
        expanded
      end
    end

    # @rbs path: String
    # @rbs return: Pathname
    def absolute_path(path)
      pathname = Pathname.new(path)
      return pathname if path.match?(%r{\A[A-Za-z]:[\\/]})
      return pathname.expand_path if pathname.absolute?

      root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root : Dir.pwd
      Pathname.new(root).join(pathname).expand_path
    end

    # @rbs return: String?
    def current_source_digest
      return unless source_file && File.file?(source_file)

      Digest::SHA256.hexdigest(File.binread(source_file))
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
