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
      { label: t("navbar.dashboard"), url: dashboard_path },
      { label: t("navbar.job_market"), url: jobs_path },
      { label: t("navbar.companies"), url: companies_path },
      { label: t("navbar.my_crm"), url: crm_path },
      { label: t("navbar.templates"), url: cover_letter_templates_path },
      { label: t("navbar.asset_library"), url: resumes_path },
      { label: t("navbar.radar_settings"), url: edit_user_preference_path },
      { label: t("shared.command_palette.new_template"), url: new_cover_letter_template_path }
    ]
  end
end
