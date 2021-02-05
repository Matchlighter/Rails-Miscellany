module Miscellany
  module HttpErrorHandling
    extend ActiveSupport::Concern

    class UnauthorizedError < StandardError; end

    class HttpError < StandardError
      attr_accessor :status, :extra
      def initialize(arg = nil, status: nil, message: '', **extra)
        if arg.is_a?(Numeric)
          raise ArgumentError, ':status supplied multiple times' if status.present?

          status = arg
        elsif arg.present?
          raise ArgumentError, ':message supplied multiple times' if message.present?

          message = arg
        end
        super(message)
        @status = status
        @extra = extra
      end
    end

    module ClassMethods
      def http_error(status = 400, message = nil, &blk)
        message = blk if blk.present?
        lambda { |err|
          # This is necessary to ensure that HttpErrors are never handled as StandardErrors
          if err.is_a?(HttpError)
            render_http_error(err)
          else
            render_http_error(err, status: status, message: message)
          end
        }
      end

      def rescue_with_http_error(*errors, status: nil, message: nil, **kwargs)
        rescue_from(*errors, with: http_error(status, message), **kwargs)
      end
    end

    included do
      rescue_from HttpError do |err|
        render_http_error(err)
      end

      rescue_with_http_error UnauthorizedError, status: 401
    end

    def render_http_error(err, status: nil, message: nil)
      status = err.status if err.is_a?(HttpError) && status.nil?
      status ||= 400
      message ||= err.message
      message.message.call(err) if message.is_a?(Proc)
      response_json = { status: status }
      response_json[:message] = message if message.present?
      response_json.merge!(err.extra)
      render json: response_json, status: status
    end
  end
end
