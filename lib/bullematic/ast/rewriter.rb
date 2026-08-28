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
      # @rbs return: Symbol
      def add_includes(query_location, associations)
        associations = associations.uniq
        return :unsupported if associations.empty?

        existing_call = find_includes_call(query_location.node)
        if existing_call
          existing = extract_associations_from_call(existing_call)
          return :already_present if associations.all? { |assoc| existing.include?(assoc) }
        end

        return :already_present if already_has_includes?(query_location, associations)

        strategy = Bullematic.configuration&.fix_strategy || :includes
        insert_point = find_insert_point(query_location)
        pending = @modifications.find { |mod| mod.type == :insert && mod.offset == insert_point }
        if pending
          pending.associations = (pending.associations + associations).uniq
          pending.new_text = ".#{strategy}(#{format_associations(pending.associations)})"
          return :changed
        end

        assoc_string = format_associations(associations)
        new_text = ".#{strategy}(#{assoc_string})"

        @modifications << Modification.new(
          type: :insert,
          offset: insert_point,
          byte_length: 0,
          new_text: new_text,
          associations: associations
        )
        :changed
      end

      #: () -> String
      def rewrite
        return @source if @modifications.empty?

        validate_modifications!
        sorted = @modifications.sort_by { |m| -m.offset }

        result = @source.dup
        sorted.each do |mod|
          before = result.byteslice(0, mod.offset)
          after = result.byteslice(mod.offset + mod.byte_length..)
          replacement = mod.type == :delete ? "" : mod.new_text
          result = before + replacement + after
        end

        result
      end

      private

      # @rbs query_location: Finder::QueryLocation
      # @rbs return: Integer
      def find_insert_point(query_location)
        node = query_location.node
        receiver = query_location.receiver

        if receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)
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
        call_node.arguments.arguments.each { |arg| collect_literal_associations(arg, associations) }
        associations
      end

      # @rbs node: untyped
      # @rbs associations: Array[Symbol]
      # @rbs return: void
      def collect_literal_associations(node, associations)
        case node
        when Prism::SymbolNode
          associations << node.value.to_sym
        when Prism::ArrayNode
          node.elements.each { |element| collect_literal_associations(element, associations) }
        when Prism::KeywordHashNode, Prism::HashNode
          node.elements.each do |element|
            next unless element.is_a?(Prism::AssocNode)

            collect_literal_associations(element.key, associations)
            collect_literal_associations(element.value, associations)
          end
        end
      end

      # @rbs associations: Array[Symbol]
      # @rbs return: String
      def format_associations(associations)
        associations.map(&:inspect).join(", ")
      end

      #: () -> void
      def validate_modifications!
        @modifications.each do |modification|
          limit = modification.offset + modification.byte_length
          raise FixError, "edit is outside the source" if modification.offset.negative? || limit > @source.bytesize
        end

        ranges = @modifications.reject { |modification| modification.byte_length.zero? }
        ranges.combination(2) do |left, right|
          overlap = left.offset < right.offset + right.byte_length && right.offset < left.offset + left.byte_length
          raise FixError, "overlapping edits" if overlap
        end
      end
    end
  end
end
