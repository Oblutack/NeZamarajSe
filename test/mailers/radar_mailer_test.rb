require "test_helper"

class RadarMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @company = companies(:one)
  end

  def job(title)
    Job.create!(company: @company, title: title, url: "https://jobs.example.com/#{SecureRandom.hex(6)}")
  end

  test "is addressed to the user from the user's own address" do
    mail = RadarMailer.daily_summary(@user, [ job("Software Role") ])

    assert_equal [ @user.email ], mail.to
    assert_equal [ @user.email ], mail.from,
      "Gmail stamps the authenticated account as sender, so any other From would just be overwritten"
    assert_match(/NeZamarajSe Radar/, mail[:from].to_s)
  end

  test "grammar agrees with the count in the subject" do
    one = RadarMailer.daily_summary(@user, [ job("A") ])
    many = RadarMailer.daily_summary(@user, [ job("B"), job("C") ])

    assert_equal "🎯 NeZamarajSe: 1 new job matches your radar!", one.subject
    assert_equal "🎯 NeZamarajSe: 2 new jobs match your radar!", many.subject
  end

  test "grammar agrees with the count in the body too" do
    one = RadarMailer.daily_summary(@user, [ job("A") ])
    many = RadarMailer.daily_summary(@user, [ job("B"), job("C") ])

    assert_match(/<strong>1<\/strong> new job matching/, one.body.decoded)
    assert_match(/<strong>2<\/strong> new jobs matching/, many.body.decoded)
  end

  test "each job links to its own page instead of a hardcoded localhost url" do
    first = job("First Software Role")
    second = job("Second Software Role")
    body = RadarMailer.daily_summary(@user, [ first, second ]).body.decoded

    assert_includes body, "/jobs/#{first.id}"
    assert_includes body, "/jobs/#{second.id}"
    assert_no_match(/localhost/, body)
  end
end
