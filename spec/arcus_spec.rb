require 'spec_helper'
require 'rspec/core'

Arcus::Api.configure do |c|
   c.api_uri = "http://icloud-staging-api.logicworks.net:8096/client/api"
   c.default_response = "json"
end

include Arcus::Api

describe Domain do
  pending "Domain test"
end
