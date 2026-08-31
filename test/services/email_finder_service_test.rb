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
end
