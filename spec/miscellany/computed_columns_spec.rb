
require 'spec_helper'

describe Miscellany::ComputedColumns do
  with_model :Post do
    table do |t|
      t.string :title
      t.timestamps null: false
    end

    model do
      has_many :comments

      define_computed :favorite_comments_count, ->() {
        select "COMPUTED.count AS favorite_comments_count"

        query do
          Comment.select(<<~SQL)
              post_id AS id,
              count(*) AS count
            SQL
          .group(:post_id)
            .where(favorite: true)
        end
      }
    end
  end

  with_model :Comment do
    table do |t|
      t.belongs_to :post
      t.string :title
      t.boolean :favorite
      t.timestamps null: false
    end

    model do
      belongs_to :post
    end
  end

  let!(:posts) { 3.times.map{|i| Post.create!(title: "Post #{i}") } }

  before :each do
    posts.each do |p|
      5.times{|i| p.comments.create!(title: "#{p.title} Comment #{i}") }
      p.comments.last.update!(favorite: true)
    end
  end

  it 'generally works' do
    # Debug aid only; removed from ActiveRecord in Rails 7.1.
    ActiveRecord::Base.verbose_query_logs = true if ActiveRecord::Base.respond_to?(:verbose_query_logs=)
    posts = Post.with_computed(:favorite_comments_count)
    expect(posts.except(:select).count).to eq 3
    expect(posts[0].favorite_comments_count).to eq 1

    Comment.update_all(favorite: true)
    posts = Post.with_computed(:favorite_comments_count)
    expect(posts.except(:select).count).to eq 3
    expect(posts[0].favorite_comments_count).to eq 5
  end
end
