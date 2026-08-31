ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Minitest's Mock/#stub live in the "minitest-mock" gem, which isn't part of
    # this app's bundle (Minitest 6 split it out) - so tests stub a class method
    # by hand instead of pulling in a new dependency. `replacement` is returned
    # as-is when the stubbed method is called, unless it's a Proc, in which case
    # it's invoked with the same arguments and its return value is used instead.
    # (Checking Proc specifically, rather than respond_to?(:call), matters: a
    # fake object being returned as-is might itself define #call as the thing
    # under test - respond_to?(:call) would wrongly invoke it instead of
    # returning it.)
    def stub_class_method(klass, method_name, replacement)
      singleton = klass.singleton_class
      original_name = :"__original_#{method_name}"
      singleton.send(:alias_method, original_name, method_name)
      singleton.define_method(method_name) do |*args|
        replacement.is_a?(Proc) ? replacement.call(*args) : replacement
      end
      yield
    ensure
      singleton.send(:remove_method, method_name)
      singleton.send(:alias_method, method_name, original_name)
      singleton.send(:remove_method, original_name)
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
