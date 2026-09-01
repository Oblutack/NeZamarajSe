class MigrateCoverLetterTemplateBodyToRichText < ActiveRecord::Migration[8.1]
  class CoverLetterTemplate < ApplicationRecord
    self.table_name = "cover_letter_templates"

    # Without this, ActionText's polymorphic record_type column gets stamped
    # with this migration-scoped class's own namespaced name
    # ("MigrateCoverLetterTemplateBodyToRichText::CoverLetterTemplate")
    # instead of "CoverLetterTemplate" - the app's real model would then
    # never find the rich text it just wrote.
    def self.polymorphic_name
      "CoverLetterTemplate"
    end

    has_rich_text :body
  end

  def up
    rename_column :cover_letter_templates, :body, :legacy_body
    CoverLetterTemplate.reset_column_information

    CoverLetterTemplate.find_each do |template|
      html = ERB::Util.html_escape(template.legacy_body.to_s).gsub("\n", "<br>")
      template.update!(body: html)
    end

    remove_column :cover_letter_templates, :legacy_body
  end

  def down
    add_column :cover_letter_templates, :legacy_body, :text
    CoverLetterTemplate.reset_column_information

    CoverLetterTemplate.find_each do |template|
      template.update_column(:legacy_body, template.body.to_plain_text)
    end

    ActionText::RichText.where(record_type: "CoverLetterTemplate").delete_all
    rename_column :cover_letter_templates, :legacy_body, :body
    change_column_null :cover_letter_templates, :body, false
  end
end
