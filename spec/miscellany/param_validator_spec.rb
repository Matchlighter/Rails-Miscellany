
require 'spec_helper'

describe Miscellany::ParamValidator do
  let!(:value) do
    {
      int_array: [1,2,3],
      string_array: %w[A B C],
      some_number: 2,
      some_string: "Robert",
      specified: nil,
      array: [
        {a: 2},
        {a: 3},
      ],
      hash: {
        nested_hash: {
          value: 1,
        }
      },
    }
  end

  # TODO transform:

  def expect_valid(&blk)
    result = Miscellany::ParamValidator.check(value, &blk)
    expect(result.serialize).to be_nil
  end

  def expect_invalid(&blk)
    result = Miscellany::ParamValidator.check(value, &blk)
    expect(result.serialize).to be_present
  end

  def expect_coercion(raw, type, expectation)
    result = Miscellany::ParamValidator.assert({ value: raw }, handle: ->(v){ raise 'Invalid' }) do
      p :value, type: type
    end
    expect(result[:value]).to eq expectation
  end

  describe 'default:' do
    it 'sets a default value' do
      result = Miscellany::ParamValidator.assert({ }, handle: ->(v){ raise 'Invalid' }) do
        p :value, default: 'HIA'
      end
      expect(result[:value]).to eq 'HIA'
    end

    it 'works deep' do
      result = Miscellany::ParamValidator.assert({ value: {} }, handle: ->(v){ raise 'Invalid' }) do
        p :value do |x|
          p :value, default: 'Hia'
        end
      end
      expect(result).to eq ({ value: { value: 'Hia' } })
    end
  end

  describe 'specified' do
    it 'passes a given value' do
      expect_valid do
        p :some_string, :specified
      end
    end

    it 'passes a given nil' do
      expect_valid do
        p :specified, :specified
      end
    end

    it 'fails an unspecified key' do
      expect_invalid do
        p :not_specified, :specified
      end
    end
  end

  describe 'present' do
    it 'passes a given value' do
      expect_valid do
        p :some_string, :present
      end
    end

    it 'fails a given nil' do
      expect_invalid do
        p :specified, :present
      end
    end

    it 'fails an unspecified key' do
      expect_invalid do
        p :not_specified, :present
      end
    end
  end

  describe 'type:' do
    it 'passes based on type' do
      expect_valid do
        p :some_number, type: Numeric
        p :some_string, type: String
      end
    end

    it 'fails based on type' do
      expect_invalid do
        p :some_number, type: String
        p :some_string, type: Numeric
      end
    end

    describe 'an unsupported type' do
      # A type with no coercion rule is a mistake in the validator definition,
      # not bad user input, so it must fail loudly instead of silently nulling.
      it 'raises, naming the type and the key' do
        expect do
          Miscellany::ParamValidator.check({ value: 'x' }) { p :value, type: Symbol }
        end.to raise_error(Miscellany::ParamValidator::UnsupportedTypeError, /Symbol.*:value/)
      end

      it 'leaves the value untouched' do
        params = { value: 'x' }
        begin
          Miscellany::ParamValidator.check(params) { p :value, type: Symbol }
        rescue Miscellany::ParamValidator::UnsupportedTypeError
          # asserted separately above
        end
        expect(params[:value]).to eq 'x'
      end

      it 'accepts a value that is already an instance of that type' do
        expect_coercion(:already_a_symbol, Symbol, :already_a_symbol)
      end
    end

    describe 'given positionally' do
      def assert_positional(raw, expectation, &blk)
        result = Miscellany::ParamValidator.assert({ value: raw }, handle: ->(_v) { raise 'Invalid' }, &blk)
        expect(result[:value]).to eq expectation
      end

      it 'coerces just as the keyword form does' do
        assert_positional('5', 5) { p :value, Integer }
      end

      it 'accepts a list of types' do
        assert_positional('5', 5) { p :value, [Integer, String] }
      end

      it 'combines with flags in any order' do
        assert_positional('5', 5) { p :value, :present, Integer }
        assert_positional('5', 5) { p :value, Integer, :present }
      end

      it 'still rejects genuinely unrecognized arguments' do
        expect do
          Miscellany::ParamValidator.check({ value: '5' }) { p :value, Integer, String }
        end.to raise_error(ArgumentError, /positional/)
      end
    end

    describe 'BigDecimal' do
      it 'coerces a decimal string' do
        expect_coercion('12.34', BigDecimal, BigDecimal('12.34'))
      end

      it 'strips currency formatting' do
        expect_coercion('$1,234.56', BigDecimal, BigDecimal('1234.56'))
      end

      # Routing through Float would silently truncate here, which defeats the
      # point of asking for a BigDecimal.
      it 'keeps digits beyond what a Float can hold' do
        expect_coercion('1.234567890123456789', BigDecimal, BigDecimal('1.234567890123456789'))
      end

      it 'coerces a numeric value' do
        expect_coercion(5, BigDecimal, BigDecimal(5))
      end

      it 'reports a validation error for a non-numeric string' do
        expect_invalid do
          p :some_string, type: BigDecimal
        end
      end
    end

    describe ':bool' do
      it 'transforms booleans' do
        expect_coercion('t', :bool, true)
        expect_coercion('T', :bool, true)
        expect_coercion('true', :bool, true)
        expect_coercion('True', :bool, true)
        expect_coercion('TRUE', :bool, true)
        expect_coercion('YES', :bool, true)
        expect_coercion('yes', :bool, true)
        expect_coercion('Y', :bool, true)
        expect_coercion('y', :bool, true)
        expect_coercion('1', :bool, true)
        expect_coercion(1, :bool, true)

        expect_coercion('f', :bool, false)
        expect_coercion('F', :bool, false)
        expect_coercion('false', :bool, false)
        expect_coercion('False', :bool, false)
        expect_coercion('FALSE', :bool, false)
        expect_coercion('NO', :bool, false)
        expect_coercion('no', :bool, false)
        expect_coercion('N', :bool, false)
        expect_coercion('n', :bool, false)
        expect_coercion('0', :bool, false)
        expect_coercion(0, :bool, false)
      end
    end
  end

  describe 'in:' do
    it 'works' do
      expect_valid do
        p :some_number, in: [1, 2]
      end

      expect_invalid do
        p :some_number, in: [1, 3]
      end
    end

    it 'works with modifiers' do
      expect_valid do
        p [:some_number, :some_string], one_in: [2]
        p [:some_number, :some_string], one_in: ['Robert']
        p [:some_number, :some_string], none_in: ['Steve', 3]
      end
    end
  end

  describe 'pattern:' do
    it 'works' do
      expect_valid do
        p :some_string, pattern: /^Rob/
        p :some_string, pattern: /^Robert$/
      end
      expect_invalid do
        p :some_string, pattern: /^Steve$/
      end
    end

    # A matching pattern must not short-circuit the rest of the parameter.
    it 'still applies the other checks when the pattern matches' do
      expect_invalid do
        p :some_string, pattern: /^Rob/, in: %w[Steve]
      end
    end

    it 'reports the failing key when an earlier key matched' do
      result = Miscellany::ParamValidator.check({ matches: 'Robert', fails: 'Steve' }) do
        p %i[matches fails], pattern: /^Rob/
      end
      expect(result.serialize).to eq('fails' => ['must match pattern: /^Rob/'])
    end

    it 'does not discard errors collected for earlier keys' do
      result = Miscellany::ParamValidator.check({ fails: 'Steve', matches: 'Robert' }) do
        p %i[fails matches], pattern: /^Rob/
      end
      expect(result.serialize).to eq('fails' => ['must match pattern: /^Rob/'])
    end
  end

  describe 'items:' do
    it 'works when given a Lambda' do
      expect_valid do
        p :array, items: ->(*args) {
          p :a, in: [2, 3]
          nil
        }
      end
      expect_invalid do
        p :array, items: ->(*args) {
          p :a, in: [5]
        }
      end
      expect_invalid do
        p :array, items: ->(*args) {
          'bob'
        }
      end
    end
    it 'works when given a Hash' do
      # TODO
    end
  end

  it 'supports a custom validator block' do
    expect_valid do
      p :some_string do |v|
        nil
      end
    end

    expect_invalid do
      p :some_string do |v|
        'Bad Length'
      end
    end
  end

  describe 'modifiers' do
    let!(:value) do
      {
        a: 1,
        b: 1,
        c: 1,
        x: nil,
        y: nil,
        z: nil,
      }
    end

    def assert_modifier(modifier, keys, exp)
      blk = ->(*args) {
        p keys, :"#{modifier}_present"
      }
      exp ? expect_valid(&blk) : expect_invalid(&blk)
    end

    it 'the all modifier works as expected' do
      assert_modifier(:all, %i[a b c], true)
      assert_modifier(:all, %i[a b z], false)
      assert_modifier(:all, %i[a y z], false)
      assert_modifier(:all, %i[x y z], false)
    end

    it 'the onem modifier works as expected' do
      assert_modifier(:onem, %i[a b c], false)
      assert_modifier(:onem, %i[a b z], false)
      assert_modifier(:onem, %i[a y z], true)
      assert_modifier(:onem, %i[x y z], true)
    end

    it 'the onep modifier works as expected' do
      assert_modifier(:onep, %i[a b c], true)
      assert_modifier(:onep, %i[a b z], true)
      assert_modifier(:onep, %i[a y z], true)
      assert_modifier(:onep, %i[x y z], false)
    end

    it 'the one modifier works as expected' do
      assert_modifier(:one, %i[a b c], false)
      assert_modifier(:one, %i[a b z], false)
      assert_modifier(:one, %i[a y z], true)
      assert_modifier(:one, %i[x y z], false)
    end

    it 'the none modifier works as expected' do
      assert_modifier(:none, %i[a b c], false)
      assert_modifier(:none, %i[a b z], false)
      assert_modifier(:none, %i[a y z], false)
      assert_modifier(:none, %i[x y z], true)
    end

    it 'aliases work' do
      assert_modifier(:any, %i[a b c], true)
      assert_modifier(:any, %i[a b z], true)
      assert_modifier(:any, %i[a y z], true)
      assert_modifier(:any, %i[x y z], false)
    end
  end

  describe 'nesting' do
    it 'works' do
      expect_valid do
        p :hash, :present do
          p :nested_hash do
            p :value, in: [1]
          end
        end
      end
      expect_invalid do
        p :hash, :present do
          p :nested_hash do
            p :value, not_in: [1]
          end
        end
      end
    end
  end
end
