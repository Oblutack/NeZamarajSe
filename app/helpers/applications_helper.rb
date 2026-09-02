module ApplicationsHelper
  def application_event_description(event)
    case event.event_type
    when "status_change"
      from = event.from_status&.titleize || "—"
      "Moved from #{from} to #{event.to_status.titleize}"
    when "note"
      event.body
    when "follow_up_sent"
      "Follow-up email sent"
    when "reply_detected"
      "Reply detected - moved to Interviewing"
    else
      event.event_type.titleize
    end
  end
end
