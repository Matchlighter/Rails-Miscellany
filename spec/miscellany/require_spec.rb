require 'spec_helper'
require 'open3'

# These run in a fresh process on purpose: by the time the rest of the suite
# loads, ActiveRecord is already in memory, which is exactly what masks a missing
# require in lib/miscellany.rb.
RSpec.describe 'requiring miscellany' do
  LIB_PATH = File.expand_path('../../lib', __dir__)

  # stdout and stderr are kept apart deliberately: Ruby writes unrelated
  # deprecation warnings to stderr, which would otherwise corrupt the result.
  def ruby(source)
    out, err, status = Open3.capture3(
      Gem.ruby, '-rbundler/setup', "-I#{LIB_PATH}", '-e', source
    )
    raise "subprocess exited #{status.exitstatus}:\n#{err}" unless status.success?

    out
  end

  it 'succeeds without ActiveRecord having been loaded first' do
    expect(ruby('require "miscellany"; print "OK"')).to eq 'OK'
  end

  it 'installs the ActiveRecord extensions' do
    expect(ruby('require "miscellany"; print ActiveRecord::Base.respond_to?(:prefetch)')).to eq 'true'
    expect(ruby('require "miscellany"; print ActiveRecord::Base.respond_to?(:with_computed)')).to eq 'true'
  end

  it 'exposes the plain-Ruby helpers' do
    expect(ruby('require "miscellany"; print Miscellany::LocalLruCache.new(2)[:missing].inspect')).to eq 'nil'
    expect(ruby('require "miscellany"; print Miscellany::ParamValidator.check({}) { }.serialize.inspect')).to eq 'nil'
  end
end
