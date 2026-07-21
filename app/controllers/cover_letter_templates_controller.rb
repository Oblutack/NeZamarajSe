# app/controllers/cover_letter_templates_controller.rb
class CoverLetterTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:edit, :update, :destroy]

  def index
    @templates = current_user.cover_letter_templates.order(created_at: :desc)
  end

  def new
    @template = current_user.cover_letter_templates.build
  end

  def create
    @template = current_user.cover_letter_templates.build(template_params)
    
    if @template.save
      redirect_to cover_letter_templates_path, notice: "Template created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to cover_letter_templates_path, notice: "Template updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to cover_letter_templates_path, notice: "Template deleted.", status: :see_other
  end

  private

  def set_template
    @template = current_user.cover_letter_templates.find(params[:id])
  end

  def template_params
    params.require(:cover_letter_template).permit(:name, :body)
  end
end