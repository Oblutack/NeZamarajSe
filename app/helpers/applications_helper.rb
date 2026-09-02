module ApplicationsHelper
  def application_status_label(status)
    t("shared.application_statuses.#{status}")
  end

  def application_event_description(event)
    case event.event_type
    when "status_change"
      from = event.from_status ? application_status_label(event.from_status) : "—"
      t("shared.application_events.status_change", from: from, to: application_status_label(event.to_status))
    when "note"
      event.body
    when "follow_up_sent"
      t("shared.application_events.follow_up_sent")
    when "reply_detected"
      t("shared.application_events.reply_detected")
    else
      event.event_type.titleize
    end
  end
end
