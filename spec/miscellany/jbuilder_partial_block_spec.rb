require 'spec_helper'

# JbuilderTemplateExt is meant to be prepended onto JbuilderTemplate. Rather than
# stand up a full jbuilder render, we prepend it onto a stub that records what
# partial! receives, which is exactly the behavior the extension changes.
RSpec.describe Miscellany::Extensions::JBuilder::JbuilderTemplateExt do
  let(:recorder_class) do
    Class.new do
      attr_reader :last_args, :last_kwargs

      def partial!(*args, **kwargs)
        @last_args = args
        @last_kwargs = kwargs
      end
    end
  end

  let(:instance) do
    klass = recorder_class
    klass.prepend(described_class)
    klass.new
  end

  it 'injects a given block as the :block keyword' do
    blk = -> { :rendered }
    instance.partial!('shared/thing', foo: 1, &blk)

    expect(instance.last_kwargs[:block]).to eq blk
    expect(instance.last_kwargs[:foo]).to eq 1
  end

  it 'does not add a :block keyword when no block is given' do
    instance.partial!('shared/thing', foo: 1)
    expect(instance.last_kwargs).not_to have_key(:block)
  end

  it 'passes positional arguments through unchanged' do
    instance.partial!('shared/thing')
    expect(instance.last_args).to eq ['shared/thing']
  end
end
