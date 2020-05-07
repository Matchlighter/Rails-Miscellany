module AdvancedAR
  # An array that "processes" after so many items are added.
  #
  # Example Usage:
  #   batches = BatchProcessor.new(of: 1000) do |batch|
  #     # Process the batch somehow
  #   end
  #   enumerator_of_some_kind.each { |item| batches << item }
  #   batches.flush
  class BatchProcessor
    attr_reader :batch_size

    def initialize(of: 1000, &blk)
      @batch_size = of
      @block = blk
      @current_batch = []
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
      process_batch if @current_batch.present?
    end

    protected

    def process_batch
      @block.call(@current_batch)
      @current_batch = []
    end
  end
end
