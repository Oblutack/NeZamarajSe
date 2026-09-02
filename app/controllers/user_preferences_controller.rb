class UserPreferencesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @preference = current_user.user_preference || current_user.create_user_preference
  end

  def update
    @preference = current_user.user_preference
    if @preference.update(preference_params)
      redirect_to edit_user_preference_path, notice: t("flash.user_preferences.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def preference_params
    params.require(:user_preference).permit(:keywords, :location, :receive_daily_alerts)
  end
end
