require "test_helper"

class CoverLetterTemplateTest < ActiveSupport::TestCase
  test "requires a name unique per user" do
    duplicate = CoverLetterTemplate.new(
      user: users(:one), name: cover_letter_templates(:one).name, body: "Body"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "two different users can each use the same template name" do
    other_user = User.create!(email: "another-user@example.com", password: "password123")
    template = CoverLetterTemplate.new(
      user: other_user, name: cover_letter_templates(:one).name, body: "Body"
    )
    assert template.valid?
  end

  test "requires a body" do
    template = CoverLetterTemplate.new(user: users(:one), name: "Empty")
    assert_not template.valid?
    assert_includes template.errors[:body], "can't be blank"
  end

  test "render_content substitutes smart tags from the job" do
    template = cover_letter_templates(:one)
    job = jobs(:one)

    rendered = template.render_content(job)

    assert_includes rendered, job.company.name
    assert_includes rendered, job.title
    assert_includes rendered, job.location
  end

  test "render_content falls back to a generic location when the job has none" do
    template = cover_letter_templates(:one)
    job = jobs(:one)
    job.location = nil

    rendered = template.render_content(job)

    assert_includes rendered, "your office"
  end
end
