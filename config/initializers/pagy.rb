# config/initializers/pagy.rb
require "pagy/extras/overflow"

# Applies to every pagy() call unless overridden per-call (e.g. Job Market's
# card grid uses a larger page size than a table-heavy list would want).
Pagy::DEFAULT[:limit] = 24

# A stale bookmarked/shared link to a page number that no longer exists
# (filters changed, items got deleted) redirects to the last valid page
# instead of raising Pagy::OverflowError.
Pagy::DEFAULT[:overflow] = :last_page
