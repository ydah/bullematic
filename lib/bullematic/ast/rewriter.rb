# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module AST
    class Rewriter
      # @rbs!
      #   type modification = { type: Symbol, offset: Integer, byte_length: Integer, new_text: String, associations: Array[Symbol] }

      Modification = Struct.new(:type, :offset, :byte_length, :new_text, :associations, keyword_init: true)

      # @rbs @source: String
      # @rbs @modifications: Array[Modification]

      # @rbs!
      #   attr_reader source: String
      #   attr_reader modifications: Array[Modification]
      attr_reader :source, :modifications

      # @rbs source: String
      # @rbs return: void
      def initialize(source)
        @source = source.dup
        @modifications = []
      end

      # @rbs query_location: Finder::QueryLocation
      # @rbs associations: Array[Symbol]
      # @rbs return: void
      def add_includes(query_location, associations)
        existing_call = find_includes_call(query_location.node)
        if existing_call
          existing = extract_associations_from_call(existing_call)
          return if associations.all? { |assoc| existing.include?(assoc) }

          merged = (existing + associations).uniq
          args_location = existing_call.arguments&.location
          return unless args_location

          @modifications << Modification.new(
            type: :replace,
            offset: args_location.start_offset,
            byte_length: args_location.end_offset - args_location.start_offset,
            new_text: format_associations(merged),
            associations: associations
          )
          return
        end

        return if already_has_includes?(query_location, associations)

        strategy = Bullematic.configuration&.fix_strategy || :includes
        insert_point = find_insert_point(query_location)

        assoc_string = format_associations(associations)
        new_text = ".#{strategy}(#{assoc_string})"

        @modifications << Modification.new(
          type: :insert,
          offset: insert_point,
          byte_length: 0,
          new_text: new_text,
          associations: associations
        )
      end

      #: () -> String
      def rewrite
        return @source if @modifications.empty?

        sorted = @modifications.sort_by { |m| -m.offset }

        result = @source.dup
        sorted.each do |mod|
          case mod.type
          when :insert
            result.insert(mod.offset, mod.new_text)
          when :replace
            result[mod.offset, mod.byte_length] = mod.new_text
          when :delete
            result[mod.offset, mod.byte_length] = ""
          end
        end

        result
      end

      private

      # @rbs query_location: Finder::QueryLocation
      # @rbs return: Integer
      def find_insert_point(query_location)
        node = query_location.node
        receiver = query_location.receiver

        if receiver.is_a?(Prism::ConstantReadNode)
          receiver.location.end_offset
        else
          find_chain_insert_point(node)
        end
      end

      # @rbs node: untyped
      # @rbs return: Integer
      def find_chain_insert_point(node)
        current = node
        current = current.receiver while current.is_a?(Prism::CallNode) && current.receiver.is_a?(Prism::CallNode)

        if current.receiver
          current.receiver.location.end_offset
        else
          current.location.start_offset
        end
      end

      # @rbs query_location: Finder::QueryLocation
      # @rbs associations: Array[Symbol]
      # @rbs return: bool
      def already_has_includes?(query_location, associations)
        existing = find_existing_includes(query_location.node)
        return false if existing.empty?

        associations.all? { |assoc| existing.include?(assoc) }
      end

      # @rbs node: untyped
      # @rbs return: Array[Symbol]
      def find_existing_includes(node)
        includes = [] #: Array[Symbol]
        current = node

        while current.is_a?(Prism::CallNode)
          if %i[includes preload eager_load].include?(current.name)
            includes.concat(extract_associations_from_call(current))
          end
          current = current.receiver
        end

        includes
      end

      # @rbs node: untyped
      # @rbs return: Prism::CallNode?
      def find_includes_call(node)
        current = node
        while current.is_a?(Prism::CallNode)
          return current if %i[includes preload eager_load].include?(current.name)

          current = current.receiver
        end
        nil
      end

      # @rbs call_node: untyped
      # @rbs return: Array[Symbol]
      def extract_associations_from_call(call_node)
        return [] unless call_node.arguments

        associations = [] #: Array[Symbol]
        call_node.arguments.arguments.each do |arg|
          case arg
          when Prism::SymbolNode
            associations << arg.value.to_sym
          when Prism::ArrayNode
            arg.elements.each do |elem|
              associations << elem.value.to_sym if elem.is_a?(Prism::SymbolNode)
            end
          end
        end
        associations
      end

      # @rbs associations: Array[Symbol]
      # @rbs return: String
      def format_associations(associations)
        if associations.size == 1
          ":#{associations.first}"
        else
          associations.map { |a| ":#{a}" }.join(", ")
        end
      end
    end
  end
end
