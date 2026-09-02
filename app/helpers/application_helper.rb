module ApplicationHelper
  # Companies and Jobs both store URLs scraped from external sites -
  # refuse anything that isn't plain http(s) before it ever reaches a
  # link_to href, so a scraped javascript: URI can't execute on click.
  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url)
    uri.to_s if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    nil
  end
end
