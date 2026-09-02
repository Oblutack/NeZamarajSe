# app/controllers/locales_controller.rb
class LocalesController < ApplicationController
  def update
    if params[:locale].presence_in(I18n.available_locales.map(&:to_s))
      session[:locale] = params[:locale]
    end

    redirect_back fallback_location: root_path
  end
end
