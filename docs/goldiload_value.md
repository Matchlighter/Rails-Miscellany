# Goldiloaded Ruby-Computed Values

Allows getter methods that load an association. When the getter is called on one model in a loaded relation, the computation is expected to load data for all models.

## Setup
Create an Initializer with
```ruby
Miscellany::GoldiloadValue.install
```

Install `goldiloader`.

## Examples

### Example 1
```ruby
# Based off of a case in learning-teams-lti
def bookmarked_by(user)
    # [:bookmarked_by, user] is basically the key - if this key has already been loaded/cached, no compute will be performed
    goldiload_value([:bookmarked_by, user]) do |models|
        bookmarks = ChannelMember.joins(:user).where(channel: models, user: { canvas_id: user.canvas_id }, type: 'bookmarker').index_by(&:channel_id)
        models.map{|m| [m.id, bookmarks[m.id].present?] }.to_h
    end
end
