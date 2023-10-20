
require 'spec_helper'

describe Miscellany::ArbitraryPrefetch do
  shared_examples "general specs" do
    it 'generally works' do
      posts = Post.prefetch(favorite_comment: Comment.where(favorite: true))
      expect(posts.count).to eq 10
      expect(posts[0].favorite_comment).to be
    end

    it 'works with Goldiloader active' do
      Goldiloader.enabled do
        posts = Post.prefetch(favorite_comment: Comment.where(favorite: true))
        expect(posts.count).to eq 10
        expect(posts[0].favorite_comment).to be
      end
    end

    it 'works with Goldiloader disabled' do
      Goldiloader.disabled do
        posts = Post.prefetch(favorite_comment: Comment.where(favorite: true))
        expect(posts.count).to eq 10
        expect(posts[0].favorite_comment).to be
      end
    end

    context 'prefetch is singluar' do
      it 'returns a single object' do
        posts = Post.prefetch(favorite_comment: Comment.where(favorite: true))
        expect(posts[0].favorite_comment).to be_a Comment
      end

      it 'with multiple items returns a single object' do
        posts = Post.prefetch(favorite_comment: Comment.where(favorite: nil))
        expect(posts[0].favorite_comment).to be_a Comment
      end
    end

    context 'prefetch is plural' do
      it 'returns an Array' do
        posts = Post.prefetch(non_favorite_comments: Comment.where(favorite: nil))
        expect(posts[0].non_favorite_comments).to respond_to :[]
        expect(posts[0].non_favorite_comments.length).to eq 4
      end

      it 'with 1 item returns an Array' do
        posts = Post.prefetch(non_favorite_comments: Comment.where(favorite: true))
        expect(posts[0].non_favorite_comments).to respond_to :[]
        expect(posts[0].non_favorite_comments.length).to eq 1
      end
    end
  end

  context "normal association" do
    with_model :Post do
      table do |t|
        t.string :title
        t.timestamps null: false
      end

      model do
        has_many :comments
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

    let!(:posts) { 10.times.map{|i| Post.create!(title: "Post #{i}") } }

    before :each do
      posts.each do |p|
        5.times{|i| p.comments.create!(title: "#{p.title} Comment #{i}") }
        p.comments.last.update!(favorite: true)
      end
    end

    include_examples "general specs"
  end

  context "through: association" do
    with_model :Post do
      table do |t|
        t.string :title
        t.timestamps null: false
      end

      model do
        has_many :interims
        has_many :comments, through: :interims
      end
    end

    with_model :Interim do
      table do |t|
        t.belongs_to :post
        t.belongs_to :comment
        t.timestamps null: false
      end

      model do
        belongs_to :post
        belongs_to :comment
      end
    end

    with_model :Comment do
      table do |t|
        t.string :title
        t.boolean :favorite
        t.timestamps null: false
      end

      model do
      end
    end

    let!(:posts) { 10.times.map{|i| Post.create!(title: "Post #{i}") } }

    before :each do
      posts.each do |p|
        5.times{|i| p.comments.create!(title: "#{p.title} Comment #{i}") }
        p.comments.last.update!(favorite: true)
      end
    end

    include_examples "general specs"
  end
end
