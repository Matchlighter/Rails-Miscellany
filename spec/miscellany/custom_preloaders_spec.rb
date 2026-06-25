require 'spec_helper'

RSpec.describe Miscellany::CustomPreloaders do
  describe Miscellany::CustomPreloaders::AssociationBuilderExtension do
    it 'registers :preloader as a valid association option' do
      expect(described_class.valid_options).to include(:preloader)
    end
  end

  describe 'option registration on a real association' do
    with_model :Author do
      table { |t| t.string :name }
      model do
        has_many :books, preloader: 'SomePreloaderClass'
      end
    end

    with_model :Book do
      table { |t| t.integer :author_id }
    end

    it 'accepts the :preloader option without raising' do
      # If AssociationBuilderExtension were not installed, ActiveRecord would
      # reject the unknown :preloader option when the association is touched.
      expect { Author.reflect_on_association(:books).options }.not_to raise_error
      expect(Author.reflect_on_association(:books).options[:preloader])
        .to eq 'SomePreloaderClass'
    end
  end

  describe Miscellany::CustomPreloaders::PreloaderExtension do
    # A minimal stand-in for ActiveRecord's Preloader whose default
    # preloader_for returns :fallback, so we can observe override behavior.
    let(:preloader) do
      base = Class.new do
        def preloader_for(_reflection, _owners)
          :fallback
        end
      end
      base.prepend(Miscellany::CustomPreloaders::PreloaderExtension)
      base.new
    end

    def reflection_with(options)
      double('reflection', options: options)
    end

    it 'falls back to the default when no custom preloader is configured' do
      expect(preloader.preloader_for(reflection_with({}), [])).to eq :fallback
    end

    it 'returns a custom preloader class as-is' do
      custom = Class.new
      expect(preloader.preloader_for(reflection_with(preloader: custom), [])).to eq custom
    end

    it 'constantizes a string preloader name' do
      stub_const('MyCustomPreloader', Class.new)
      expect(preloader.preloader_for(reflection_with(preloader: 'MyCustomPreloader'), []))
        .to eq MyCustomPreloader
    end
  end
end
