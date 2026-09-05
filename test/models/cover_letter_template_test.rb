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

  test "render_content_for_company substitutes the company name and blanks job-specific tags" do
    template = cover_letter_templates(:one)
    template.update!(body: "Dear {{company_name}}, I'm interested in {{job_title}} at {{location}}.")
    company = companies(:one)

    rendered = template.render_content_for_company(company)

    assert_includes rendered, company.name
    assert_not_includes rendered, "{{job_title}}"
    assert_not_includes rendered, "{{location}}"
  end

  test "sent_count and reply_count only count applications actually sent with this template" do
    user = users(:one)
    template = cover_letter_templates(:one)
    other_template = CoverLetterTemplate.create!(user: user, name: "Other Template", body: "Body")

    job_a = Job.create!(company: companies(:one), title: "Role A", url: "https://jobs.example.com/role-a")
    job_b = Job.create!(company: companies(:one), title: "Role B", url: "https://jobs.example.com/role-b")
    job_c = Job.create!(company: companies(:one), title: "Role C", url: "https://jobs.example.com/role-c")

    app_a = user.applications.create!(job: job_a, status: "applied", applied_at: Time.current, cover_letter_template: template)
    user.applications.create!(job: job_b, status: "applied", applied_at: Time.current, cover_letter_template: template)
    user.applications.create!(job: job_c, status: "applied", applied_at: Time.current, cover_letter_template: other_template)

    app_a.application_events.create!(event_type: "reply_detected")

    assert_equal 2, template.sent_count
    assert_equal 1, template.reply_count
    assert_equal 1, other_template.sent_count
    assert_equal 0, other_template.reply_count
  end

  test "sent_count and reply_count ignore applications not yet sent with this template" do
    template = cover_letter_templates(:one)

    assert_equal 0, template.sent_count
    assert_equal 0, template.reply_count
  end

  test "language accepts a supported code or nil, rejects anything else" do
    template = cover_letter_templates(:one)

    template.language = "en"
    assert template.valid?

    template.language = "bs"
    assert template.valid?

    template.language = nil
    assert template.valid?

    template.language = "fr"
    assert_not template.valid?
    assert_includes template.errors[:language], "is not included in the list"
  end

  test "ai_generated defaults to false" do
    template = CoverLetterTemplate.create!(user: users(:one), name: "Manual", body: "Body")

    assert_equal false, template.ai_generated
  end

  test "unique_ai_name returns the base name when it's free" do
    user = users(:one)

    assert_equal "AI Template (Sep 5, 07:48:25)",
      CoverLetterTemplate.unique_ai_name(user, "AI Template (Sep 5, 07:48:25)")
  end

  test "unique_ai_name appends a suffix when two generations land on the same name" do
    user = users(:one)
    base = "AI Template (Sep 5, 07:48)"
    user.cover_letter_templates.create!(name: base, body: "Body")

    assert_equal "#{base} (2)", CoverLetterTemplate.unique_ai_name(user, base)
  end

  test "unique_ai_name keeps incrementing past multiple collisions" do
    user = users(:one)
    base = "AI Template (Sep 5, 07:48)"
    user.cover_letter_templates.create!(name: base, body: "Body")
    user.cover_letter_templates.create!(name: "#{base} (2)", body: "Body")
    user.cover_letter_templates.create!(name: "#{base} (3)", body: "Body")

    assert_equal "#{base} (4)", CoverLetterTemplate.unique_ai_name(user, base)
  end

  test "unique_ai_name is scoped per user - another user's name in use doesn't force a suffix" do
    other_user = User.create!(email: "collision-check@example.com", password: "password123")
    base = "AI Template (Sep 5, 07:48)"
    other_user.cover_letter_templates.create!(name: base, body: "Body")

    assert_equal base, CoverLetterTemplate.unique_ai_name(users(:one), base)
  end

  test "deleting a template nullifies cover_letter_template_id rather than removing the application" do
    user = users(:one)
    template = CoverLetterTemplate.create!(user: user, name: "Disposable", body: "Body")
    job = Job.create!(company: companies(:one), title: "Role D", url: "https://jobs.example.com/role-d")
    application = user.applications.create!(job: job, status: "applied", applied_at: Time.current, cover_letter_template: template)

    template.destroy

    assert_nil application.reload.cover_letter_template_id
  end
end
