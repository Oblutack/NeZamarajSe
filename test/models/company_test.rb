require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "requires a name" do
    company = Company.new(website: "https://example.com")
    assert_not company.valid?
    assert_includes company.errors[:name], "can't be blank"
  end

  test "requires a unique name" do
    duplicate = Company.new(name: companies(:one).name)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "destroying a company destroys its jobs" do
    company = companies(:one)

    assert_difference("Job.count", -1) do
      company.destroy
    end
  end

  test "destroying a company destroys its email suggestions" do
    company = companies(:one)
    company.email_suggestions.create!(user: users(:one), email: "hr@vertexsolutions.example")

    assert_difference("CompanyEmailSuggestion.count", -1) do
      company.destroy
    end
  end

  test "reply_confirmed_send_count is 0 with no primary_email" do
    company = companies(:one)
    assert_nil company.primary_email
    assert_equal 0, company.reply_confirmed_send_count
  end

  test "reply_confirmed_send_count counts applications sent to the primary_email that got a reply" do
    company = companies(:one)
    company.update!(primary_email: "hr@vertexsolutions.example")
    user = users(:one)

    replied_job = Job.create!(company: company, title: "Role With Reply", url: "https://jobs.example.com/role-with-reply")
    no_reply_job = Job.create!(company: company, title: "Role Without Reply", url: "https://jobs.example.com/role-without-reply")
    other_address_job = Job.create!(company: company, title: "Role At Different Address", url: "https://jobs.example.com/role-different-address")

    replied = user.applications.create!(job: replied_job, status: "applied", applied_at: Time.current, sent_recipient: "hr@vertexsolutions.example")
    replied.application_events.create!(event_type: "reply_detected")
    user.applications.create!(job: no_reply_job, status: "applied", applied_at: Time.current, sent_recipient: "hr@vertexsolutions.example")
    other = user.applications.create!(job: other_address_job, status: "applied", applied_at: Time.current, sent_recipient: "someone-else@vertexsolutions.example")
    other.application_events.create!(event_type: "reply_detected")

    assert_equal 1, company.reply_confirmed_send_count
  end
end
