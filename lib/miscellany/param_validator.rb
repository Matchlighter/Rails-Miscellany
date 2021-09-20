module Miscellany
  class ParamValidator
    attr_accessor :context, :errors
    attr_reader :params

    delegate_missing_to :context

    TIME_TYPES = [Date, DateTime, Time].freeze

    CHECKS = %i[type specified present default transform in block items pattern].freeze
    NON_PREFIXED = %i[default transform type message timezone].freeze
    PREFIXES = %i[all onem onep one none].freeze
    PREFIX_ALIASES = { any: :onep, not: :none, one_or_less: :onem, one_or_more: :onem }.freeze
    ALL_PREFIXES = (PREFIXES + PREFIX_ALIASES.keys).freeze
    VALID_FLAGS = %i[present specified].freeze

    def self.record_type(model, key: :id)
      Proc.new do |param, *args|
        model.find_by!(key => param)
      rescue ActiveRecord::RecordNotFound
        raise ArgumentError
      end
    end

    def initialize(block, context, parameters = nil)
      @block = block
      @context = context
      @params = parameters || context.params
      @errors = ErrorStore.new
    end

    def self.check(params, context: nil, &blk)
      pv = new(blk, context, params)
      pv.apply_checks
      pv.errors
    end

    def self.assert(params, context: nil, handle:, &blk)
      errors = check(params, context: context, &blk)
      if errors.present?
        handle.call(errors)
      else
        params
      end
    end

    def apply_checks(&blk)
      blk ||= @block
      args = trim_arguments(blk, [@params, :TODO])

      dresult = instance_exec(*args, &blk)
      dresult = "failed validation #{check}" if dresult == false
      if dresult.present? && dresult != true
        @errors.push(dresult)
      end
    end

    def parameter(param_keys, *args, **kwargs, &blk)
      param_keys = Array(param_keys)
      opts = normalize_opts(*args, **kwargs, &blk)

      checks = {}
      PREFIXES.each do |pfx|
        pfx_keys = opts[pfx]&.keys&.select { |k| opts[pfx][k] } || []
        pfx_keys.each do |k|
          checks[k] = pfx # TODO: Support filters connected to multiple prefixes
        end
        # TODO: warn if pfx != :all && param_keys.length == 1
      end
      NON_PREFIXED.each do |k|
        checks[k] = nil
      end

      all_results = {}
      param_keys.each do |pk|
        check_results = all_results[pk] = {}
        run_check = ->(check, &blk) { exec_check(check_results, check, checks, options: opts, &blk) }

        exec_check(check_results, :type) { coerce_type(params, pk, opts) } || next

        run_check[:specified] { params.key?(pk) || 'must be specified' } || next
        run_check[:present] { params[pk].present? || 'must be present' } || next

        # Set Default
        if params[pk].nil? && !opts[:default].nil?
          params[pk] ||= opts[:default].respond_to?(:call) ? opts[:default].call : opts[:default]
          next # We can assume that the default value is allowed
        end

        # Apply Transform
        params[pk] = opts[:transform].to_proc.call(params[pk]) if params.include?(pk) && opts[:transform]

        next if params[pk].nil?

        run_check[:pattern] do |pattern|
          return true if params[pk].to_s.match?(pattern)

          "must match pattern: #{pattern.inspect}"
        end

        run_check[:in] do |one_of|
          next true if one_of.include?(params[pk])

          if one_of.is_a?(Range)
            "must be between: #{one_of.begin}..#{one_of.end}"
          else
            "must be one of: #{one_of.to_a.join(', ')}"
          end
        end

        # Nested check
        run_check[:block] do |blk|
          ParamValidator.check(params[pk], context: context, &blk)
        end

        # Array Items check
        run_check[:items] do |blk|
          if params[pk].is_a?(Array)
            error_items = 0
            astore = ErrorStore.new

            params[pk].each_with_index do |v, i|
              errs = nil
              if blk.is_a?(Hash)
                pv = ParamValidator.new(nil, self.context, params[pk])
                pv.parameter(i, **blk)
                ers = pv.errors
              else
                errs = ParamValidator.check(params[pk][i], context: context, &blk)
              end

              if errs.present?
                error_items += 1
                if error_items > 5
                  check_results[:items]
                  astore.push("Too Many Errors")
                  break
                else
                  astore.push_to(i, errs)
                end
              end
            end

            astore
          else
            raise "items: validator can only be used with Arrays"
          end
        end
      end

      final_errors = ErrorStore.new
      checks.each do |check, check_prefix|
        if check_prefix == :all || check_prefix == nil
          all_results.each do |field, err_map|
            errs = err_map[check]
            next unless errs.present?

            final_errors.push_to(field, errs)
          end
        elsif check_prefix == :none
          all_results.each do |field, err_map|
            errs = err_map[check]
            final_errors.push_to(field, "must NOT be #{check}") unless errs.present?
          end
        else
          counts = check_pass_count(check, all_results)
          field_key = param_keys.join(', ')
          string_prefixes = {
            onep: 'One or more of',
            onem: 'At most one of',
            one: 'Exactly one of',
          }

          if (counts[:passed] != 1 && check_prefix == :one) ||
            (counts[:passed] > 1 && check_prefix == :onem) ||
            (counts[:passed] < 1 && check_prefix == :onep)

            final_errors.push("#{string_prefixes[check_prefix]} #{field_key} must be #{check}")
          end
        end
      end

      @errors.merge!(final_errors)

      nil
    end

    alias p parameter

    protected

    def check_pass_count(check, all_results)
      counts = { passed: 0, failed: 0, skipped: 0 }
      all_results.each do |_field, field_results|
        result = field_results[check]
        key = if result.nil?
                :skipped
              elsif result.present?
                :failed
              else
                :passed
              end
        counts[key] += 1
      end
      counts
    end

    def exec_check(state, check, checks_to_run = nil, options: nil, &blk)
      return true if checks_to_run && !checks_to_run[check] && !NON_PREFIXED.include?(check)

      # TODO: Support Running checks of the same type for different prefixes

      check_prefixes = NON_PREFIXED.include?(check) ? [nil] : Array(checks_to_run&.[](check))
      return true unless check_prefixes.present?

      encountered_errors = false

      check_prefixes.each do |check_prefix|
        prefixed_check = [check_prefix, check].compact.join('_')
        prefix_options = (check_prefix.nil? ? options : options&.[](check_prefix)) || {}

        result = blk.call(*trim_arguments(blk, [prefix_options[check]]))
        result = "failed validation #{check}" if result == false

        store = state[check] ||= ErrorStore.new

        if result.present? && result != true
          result = options[:message] if options&.[](:message).present?

          store.push(result)

          encountered_errors = true
        end
      end

      !encountered_errors
    end

    def coerce_type(params, key, opts)
      value = params[key]
      return nil if value.nil? || !opts[:type].present?

      types = Array(opts[:type])
      types.each do |t|
        params[key] = coerce_single_type(value, t, opts)
        return true
      rescue ArgumentError, TypeError => err
      end

      "'#{value}' could not be cast to a #{types.join(' or a ')}"
    end

    def coerce_single_type(param, type, options)
      return param if (param.is_a?(type) rescue false)

      if type.is_a?(Class) && type <= ActiveRecord::Base
        type = self.class.record_type(type)
      end

      return type.call(param, options) if type.is_a?(Proc)

      is_rails_parameters = defined?(ActionController::Parameters) && param.is_a?(ActionController::Parameters)
      if (param.is_a?(Array) && type != Array) || ((param.is_a?(Hash) || is_rails_parameters) && type != Hash)
        raise ArgumentError
      end
      return param if (is_rails_parameters && type == Hash rescue false)

      # Primitives
      return Integer(param) if type == Integer
      return Float(param) if type == Float
      return Float(param) if type == Numeric
      return String(param) if type == String

      # Date/Time
      if TIME_TYPES.include? type
        if tz = options[:timezone]
          tz = ActiveSupport::TimeZone[tz] if tz.is_a?(String)
          dt = options[:format].present? ? tz.strptime(param, options[:format]) : tz.parse(param)
          dt = dt.to_date if type == Date
          return dt
        else
          if options[:format].present?
            return type.strptime(param, options[:format])
          else
            return type.parse(param)
          end
        end
      end

      # Arrays/Hashes
      raise ArgumentError if (type == Array || type == Hash) && !param.respond_to?(:split)
      return Array(param.split(options[:delimiter] || ',')) if type == Array
      return Hash[param.split(options[:delimiter] || ',').map { |c| c.split(options[:separator] || ':') }] if type == Hash

      # Booleans
      if [TrueClass, FalseClass, :boolean, :bool].include?(type)
        return false if /^(false|f|no|n|0)$/i === param.to_s
        return true if /^(true|t|yes|y|1)$/i === param.to_s

        raise ArgumentError
      end

      # BigDecimals
      if type == BigDecimal
        param = param.delete('$,').strip.to_f if param.is_a?(String)
        return BigDecimal(param, (options[:precision] || DEFAULT_PRECISION))
      end
      nil
    end

    def normalize_opts(*args, **kwargs, &blk)
      # Stage 1 - Convert args to kwargs
      args, norm = convert_positional_args(args, kwargs)
      if blk.present?
        type = args.delete(:items) ? :all_items : :all_block
        set_hash_key(norm, type, blk)
      end
      set_hash_key(norm, :type, args.pop(0)) if args.present?

      # Stage 2
      norm = convert_flags(norm)

      # Stage 3
      norm = convert_prefixed_keys(norm)

      extra_kwargs = norm.keys - PREFIXES - NON_PREFIXED
      raise ArgumentError, "Unrecognized postitional arguments: #{args.inspect}" if args.present?
      raise ArgumentError, "Unrecognized keyword arguments: #{extra_kwargs.inspect}" if extra_kwargs.present?

      norm
    end

    def convert_positional_args(args, kwargs)
      dest_hash = { **kwargs }
      args = args.reject do |arg|
        next false unless arg.is_a?(Symbol)

        flag, pfx = split_key(arg)
        next false unless VALID_FLAGS.include?(flag) && (pfx.nil? || PREFIXES.include?(pfx))

        set_hash_key(dest_hash, :"#{pfx || 'all'}_#{flag}", true)
        true
      end
      [args, dest_hash]
    end

    def convert_flags(h)
      dest_hash = {}
      h.each do |k, v|
        if VALID_FLAGS.include?(k) && normalize_prefix(v)
          set_hash_key(dest_hash, :"#{normalize_prefix(v)}_#{k}", true)
        else
          dest_hash[k] = v
        end
      end
      dest_hash
    end

    def convert_prefixed_keys(h)
      dest_hash = {}

      h.each do |k, v|
        flag, pfx = split_key(k)
        if !CHECKS.include?(flag)
          dest_hash[k] = v
        elsif NON_PREFIXED.include?(flag)
          # TODO: Raise warning if pfx
          dest_hash[k] = v
        elsif normalize_prefix(flag)
          dest_hash[flag] = merge_hashes(dest_hash[normalize_prefix(flag)] || {}, v)
        elsif pfx.nil? || PREFIXES.include?(pfx)
          pfx ||= :all
          dest_hash[pfx] ||= {}
          set_hash_key(dest_hash[pfx], flag, v)
        else
          dest_hash[k] = v
        end
      end

      dest_hash
    end

    def normalize_prefix(prefix)
      prefix = PREFIX_ALIASES[prefix] if PREFIX_ALIASES.include?(prefix)
      return nil unless PREFIXES.include?(prefix)

      prefix
    end

    def split_key(key)
      skey = key.to_s
      ALL_PREFIXES.each do |pfx|
        spfx = pfx.to_s
        next unless skey.start_with?("#{spfx}_")

        return [skey[(spfx.length + 1)..-1].to_sym, PREFIX_ALIASES[pfx] || pfx]
      end
      [key, nil]
    end

    def merge_hashes(h1, h2)
      h2.each do |k, v|
        set_hash_key(h1, k, v)
      end
      h1
    end

    def set_hash_key(h, k, v)
      k = k.to_sym
      # TODO: warn if h[k].present?
      h[k] = v
    end

    def trim_arguments(blk, args)
      return args if blk.arity.negative?
      args[0..(blk.arity.abs - 1)]
    end

    class ErrorStore
      attr_reader :errors, :fields

      def initialize
        @errors = []
        @fields = {}
      end

      def push(error)
        if error.is_a?(ErrorStore)
          merge!(error)
        elsif error.is_a?(Array)
          error.each{|e| push(e) }
        else
          @errors << error
        end
      end

      def push_to(field, error)
        store_for(field).push(error)
      end

      def present?
        @errors.present? || @fields.values.any?(&:present?)
      end

      def serialize
        if @fields.values.any?(&:present?)
          h = { }
          h[:_SELF_] = @errors if @errors.present?
          @fields.each do |k, v|
            s = v.serialize
            next unless s.present?
            h[k] = s
          end
          h
        elsif @errors.present?
          @errors
        else
          nil
        end
      end

      def merge!(other_store)
        return self if other_store == self

        @errors |= other_store.errors
        other_store.fields.each do |k, v|
          store_for(k).merge!(v)
        end

        self
      end

      def store_for(field)
        if field.is_a?(Symbol) || field.is_a?(Numeric)
          field = [field]
        elsif field.is_a?(String)
          field = field.split('.')
        elsif field.is_a?(Array)
          field = [*field]
        end

        sfield = field.shift
        store = @fields[sfield.to_s] ||= ErrorStore.new
        return store if field.count == 0
        return store.store_for(field)
      end
    end
  end
end
