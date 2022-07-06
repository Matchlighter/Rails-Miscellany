module Miscellany
  # An array that "processes" after so many items are added.
  #
  # Example Usage:
  #   batches = BatchProcessor.new(of: 1000) do |batch|
  #     # Process the batch somehow
  #   end
  #   enumerator_of_some_kind.each { |item| batches << item }
  #   batches.flush
  class BatchProcessor
    attr_reader :batch_size, :ensure_once

    def initialize(of: 1000, ensure_once: false, &blk)
      @batch_size = of
      @block = blk
      @ensure_once = ensure_once
      @current_batch = []

      @flush_count = 0
    end

    def <<(item)
      @current_batch << item
      process_batch if @current_batch.count >= batch_size
    end

    def add_all(items)
      items.each do |i|
        self << i
      end
    end

    def flush
      process_batch if @current_batch.present? || (@flush_count.zero? && ensure_once)
    end

    protected

    def process_batch
      @block.call(@current_batch)
      @current_batch = []
      @flush_count += 1
    end
  end
end
