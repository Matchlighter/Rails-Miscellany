
require 'spec_helper'
require 'action_controller'

describe Miscellany::SlicedResponse do
  with_model :ARModel do
    table do |t|
      t.string :title
      t.timestamps null: false
    end
  end

  subject_class = Class.new(ActionController::Base) do
    include Miscellany::SlicedResponse
  end

  complex_query_class = Class.new(Miscellany::ComplexQuery) do
    def build_query
      "SELECT * FROM #{ARModel.table_name}"
    end

    def build_count_query
      "SELECT COUNT(*) FROM #{ARModel.table_name}"
    end

    def valid_sorts
      ["title"]
    end
  end

  before do
    10.times do |i|
      ARModel.create!(title: i)
    end
  end

  let(:subject) { subject_class.new }

  let(:slice_params) { { } }
  let(:slice_config) { {
    default_size: 3,
    default_sort: "title",
    valid_sorts: ["title", "created_at"],
  } }

  def expect_items(slice, expected)
    expected = JSON.parse(expected.to_json).map{|i| i.without("created_at", "updated_at")}
    slice = JSON.parse(slice.to_json)
    expect(slice).to be_a Hash
    expect(slice["items"].map{|i| i.without("created_at", "updated_at")}).to eql expected
  end

  shared_examples "basic functionality" do
    it "returns the first page" do
      r = subject.sliced_json(source, slice_params, **slice_config)
      expect_items(r, ARModel.all.limit(3))
    end

    it "returns the second page" do
      r = subject.sliced_json(source, { **slice_params, page: 2 }, **slice_config)
      expect_items(r, ARModel.all.offset(3).limit(3))
    end

    it "allows changing page sizes" do
      r = subject.sliced_json(source, { **slice_params, page: 2, page_size: 4 }, **slice_config)
      expect_items(r, ARModel.all.offset(4).limit(4))
    end

    it "works with a slice" do
      r = subject.sliced_json(source, { **slice_params, slice: "2:4" }, **slice_config)
      expect_items(r, ARModel.all.offset(2).limit(2))
    end

    it "includes metadata" do
      r = subject.sliced_json(source, slice_params, **slice_config)
      expect(r[:total_count]).to eql 10
      expect(r[:page]).to eql 1
      expect(r[:page_size]).to eql 3
      expect(r[:page_count]).to eql 4
      expect(r[:slice_start]).to eql 0
      expect(r[:slice_end]).to eql 3
    end
  end

  shared_examples "sortable" do
    it "is sortable" do
      expect_items(subject.sliced_json(source, { **slice_params, sort: "title DESC" }, **slice_config), ARModel.all.order("title DESC").limit(3))
    end
  end

  describe "#sliced_json" do
    context "with an Array source" do
      let(:source) { ARModel.all.to_a }

      include_examples "basic functionality"
    end

    context "with an ActiveRecord::Relation source" do
      let(:source) { ARModel.all }

      include_examples "basic functionality"
      include_examples "sortable"
    end

    context "with a ComplexQuery source" do
      let(:source) { complex_query_class.new({}) }

      include_examples "basic functionality"
      include_examples "sortable"

      it "uses the ComplexQuery sort_parser if valid_sorts is not given" do
        r = subject.sliced_json(source, { **slice_params, sort: "created_at" }, {})
        expect(r[:sort]).to eql nil

        r = subject.sliced_json(source, { **slice_params, sort: "title" }, {})
        expect(r[:sort]).to eql "title ASC"
      end

      it "does not reference the ComplexQuery sort_parser if valid_sorts is given" do
        expect(source).not_to receive(:sort_parser)
        subject.sliced_json(source, { **slice_params, sort: "title" }, **slice_config)
      end
    end

    it "enforces allow_all" do
      expect do
        subject.sliced_json(ARModel.all, { page: "all" }, **slice_config)
      end.to raise_error("cannot request whole collection")

      expect(subject.sliced_json(ARModel.all, { page: "all" }, allow_all: true, **slice_config)).to be_a Hash
    end

    context "with Hash-based valid_sorts" do
      let(:source) { ARModel.all }

      before(:each) do
        slice_config[:valid_sorts] = [
          title: ->(dir) { "title #{dir}" }
        ]
      end

      include_examples "basic functionality"
      include_examples "sortable"
    end
  end

  describe "#bearcat_as_sliced_json" do
    # TODO
  end

  describe Miscellany::SlicedResponse::Slice do
    let(:sort_parser) { Miscellany::SortLang::Parser.new(slice_config[:valid_sorts], default: slice_config[:default_sort]) }
    let(:slice) do
      Miscellany::SlicedResponse::Slice.build(ARModel.all, slice_params, sort_parser: sort_parser, **slice_config)
    end

    describe "#sort_sql" do
      it "always includes the default sort" do
        slice_params[:sort] = "created_at"
        expect(slice.send(:sort_sql)).to include "created_at ASC NULLS FIRST"
      end

      it "excludes unknown sorts" do
        slice_params[:sort] = "updated_at"
        expect(slice.send(:sort_sql)).not_to include "updated_at"
      end
    end
  end
end
