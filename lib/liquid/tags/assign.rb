# frozen_string_literal: true

module Liquid
  # @liquid_public_docs
  # @liquid_type tag
  # @liquid_category variable
  # @liquid_name assign
  # @liquid_summary
  #   Creates a new variable.
  # @liquid_description
  #   You can create variables of any [basic type](/docs/api/liquid/basics#types), [object](/docs/api/liquid/objects), or object property.
  #
  #   > Caution:
  #   > Predefined Liquid objects can be overridden by variables with the same name.
  #   > To make sure that you can access all Liquid objects, make sure that your variable name doesn't match a predefined object's name.
  # @liquid_syntax
  #   {% assign variable_name = value %}
  # @liquid_syntax_keyword variable_name The name of the variable being created.
  # @liquid_syntax_keyword value The value you want to assign to the variable.
  class Assign < Tag
    Syntax = /(#{VariableSignature}+)\s*=\s*(.*)\s*/om

    # @api private
    def self.raise_syntax_error(parse_context)
      raise Liquid::SyntaxError, parse_context.locale.t('errors.syntax.assign')
    end

    attr_reader :to, :from

    # Cache for Assign Variable objects by the expression part
    ASSIGN_VAR_CACHE = {}

    def initialize(tag_name, markup, parse_context)
      super
      # Fast byte-level parse: find "name = expression"
      len = markup.bytesize
      pos = 0
      # Skip leading whitespace
      pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9)
      # Scan identifier for @to
      to_start = pos
      b = pos < len ? markup.getbyte(pos) : nil
      if b && ((b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95)
        pos += 1
        while pos < len
          b = markup.getbyte(pos)
          break unless (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 95 || b == 45
          pos += 1
        end
        @to = markup.byteslice(to_start, pos - to_start)
        # Skip whitespace
        pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9)
        # Expect '='
        if pos < len && markup.getbyte(pos) == 61 # '='
          pos += 1
          # Skip whitespace after '='
          pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9)
          from_markup = pos < len ? markup.byteslice(pos, len - pos).rstrip : ""
          em = parse_context.error_mode
          cacheable = parse_context.variable_cacheable && em != :strict && em != :strict2 && em != :rigid
          if cacheable && (cached = ASSIGN_VAR_CACHE[from_markup])
            @from = cached
          else
            @from = Variable.new(from_markup, parse_context)
            ASSIGN_VAR_CACHE[from_markup] = @from if cacheable
          end
          return
        end
      end
      # Fallback to regex
      if markup =~ Syntax
        @to = Regexp.last_match(1)
        @from = Variable.new(Regexp.last_match(2), parse_context)
      else
        self.class.raise_syntax_error(parse_context)
      end
    end

    def render_to_output_buffer(context, output)
      val = @from.render(context)
      context.scopes.last[@to] = val
      context.resource_limits.increment_assign_score(assign_score_of(val))
      output
    end

    def blank?
      true
    end

    private

    def assign_score_of(val)
      if val.instance_of?(String)
        val.bytesize
      elsif val.instance_of?(Array)
        sum = 1
        # Uses #each to avoid extra allocations.
        val.each { |child| sum += assign_score_of(child) }
        sum
      elsif val.instance_of?(Hash)
        sum = 1
        val.each do |key, entry_value|
          sum += assign_score_of(key)
          sum += assign_score_of(entry_value)
        end
        sum
      else
        1
      end
    end

    class ParseTreeVisitor < Liquid::ParseTreeVisitor
      def children
        [@node.from]
      end
    end
  end
end
