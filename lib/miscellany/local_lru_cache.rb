module Miscellany
  class LocalLruCache
    def initialize(max_size)
      @max_size = max_size
      @data = {}
    end

    def max_size=(size)
      raise ArgumentError.new(:max_size) if size < 1
      @max_size = size
      # Evict least-recently-used entries (oldest first) until we fit.
      while @data.size > @max_size
        @data.delete(@data.first[0])
      end
    end

    def fetch(key)
      if @data.key?(key)
        self[key]
      else
        self[key] = yield
      end
    end

    def [](key)
      found = true
      value = @data.delete(key){ found = false }
      if found
        @data[key] = value
      else
        nil
      end
    end

    def []=(key,val)
      @data.delete(key)
      @data[key] = val
      if @data.length > @max_size
        @data.delete(@data.first[0])
      end
      val
    end

    def each
      to_a.each do |pair|
        yield pair
      end
    end

    def to_a
      @data.to_a.reverse
    end

    def delete(k)
      @data.delete(k)
    end

    def clear
      @data.clear
    end

    def count
      @data.count
    end
  end
end
