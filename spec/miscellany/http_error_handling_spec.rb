require 'spec_helper'
require 'action_controller'

RSpec.describe Miscellany::HttpErrorHandling do
  # Captures what the concern hands to `render` instead of driving a real response.
  controller_class = Class.new(ActionController::Base) do
    include Miscellany::HttpErrorHandling

    attr_reader :rendered

    def render(**kwargs)
      @rendered = kwargs
    end
  end

  let(:controller) { controller_class.new }

  def rendered_for(err, **kwargs)
    controller.render_http_error(err, **kwargs)
    controller.rendered
  end

  describe '#render_http_error' do
    it 'renders an HttpError with its own status, message, and extra' do
      err = Miscellany::HttpErrorHandling::HttpError.new('nope', status: 422, code: 'E_NOPE')
      expect(rendered_for(err)).to eq(
        json: { status: 422, message: 'nope', code: 'E_NOPE' },
        status: 422,
      )
    end

    it 'defaults to 400 when no status is available' do
      expect(rendered_for(Miscellany::HttpErrorHandling::HttpError.new('nope'))[:status]).to eq 400
    end

    # Reached by `rescue_with_http_error`, which passes ordinary exceptions.
    it 'renders a plain StandardError that carries no extra' do
      expect(rendered_for(StandardError.new('boom'), status: 422)).to eq(
        json: { status: 422, message: 'boom' },
        status: 422,
      )
    end

    # The idiom ParamValidator's docs recommend: field errors must reach the client
    # as their own key, not folded into the message string.
    it 'carries structured field errors through as extra' do
      errors = { 'search_term' => ['must be at least 3 characters'] }
      err = Miscellany::HttpErrorHandling::HttpError.new(
        'invalid parameters', status: 422, parameter_errors: errors
      )
      expect(rendered_for(err)).to eq(
        json: { status: 422, message: 'invalid parameters', parameter_errors: errors },
        status: 422,
      )
    end

    it 'prefers an explicit message over the exception message' do
      expect(rendered_for(StandardError.new('boom'), message: 'friendlier')[:json][:message])
        .to eq 'friendlier'
    end
  end

  describe '.http_error' do
    it 'resolves a Proc message against the exception' do
      handler = controller_class.http_error(422, ->(err) { "custom: #{err.message}" })
      controller.instance_exec(StandardError.new('boom'), &handler)
      expect(controller.rendered).to eq(
        json: { status: 422, message: 'custom: boom' },
        status: 422,
      )
    end

    it 'accepts the message as a block' do
      handler = controller_class.http_error(422) { |err| "blocky: #{err.message}" }
      controller.instance_exec(StandardError.new('boom'), &handler)
      expect(controller.rendered[:json][:message]).to eq 'blocky: boom'
    end

    it 'lets an HttpError keep its own status rather than the handler default' do
      handler = controller_class.http_error(500)
      controller.instance_exec(Miscellany::HttpErrorHandling::HttpError.new('nope', status: 404), &handler)
      expect(controller.rendered[:status]).to eq 404
    end
  end
end

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
