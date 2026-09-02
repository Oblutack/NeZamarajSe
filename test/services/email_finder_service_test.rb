require "test_helper"

class EmailFinderServiceTest < ActiveSupport::TestCase
  test "resolves the domain via Clearbit then saves the best matching Hunter.io email" do
    company = companies(:one)
    company.update!(website: nil)

    clearbit_response = [ { domain: "vertex.example" } ].to_json
    hunter_response = {
      data: { emails: [
        { value: "sales@vertex.example" },
        { value: "hr@vertex.example" }
      ] }
    }.to_json

    responses = [ clearbit_response, hunter_response ]
    stub_class_method(Net::HTTP, :get, ->(*) { responses.shift }) do
      EmailFinderService.call(company)
    end

    company.reload
    assert_equal "hr@vertex.example", company.primary_email
    assert_equal "vertex.example", company.domain
  end

  test "resolves the domain from the company's own website without calling Clearbit" do
    company = companies(:one)
    company.update!(website: "https://www.vertexsolutions.example/careers")

    hunter_response = { data: { emails: [ { value: "careers@vertexsolutions.example" } ] } }.to_json

    stub_class_method(Net::HTTP, :get, ->(*) { hunter_response }) do
      EmailFinderService.call(company)
    end

    assert_equal "careers@vertexsolutions.example", company.reload.primary_email
    assert_equal "vertexsolutions.example", company.reload.domain
  end

  test "does nothing when no domain can be resolved" do
    company = companies(:one)
    company.update!(website: nil, name: "Totally Unknown Co")

    stub_class_method(Net::HTTP, :get, ->(*) { "[]" }) do
      EmailFinderService.call(company)
    end

    assert_nil company.reload.primary_email
  end

  test "records a HunterLookup for every Hunter.io call actually made" do
    company = companies(:one)
    company.update!(website: "https://www.vertexsolutions.example")
    hunter_response = { data: { emails: [ { value: "careers@vertexsolutions.example" } ] } }.to_json

    assert_difference("HunterLookup.count", 1) do
      stub_class_method(Net::HTTP, :get, ->(*) { hunter_response }) do
        EmailFinderService.call(company)
      end
    end

    assert_equal company, HunterLookup.last.company
  end

  def with_hunter_quota(value)
    original = Rails.application.config.hunter_monthly_quota
    Rails.application.config.hunter_monthly_quota = value
    yield
  ensure
    Rails.application.config.hunter_monthly_quota = original
  end

  test "skips the Hunter.io call once this month's quota is reached" do
    company = companies(:one)
    company.update!(website: "https://www.vertexsolutions.example")
    other = companies(:two)
    other.update!(website: "https://www.northbridgesystems.example")
    HunterLookup.create!(company: other)

    with_hunter_quota(1) do
      assert_no_difference("HunterLookup.count") do
        stub_class_method(Net::HTTP, :get, ->(*) { raise "should not call Hunter" }) do
          EmailFinderService.call(company)
        end
      end
    end

    assert_nil company.reload.primary_email
  end
end
