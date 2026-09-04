# app/services/resume_text_extractor.rb
require "pdf/reader"
require "stringio"

# Shared by every AI cover-letter service (per-job drafts and reusable
# templates alike) - reads a resume PDF blob into plain text for a prompt.
class ResumeTextExtractor
  MAX_CHARS = 4000

  def self.call(resume_blob)
    reader = PDF::Reader.new(StringIO.new(resume_blob.download))
    reader.pages.map(&:text).join("\n").strip.first(MAX_CHARS)
  rescue StandardError => e
    Honeybadger.notify(e, context: { resume_blob_id: resume_blob.id })
    ""
  end
end
