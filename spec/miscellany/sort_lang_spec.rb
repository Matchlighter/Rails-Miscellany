
require 'spec_helper'

describe Miscellany::SortLang do

  describe ".normalize_sort" do
    it "accepts Hash KV pairs" do
      expect(Miscellany::SortLang.normalize_sort(["key", { column: "created_at", order: "ASC" }])).to eql({
        column: "created_at", force_order: false, key: "created_at", order: "ASC"
      })
    end

    it "accepts strings" do
      expect(Miscellany::SortLang.normalize_sort("created_at")).to eql({
        column: "created_at", force_order: false, key: "created_at"
      })
      expect(Miscellany::SortLang.normalize_sort("created_at ASC")).to eql({
        column: "created_at", force_order: false, key: "created_at", order: "ASC"
      })
      expect(Miscellany::SortLang.normalize_sort("created_at ASC!")).to eql({
        column: "created_at", force_order: true, key: "created_at", order: "ASC"
      })
    end

    it "accepts Procs" do
      logic = ->(x) { "created_at #{x}" }
      expect(Miscellany::SortLang.normalize_sort(logic, key: "k")).to eql({
        column: logic, key: "k"
      })
    end
  end

  describe ".distinct_sorts" do
    it "only includes each sort key once" do
      distinct = Miscellany::SortLang.distinct_sorts([
        { column: "created_at", order: "ASC" },
        { column: "created_at", order: "DESC" },
      ])
      expect(Miscellany::SortLang.sqlize(distinct)).to eql "created_at ASC NULLS FIRST"
    end
  end

  describe ".sqlize" do
    describe "nulls: option" do
      it "accepts a nulls: option" do
        expect(Miscellany::SortLang.sqlize([
          { column: "created_at", order: "ASC", nulls: :last },
        ])).to eql "created_at ASC NULLS LAST"
      end

      it "nulls: :high works" do
        expect(Miscellany::SortLang.sqlize([
          { column: "created_at", order: "ASC", nulls: :high },
        ])).to eql "created_at ASC NULLS LAST"
        expect(Miscellany::SortLang.sqlize([
          { column: "created_at", order: "DESC", nulls: :high },
        ])).to eql "created_at DESC NULLS FIRST"
      end

      it "nulls: :low works" do
        expect(Miscellany::SortLang.sqlize([
          { column: "created_at", order: "ASC", nulls: :low },
        ])).to eql "created_at ASC NULLS FIRST"
        expect(Miscellany::SortLang.sqlize([
          { column: "created_at", order: "DESC", nulls: :low },
        ])).to eql "created_at DESC NULLS LAST"
      end
    end
  end

  describe Miscellany::SortLang::Parser do
    let(:valid_sorts) {[
      "title", "created_at"
    ]}
    let(:default_sort) { "title" }

    let(:subject) { Miscellany::SortLang::Parser.new(valid_sorts, default: default_sort) }

    context "with multiple default sorts" do
      let(:default_sort) { ["title", "created_at"] }

      it "includes each" do
        expect(subject.parse(nil)).to eql [
          {:column=>"title", :force_order=>false, :key=>"title"},
          {:column=>"created_at", :force_order=>false, :key=>"created_at"},
        ]
      end
    end

    describe "#parse" do
      it "excludes uknown sorts" do
        expect(subject.parse("updated_at")).to eql [
          {:column=>"title", :force_order=>false, :key=>"title"},
        ]
      end

      it "considers force_order" do
        subject = Miscellany::SortLang::Parser.new([ "title ASC!" ])
        expect(subject.parse("title DESC")).to eql [
          {:column=>"title", :force_order=>true, :key=>"title", :order=>"ASC"},
        ]
      end

      it "returns the default sort if no sort is given" do
        expect(subject.parse("")).to eql [
          {:column=>"title", :force_order=>false, :key=>"title"},
        ]
        expect(subject.parse("", default: true)).to eql [
          {:column=>"title", :force_order=>false, :key=>"title"},
        ]
      end

      it "appends the default sort" do
        expect(subject.parse("created_at", default: :append)).to eql [
          {:column=>"created_at", :force_order=>false, :key=>"created_at"},
          {:column=>"title", :force_order=>false, :key=>"title"},
        ]
      end

      it "excludes the default sort" do
        expect(subject.parse("created_at", default: false)).to eql [
          {:column=>"created_at", :force_order=>false, :key=>"created_at"},
        ]
      end
    end
  end
end
