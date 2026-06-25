require 'spec_helper'

RSpec.describe Miscellany::HttpErrorHandling::HttpError do
  it 'defaults to a blank message, no status, and no extra' do
    err = described_class.new
    expect(err.message).to eq ''
    expect(err.status).to be_nil
    expect(err.extra).to eq({})
  end

  it 'treats a numeric positional argument as the status' do
    err = described_class.new(404)
    expect(err.status).to eq 404
    expect(err.message).to eq ''
  end

  it 'treats a non-numeric positional argument as the message' do
    err = described_class.new('boom')
    expect(err.message).to eq 'boom'
    expect(err.status).to be_nil
  end

  it 'accepts status and message as keywords' do
    err = described_class.new(status: 422, message: 'bad input')
    expect(err.status).to eq 422
    expect(err.message).to eq 'bad input'
  end

  it 'combines a positional status with a keyword message' do
    err = described_class.new(403, message: 'nope')
    expect(err.status).to eq 403
    expect(err.message).to eq 'nope'
  end

  it 'captures unknown keywords as extra' do
    err = described_class.new('boom', code: 'E_BOOM', detail: 'context')
    expect(err.extra).to eq(code: 'E_BOOM', detail: 'context')
  end

  it 'raises when status is given both positionally and as a keyword' do
    expect { described_class.new(400, status: 500) }
      .to raise_error(ArgumentError, /status supplied multiple times/)
  end

  it 'raises when message is given both positionally and as a keyword' do
    expect { described_class.new('boom', message: 'also boom') }
      .to raise_error(ArgumentError, /message supplied multiple times/)
  end

  it 'is a StandardError so it can be rescued' do
    expect(described_class.new).to be_a(StandardError)
  end
end
