module ApplicationHelper
  include Pagy::Frontend

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

  # Static, hand-picked destinations for the ⌘K command palette
  # (shared/_command_palette.html.erb) - navigation only, deliberately no
  # destructive/non-GET actions (sign out, delete) in here.
  def command_palette_items
    [
      { label: "Dashboard", url: dashboard_path },
      { label: "Job Market", url: jobs_path },
      { label: "Companies", url: companies_path },
      { label: "My CRM", url: crm_path },
      { label: "Templates", url: cover_letter_templates_path },
      { label: "Asset Library", url: resumes_path },
      { label: "Radar Settings", url: edit_user_preference_path },
      { label: "New Cover Letter Template", url: new_cover_letter_template_path }
    ]
  end
end
