# rbs_inline: enabled
# frozen_string_literal: true

require "prism"

module Bullematic
  module AST
    class Parser
      # @rbs @source_code: String
      # @rbs @filepath: String?

      class << self
        #: () -> Hash[String, untyped]
        def cache
          @cache ||= {} #: Hash[String, untyped]
        end

        #: () -> void
        def clear_cache
          @cache = {} #: Hash[String, untyped]
        end

        # @rbs filepath: String
        # @rbs return: untyped
        def parse_file(filepath)
          return cache[filepath] if cache.key?(filepath)

          result = Prism.parse_file(filepath)
          raise ParseError, result.errors.map(&:message).join("\n") if result.failure?

          cache[filepath] = result
          result
        end
      end

      # @rbs!
      #   attr_reader source_code: String
      #   attr_reader filepath: String?
      attr_reader :source_code, :filepath

      # @rbs source_code: String
      # @rbs filepath: String?
      # @rbs return: void
      def initialize(source_code, filepath: nil)
        @source_code = source_code
        @filepath = filepath
      end

      #: () -> untyped
      def parse
        result = Prism.parse(@source_code, filepath: @filepath)
        raise ParseError, result.errors.map(&:message).join("\n") if result.failure?

        result
      end
    end
  end
end
