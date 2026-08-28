# rbs_inline: enabled
# frozen_string_literal: true

require "set"

module Bullematic
  module AST
    class Finder
      QUERY_METHODS = %i[all where find find_by first last order limit offset].freeze #: Array[Symbol]

      # @rbs!
      #   type query_location = { node: untyped, location: untyped, receiver: untyped, method_name: Symbol, target_name: Symbol? }

      QueryLocation = Struct.new(:node, :location, :receiver, :method_name, :target_name, keyword_init: true)

      # @rbs @parse_result: untyped

      # @rbs!
      #   attr_reader parse_result: untyped
      attr_reader :parse_result

      # @rbs parse_result: untyped
      # @rbs return: void
      def initialize(parse_result)
        @parse_result = parse_result
      end

      # @rbs model_class_name: String
      # @rbs line_number: Integer?
      # @rbs return: Array[QueryLocation]
      def find_model_queries(model_class_name, line_number: nil)
        queries = [] #: Array[QueryLocation]
        visit_node(parse_result.value, queries, model_class_name, line_number)
        queries
      end

      # @rbs model_class_name: String
      # @rbs line_number: Integer
      # @rbs associations: Array[Symbol]
      # @rbs return: Array[QueryLocation]
      def find_model_queries_for_variables_at_line(model_class_name, line_number, associations)
        names = association_receiver_names_at_line(parse_result.value, line_number, associations)
        add_block_receiver_names(parse_result.value, line_number, names)
        scope = method_scope_at_line(parse_result.value, line_number)
        find_model_queries(model_class_name).select do |query|
          query.target_name &&
            names.include?(query.target_name) &&
            !block_parameter_at_line?(parse_result.value, query.target_name, line_number) &&
            query.location.end_line <= line_number &&
            method_scope_at_line(parse_result.value, query.location.start_line).equal?(scope) &&
            !variable_written_between?(scope || parse_result.value, query.target_name, query.location.end_line, line_number, scope)
        end
      end

      # @rbs parent_association: Symbol
      # @rbs child_associations: Array[Symbol]
      # @rbs line_number: Integer?
      # @rbs return: bool
      def nested_association?(parent_association, child_associations, line_number)
        return false unless line_number

        nested_association_in_node?(parse_result.value, parent_association, child_associations, line_number)
      end

      private

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs skip_nodes: Set[Integer]
      # @rbs return: void
      def visit_node(node, queries, model_class_name, target_line, skip_nodes = Set.new)
        return unless node.respond_to?(:child_nodes)
        return if skip_nodes.include?(node.object_id)

        case node
        when Prism::InstanceVariableWriteNode, Prism::LocalVariableWriteNode
          if check_assignment_node(node, queries, model_class_name, target_line)
            mark_descendant_calls(node.value, skip_nodes)
          end
        when Prism::CallNode
          check_call_node(node, queries, model_class_name, target_line)
        end

        node.child_nodes.compact.each do |child|
          visit_node(child, queries, model_class_name, target_line, skip_nodes)
        end
      end

      # @rbs node: untyped
      # @rbs skip_nodes: Set[Integer]
      # @rbs return: void
      def mark_descendant_calls(node, skip_nodes)
        return unless node.respond_to?(:child_nodes)

        skip_nodes.add(node.object_id) if node.is_a?(Prism::CallNode)

        node.child_nodes.compact.each do |child|
          mark_descendant_calls(child, skip_nodes)
        end
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs return: void
      def check_call_node(node, queries, model_class_name, target_line)
        return unless query_method?(node.name)
        return if target_line && node.location.start_line != target_line

        root_receiver = find_root_receiver(node)
        return unless model_constant?(root_receiver, model_class_name)

        queries << QueryLocation.new(
          node: node,
          location: node.location,
          receiver: root_receiver,
          method_name: node.name
        )
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs return: bool
      def check_assignment_node(node, queries, model_class_name, target_line)
        return false if target_line && node.location.start_line != target_line

        value = node.value
        return false unless value.is_a?(Prism::CallNode)
        return false unless query_method?(value.name)

        root_receiver = find_root_receiver(value)
        return false unless model_constant?(root_receiver, model_class_name)

        queries << QueryLocation.new(
          node: value,
          location: value.location,
          receiver: root_receiver,
          method_name: value.name,
          target_name: node.name
        )
        true
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs associations: Array[Symbol]
      # @rbs return: Array[Symbol]
      def association_receiver_names_at_line(node, line_number, associations)
        return [] unless node.respond_to?(:child_nodes)

        names = [] #: Array[Symbol]
        if node.is_a?(Prism::CallNode) && associations.include?(node.name) && node.location.start_line == line_number
          receiver = find_root_receiver(node)
          if receiver.is_a?(Prism::InstanceVariableReadNode) || receiver.is_a?(Prism::LocalVariableReadNode)
            names << receiver.name
          end
        end
        node.child_nodes.compact.each do |child|
          names.concat(association_receiver_names_at_line(child, line_number, associations))
        end
        names.uniq
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs names: Array[Symbol]
      # @rbs return: void
      def add_block_receiver_names(node, line_number, names)
        return unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && node.block &&
           line_number.between?(node.block.location.start_line, node.block.location.end_line)
          parameters = node.block.parameters&.parameters&.requireds || []
          receiver = node.receiver
          if parameters.any? { |parameter| names.include?(parameter.name) } &&
             (receiver.is_a?(Prism::InstanceVariableReadNode) || receiver.is_a?(Prism::LocalVariableReadNode))
            names << receiver.name
          end
        end

        node.child_nodes.compact.each { |child| add_block_receiver_names(child, line_number, names) }
        names.uniq!
      end

      # @rbs node: untyped
      # @rbs name: Symbol
      # @rbs line_number: Integer
      # @rbs return: bool
      def block_parameter_at_line?(node, name, line_number)
        return false unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && node.block &&
           line_number.between?(node.block.location.start_line, node.block.location.end_line)
          parameters = node.block.parameters&.parameters&.requireds || []
          return true if parameters.any? { |parameter| parameter.name == name }
        end

        node.child_nodes.compact.any? { |child| block_parameter_at_line?(child, name, line_number) }
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs return: untyped
      def method_scope_at_line(node, line_number)
        return unless node.respond_to?(:child_nodes)
        return unless line_number.between?(node.location.start_line, node.location.end_line)

        node.child_nodes.compact.each do |child|
          scope = method_scope_at_line(child, line_number)
          return scope if scope
        end
        node if node.is_a?(Prism::DefNode)
      end

      # @rbs node: untyped
      # @rbs name: Symbol
      # @rbs start_line: Integer
      # @rbs end_line: Integer
      # @rbs scope: untyped
      # @rbs return: bool
      def variable_written_between?(node, name, start_line, end_line, scope)
        return false unless node.respond_to?(:child_nodes)
        return false if node.is_a?(Prism::DefNode) && !node.equal?(scope)

        written = node.respond_to?(:name) && node.name == name &&
                  node.class.name.match?(/\APrism::(?:Instance|Local)Variable(?:And|Operator|Or)?WriteNode\z/) &&
                  node.location.start_line > start_line && node.location.start_line <= end_line
        written || node.child_nodes.compact.any? do |child|
          variable_written_between?(child, name, start_line, end_line, scope)
        end
      end

      # @rbs node: untyped
      # @rbs return: untyped
      def find_root_receiver(node)
        current = node
        current = current.receiver while current.is_a?(Prism::CallNode) && current.receiver
        current
      end

      # @rbs node: untyped
      # @rbs model_class_name: String
      # @rbs return: bool
      def model_constant?(node, model_class_name)
        return false unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

        node.full_name.delete_prefix("::") == model_class_name.delete_prefix("::")
      end

      # @rbs method_name: Symbol
      # @rbs return: bool
      def query_method?(method_name)
        QUERY_METHODS.include?(method_name)
      end

      # @rbs node: untyped
      # @rbs parent_association: Symbol
      # @rbs child_associations: Array[Symbol]
      # @rbs line_number: Integer
      # @rbs return: bool
      def nested_association_in_node?(node, parent_association, child_associations, line_number)
        return false unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && %i[each find_each].include?(node.name) && node.block &&
           receiver_calls?(node.receiver, parent_association)
          parameters = node.block.parameters&.parameters&.requireds || []
          names = parameters.map(&:name)
          return true if !variable_written?(node.block.body, names) && child_associations.all? do |association|
            call_on_variable_at_line?(node.block.body, association, names, line_number)
          end
        end

        node.child_nodes.compact.any? do |child|
          nested_association_in_node?(child, parent_association, child_associations, line_number)
        end
      end

      # @rbs node: untyped
      # @rbs method_name: Symbol
      # @rbs names: Array[Symbol]
      # @rbs line_number: Integer
      # @rbs return: bool
      def call_on_variable_at_line?(node, method_name, names, line_number)
        return false unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && node.name == method_name && node.location.start_line == line_number
          receiver = find_root_receiver(node)
          return true if receiver.is_a?(Prism::LocalVariableReadNode) && names.include?(receiver.name)
        end

        if node.is_a?(Prism::CallNode) && node.block
          parameters = node.block.parameters&.parameters&.requireds || []
          return false if parameters.any? { |parameter| parameter.respond_to?(:name) && names.include?(parameter.name) }
        end

        node.child_nodes.compact.any? do |child|
          call_on_variable_at_line?(child, method_name, names, line_number)
        end
      end

      # @rbs node: untyped
      # @rbs method_name: Symbol
      # @rbs return: bool
      def receiver_calls?(node, method_name)
        current = node
        while current.is_a?(Prism::CallNode)
          return true if current.name == method_name

          current = current.receiver
        end
        false
      end

      # @rbs node: untyped
      # @rbs names: Array[Symbol]
      # @rbs return: bool
      def variable_written?(node, names)
        return false unless node.respond_to?(:child_nodes)
        return true if node.is_a?(Prism::LocalVariableWriteNode) && names.include?(node.name)

        node.child_nodes.compact.any? { |child| variable_written?(child, names) }
      end
    end
  end
end
