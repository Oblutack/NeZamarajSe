# app/controllers/company_email_suggestions_controller.rb
class CompanyEmailSuggestionsController < ApplicationController
  before_action :authenticate_user!

  # Used from three places (the job card, the job detail page, and the
  # company page) via one shared partial (shared/_email_suggestion_form),
  # so this always redirects back to wherever the form was submitted from
  # rather than assuming a single destination.
  def create
    company = Company.find(params[:company_id])

    # One suggestion per user per company - find_or_initialize_by means a
    # user correcting their own earlier guess updates it rather than
    # piling up a second row (the DB also enforces this via a unique index).
    suggestion = company.email_suggestions.find_or_initialize_by(user: current_user)
    suggestion.email = params[:email].to_s.strip

    if suggestion.save
      redirect_back fallback_location: company_path(company), notice: t("flash.company_email_suggestions.saved")
    else
      redirect_back fallback_location: company_path(company), alert: suggestion.errors.full_messages.to_sentence
    end
  end
end
