# app/services/cover_letter_formatting.rb

# Shared by every AI cover-letter service. simple_format only inserts real
# paragraph spacing (<p>) at a blank line - a single \n just becomes a
# cramped <br/>, which is what made AI-generated letters read as one big
# block. The model doesn't reliably separate paragraphs with a blank line
# even when explicitly asked, so if its response has no blank line at all,
# treat every line break it did write as a paragraph break instead.
module CoverLetterFormatting
  def normalize_paragraphs(text)
    text.include?("\n\n") ? text : text.gsub(/\n+/, "\n\n")
  end
end
