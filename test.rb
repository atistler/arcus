
response_type = :json
t = case response_type
  when :json, :yaml, :prettyjson, nil
    "json"
  when :xml, :prettyxml
    "xml"
    end

p t