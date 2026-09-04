require "test_helper"

class PublicJobsControllerTest < ActionDispatch::IntegrationTest
  test "renders a shared job with no login required" do
    job = jobs(:one)
    job.share!

    get public_job_url(job.share_token)

    assert_response :success
    assert_select "h1", text: job.title
  end

  test "never exposes hr_email or who added the job" do
    job = jobs(:one)
    job.update!(hr_email: "secret-hr@realcompany.example")
    job.share!

    get public_job_url(job.share_token)

    assert_no_match(/secret-hr@realcompany\.example/, response.body)
    assert_no_match(/#{Regexp.escape(users(:one).email)}/, response.body)
  end

  test "sets a noindex robots header" do
    job = jobs(:one)
    job.share!

    get public_job_url(job.share_token)

    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "a made-up token 404s" do
    get public_job_url("not-a-real-token")

    assert_response :not_found
  end

  test "an unshared job's token no longer resolves" do
    job = jobs(:one)
    token = job.share!
    job.unshare!

    get public_job_url(token)

    assert_response :not_found
  end
end
