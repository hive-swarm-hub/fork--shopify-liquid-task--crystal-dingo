# frozen_string_literal: true

module Liquid
  class ParseContext
    # Global expression cache shared across all template parses with default options.
    # Stores frozen VariableLookup/RangeLookup objects keyed by markup string.
    GLOBAL_EXPRESSION_CACHE = {}

    # Cached default locale to avoid allocating I18n.new per parse
    @default_locale = nil
    def self.default_locale
      @default_locale ||= I18n.new
    end

    attr_accessor :locale, :line_number, :trim_whitespace, :depth
    attr_reader :partial, :error_mode, :environment, :expression_cache, :string_scanner, :cursor, :variable_cacheable

    def warnings
      @warnings.equal?(Const::EMPTY_ARRAY) ? (@warnings = []) : @warnings
    end

    def initialize(options = Const::EMPTY_HASH)
      @environment = options.fetch(:environment, Environment.default)
      # Avoid dup for empty or minimal options
      @template_options = if options.empty? || options.frozen?
        { environment: @environment }
      else
        options.dup
      end

      @locale   = @template_options[:locale] ||= self.class.default_locale
      @warnings = Const::EMPTY_ARRAY

      # constructing new StringScanner in Lexer, Tokenizer, etc is expensive
      # This StringScanner will be shared by all of them
      @string_scanner = StringScanner.new("")

      # Use global expression cache for default options (no user-provided cache)
      ec = options[:expression_cache]
      if ec.nil? && !options.key?(:expression_cache)
        @expression_cache = GLOBAL_EXPRESSION_CACHE
        @variable_cacheable = true
      elsif ec.nil?
        # Explicitly passed nil: use global cache
        @expression_cache = GLOBAL_EXPRESSION_CACHE
        @variable_cacheable = true
      elsif ec.respond_to?(:[]) && ec.respond_to?(:[]=)
        @expression_cache = ec
        @variable_cacheable = false
      elsif ec
        @expression_cache = {}
        @variable_cacheable = false
      else
        # expression_cache: false — disable caching
        @expression_cache = nil
        @variable_cacheable = false
      end

      @cursor = Cursor.new("")

      self.depth   = 0
      self.partial = false
    end

    def [](option_key)
      @options[option_key]
    end

    def new_block_body
      Liquid::BlockBody.new
    end

    def new_parser(input)
      @string_scanner.string = input
      Parser.new(@string_scanner)
    end

    def new_tokenizer(source, start_line_number: nil, for_liquid_tag: false)
      Tokenizer.new(
        source: source,
        string_scanner: @string_scanner,
        line_number: start_line_number,
        for_liquid_tag: for_liquid_tag,
      )
    end

    def safe_parse_expression(parser)
      Expression.safe_parse(parser, @string_scanner, @expression_cache)
    end

    def parse_expression(markup, safe: false)
      if !safe && @error_mode == :strict2
        # parse_expression is a widely used API. To maintain backward
        # compatibility while raising awareness about strict2 parser standards,
        # the safe flag supports API users make a deliberate decision.
        #
        # In strict2 mode, markup MUST come from a string returned by the parser
        # (e.g., parser.expression). We're not calling the parser here to
        # prevent redundant parser overhead.
        raise Liquid::InternalError, "unsafe parse_expression cannot be used in strict2 mode"
      end

      Expression.parse(markup, @string_scanner, @expression_cache)
    end

    def partial=(value)
      @partial = value
      @options = value ? partial_options : @template_options

      @error_mode = @options[:error_mode] || @environment.error_mode
    end

    def partial_options
      @partial_options ||= begin
        dont_pass = @template_options[:include_options_blacklist]
        if dont_pass == true
          { locale: locale }
        elsif dont_pass.is_a?(Array)
          @template_options.reject { |k, _v| dont_pass.include?(k) }
        else
          @template_options
        end
      end
    end
  end
end
