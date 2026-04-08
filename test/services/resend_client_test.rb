# frozen_string_literal: true

require "test_helper"

class ResendClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  test "send_email! posts payload and parses json" do
    captured_request = nil
    fake_http = fake_http_client(FakeResponse.new("200", '{"id":"email_1"}')) do |request|
      captured_request = request
    end

    with_singleton_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
      body = ResendClient.new(api_key: "key_123").send_email!(
        from: "onboarding@resend.dev",
        to: "demo@example.com",
        subject: "Hello",
        html: "<p>Hi</p>"
      )
      assert_equal "email_1", body["id"]
    end

    assert_equal "Bearer key_123", captured_request["Authorization"]
    assert_equal "application/json", captured_request["Content-Type"]
    assert_includes captured_request.body, "\"subject\":\"Hello\""
  end

  test "send_email! raises typed error on non-2xx" do
    fake_http = fake_http_client(FakeResponse.new("422", '{"message":"invalid"}'))

    with_singleton_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
      error = assert_raises(ResendClient::Error) do
        ResendClient.new(api_key: "key_123").send_email!(
          from: "onboarding@resend.dev",
          to: "demo@example.com",
          subject: "Hello",
          html: "<p>Hi</p>"
        )
      end
      assert_includes error.message, "status=422"
    end
  end

  private

  def fake_http_client(response)
    recorder = Struct.new(:use_ssl).new(false)
    recorder.define_singleton_method(:use_ssl=) { |_value| nil }
    recorder.define_singleton_method(:request) do |request|
      yield(request) if block_given?
      response
    end
    recorder
  end

  def with_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = singleton.instance_method(method_name) if singleton.method_defined?(method_name)
    singleton.send(:define_method, method_name, &replacement)
    yield
  ensure
    if original
      singleton.send(:define_method, method_name, original)
    else
      singleton.send(:remove_method, method_name)
    end
  end
end
