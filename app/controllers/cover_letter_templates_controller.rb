# app/controllers/cover_letter_templates_controller.rb
class CoverLetterTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [ :edit, :update, :destroy, :translate ]

  def index
    @templates = current_user.cover_letter_templates.order(created_at: :desc)
  end

  def new
    @template = current_user.cover_letter_templates.build
  end

  def create
    @template = current_user.cover_letter_templates.build(template_params)

    if @template.save
      redirect_to cover_letter_templates_path, notice: t("flash.cover_letter_templates.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to cover_letter_templates_path, notice: t("flash.cover_letter_templates.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to cover_letter_templates_path, notice: t("flash.cover_letter_templates.deleted"), status: :see_other
  end

  def generate
    resume = current_user.resumes.find { |r| r.blob_id == params[:resume_blob_id].to_i }

    if resume.nil?
      redirect_to new_cover_letter_template_path, alert: t("flash.cover_letter_templates.select_a_resume_first")
      return
    end

    language = params[:language]
    body_html = CoverLetterTemplateGeneratorService.call(resume_blob: resume.blob, language: language)

    template = current_user.cover_letter_templates.create!(
      name: "AI Template (#{l(Time.current, format: '%b %-d, %H:%M')})",
      body: body_html,
      ai_generated: true,
      language: CoverLetterTemplate::LANGUAGES.key?(language) ? language : "en"
    )

    redirect_to edit_cover_letter_template_path(template), notice: t("flash.cover_letter_templates.generated")
  rescue StandardError => e
    Honeybadger.notify(e, context: { user_id: current_user.id })
    redirect_to new_cover_letter_template_path, alert: t("flash.cover_letter_templates.generation_failed")
  end

  def translate
    language = params[:language]
    translated_html = CoverLetterTranslatorService.call(plain_text: @template.body.to_plain_text, target_language: language)
    @template.update!(body: translated_html, language: CoverLetterTemplate::LANGUAGES.key?(language) ? language : "en")

    redirect_to edit_cover_letter_template_path(@template)
  rescue StandardError => e
    Honeybadger.notify(e, context: { template_id: params[:id] })
    redirect_to edit_cover_letter_template_path(@template), alert: t("flash.cover_letter_templates.translation_failed")
  end

  private

  def set_template
    @template = current_user.cover_letter_templates.find(params[:id])
  end

  def template_params
    params.require(:cover_letter_template).permit(:name, :body)
  end
end
