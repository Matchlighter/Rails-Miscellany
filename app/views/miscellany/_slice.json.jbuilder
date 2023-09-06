json.merge!(slice)

json.items slice[:items] do |item|
  block.call(item)
end
