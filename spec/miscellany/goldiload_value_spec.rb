
require 'spec_helper'
require 'goldiloader'

describe Miscellany::GoldiloadValue do
  with_model :Post do
    table do |t|
      t.string :title
      t.timestamps null: false
    end

    model do
      attr_accessor :read_count

      after_initialize { self.read_count = 0 }

      def gvalue
        goldiload_value([:key]) do |models|
          self.read_count += 1
          models.map{|m| [m.id, 123] }.to_h
        end
      end
    end
  end

  let!(:posts) { 3.times.map{|i| Post.create!(title: "Post #{i}") } }

  it 'generally works' do
    posts = Post.limit(2).to_a

    expect(posts[0].goldi_values).to eql nil
    expect(posts[1].goldi_values).to eql nil

    expect(posts[0].gvalue).to eql 123

    expect(posts[0].goldi_values).to eql ({[:key]=>123})
    expect(posts[1].goldi_values).to eql ({[:key]=>123})
  end

  it 'only calculates once per batch' do
    posts = Post.limit(2).to_a

    expect(posts[0].read_count).to eql 0
    expect(posts[1].read_count).to eql 0

    expect(posts[0].gvalue).to eql 123
    expect(posts[0].gvalue).to eql 123
    expect(posts[1].gvalue).to eql 123

    expect(posts[0].read_count).to eql 1
    expect(posts[1].read_count).to eql 0
  end
end
