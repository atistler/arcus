require 'net/http'
require 'active_support/core_ext'
require 'active_support/inflector'
require 'nori'
require 'active_support/core_ext/hash/reverse_merge'
require 'pp'
require 'nimbus/helpers'

module Nimbus
  module Api
    include Helpers

    class Target
    end

    class Action
      def api_call(command_name, params, api_uri, callbacks)
        http = Net::HTTP.new(api_uri.host, api_uri.port)
        http.read_timeout = 5
        http.open_timeout = 1
        response = http.get(api_uri.path + "?" + URI.encode_www_form(params.merge({:command => command_name})))
        if response.is_a?(Net::HTTPSuccess)
          callbacks[:success].call(response) if callbacks[:success]
        else
          callbacks[:failure].call(response) if callbacks[:failure]
        end
        response.body if response.is_a?(Net::HTTPSuccess)
      end

      def check_args(params, all_names, required_names)
        raise ArgumentError, "Invalid arguments: %s" % (params.keys - all_names).join(", "), caller if (params.keys - all_names).count > 0
        raise ArgumentError, "Missing arguments: %s" % (required_names - params.keys).join(", "), caller if (required_names - params.keys).count > 0
      end
    end

    @@targets = []

    Nori.parser = :nokogiri
    Nori.advanced_typecasting = false

    def targets
      @@targets
    end

    def parse_action(name)
      action, target = name.split(/([A-Z].*)/, 2)
      target = "User" if %w(login logout).include?(action)
      target = target.singularize
      [action, target]
    end

    def configure(options = {})
      api_xml = options[:api_xml] || (raise ArgumentError, "xml_file: commands.xml file location required")
      api_uri = options[:api_uri] || (raise ArgumentError, "api_uri: URI of API required")
      default_response = options[:default_response] || "xml"
      to_name = lambda { |a| a["name"].to_sym }

      config = Nori.parse(File.read(api_xml).to_s)

      config["commands"]["command"].each do |c|
        command_name = c["name"]
        command_desc = c["description"]

        action, target = parse_action(command_name)

        if c["request"] != nil
          all_args = c["request"]["arg"] || []
        else
          all_args = []
        end

        if all_args.is_a?(Hash)
          all_args = [all_args]
        end

        required_args = all_args.select { |a| a["required"] == "true" }
        optional_args = all_args.select { |a| a["required"] == "false" }

        all_names = all_args.map(&to_name)
        required_names = required_args.map(&to_name)

        if !class_exists?(target)
          target_clazz = create_class(target, Target) do
            cattr_accessor :actions, :opts
            self.actions = self.opts = []
          end
          target_clazz.extend(Helpers)
          @@targets << target_clazz
        else
          target_clazz = get_class(target)
        end


        target_clazz.class_eval do
          if !class_exists?(action.capitalize)
            action_clazz = create_class(action.capitalize, Action) do
              cattr_accessor :opts
              self.opts = []
            end
            action_clazz.extend(Helpers)
            target_clazz.actions << action_clazz
          else
            action_clazz = get_class(action.capitalize)
          end
          action_clazz.class_eval do
            class << self
              attr_accessor :name, :description, :required_args, :optional_args, :action_name
            end

            def execute!(params = {}, callbacks = {})
              check_args(params, all_names, required_names)
              execute(params, callbacks)
            end

            def execute(params = {}, callbacks = {})
              params[:response] ||= default_response
              api_call(command_name, params, api_uri, callbacks)
            end
          end
          action_clazz.name = command_name
          action_clazz.description = command_desc
          action_clazz.action_name = action
          action_clazz.required_args = required_args
          action_clazz.optional_args = optional_args

          define_method(("%s" % action).to_sym) do
            action_clazz.new.execute
          end
          define_method(("%s!" % action).to_sym) do
            action_clazz.new.execute!
          end
        end
      end
    end
  end
end