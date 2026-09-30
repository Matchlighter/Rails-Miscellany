json.merge!(slice.except(:items))

json.items slice[:items] do |item|
  block.call(item)
end
