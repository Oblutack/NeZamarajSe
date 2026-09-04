class AddAiFieldsToCoverLetterTemplates < ActiveRecord::Migration[8.1]
  def change
    # ai_generated drives whether the "Translate to..." button shows on the
    # compose page (see ApplicationsController#translate_cover_letter) -
    # only relevant for a letter the AI wrote, not one a user typed
    # themselves. language tracks which language the body is currently in,
    # so translate can offer "the other one" without guessing.
    add_column :cover_letter_templates, :ai_generated, :boolean, default: false, null: false
    add_column :cover_letter_templates, :language, :string
  end
end
