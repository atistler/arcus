require 'net/http'
require 'active_support/core_ext'
require 'active_support/inflector'
require 'nori'
require 'nokogiri'
require 'active_support/core_ext/hash/reverse_merge'
require 'nimbus/helpers'
require 'logger'
require 'json'

module Nimbus
  Nori.parser = :nokogiri
  Nori.advanced_typecasting = false

  class << self
    attr_accessor :log
  end

  module Api

    @@targets = []
    @@verbose = false
    @@default_response = "json"

    def self.verbose=(val)
      @@verbose = val
    end

    def self.verbose
      @@verbose
    end

    def self.default_response=(val)
      @@default_response = val
    end

    def self.default_response
      @@default_response
    end

    def self.targets
      @@targets
    end

    class Request
      attr_accessor :command_name, :params, :api_uri, :callbacks

      def initialize(command_name, params, api_uri, callbacks)
        @command_name = command_name
        @params = params
        @api_uri = api_uri
        @callbacks = callbacks
      end

      def fetch(response_type = :object)
        @params[:response] =
            case response_type
              when :json, :yaml, :prettyjson, :object
                "json"
              when :xml, :prettyxml
                "xml"
            end
        http = Net::HTTP.new(@api_uri.host, @api_uri.port)
        http.read_timeout = 5
        http.open_timeout = 1
        req_url = api_uri.path + "?" + URI.encode_www_form(params.merge({:command => @command_name}))
        Nimbus.log.debug { "Sending: #{req_url}" } if Api.verbose == true
        response = begin
          http.get(req_url)
        rescue Timeout::Error => e
          e.instance_eval do
            class << self
              attr_accessor :api_uri
            end
          end
          e.api_uri = @api_uri
          raise e
        end
        Nimbus.log.debug { "Received: #{response.body}" } if Api.verbose == true
        response.instance_eval do
          class << self
            attr_accessor :response_type
          end

          def body
            case @response_type
              when :yaml
                YAML::dump(JSON.parse(super))
              when :prettyjson
                JSON.pretty_generate(JSON.parse(super))
              when :prettyxml
                Nokogiri::XML(super, &:noblanks)
              when :xml, :json
                super
              when :object
                JSON.parse(super)
            end
          end
        end
        response.response_type = response_type
        if response.is_a?(Net::HTTPSuccess)
          callbacks[:success].call(response) if callbacks[:success]
        else
          callbacks[:failure].call(response) if callbacks[:failure]
        end
        response.body if response.is_a?(Net::HTTPSuccess)
      end
    end

    class Target
      extend Helpers
    end

    class Action
      extend Helpers

      def self.check_args(params, all_names, required_names)
        raise ArgumentError, "Invalid arguments: %s" % (params.keys - all_names).join(", "), caller if (params.keys - all_names).count > 0
        raise ArgumentError, "Missing arguments: %s" % (required_names - params.keys).join(", "), caller if (required_names - params.keys).count > 0
      end
    end

    def self.parse_action(name)
      action, target = name.split(/([A-Z].*)/, 2)
      target = "User" if %w(login logout).include?(action)
      target = target.singularize
      [action, target]
    end

    def self.load_config(api_xml)
      contents = File.read(api_xml).to_s
      md5 = Digest::MD5.hexdigest(contents)
      api_xml_basename = File.basename(api_xml)
      md5_file = Dir::home() + "/.#{api_xml_basename}.md5"
      cache_file = Dir::home() + "/.#{api_xml_basename}.cache"
      if File::exists?(md5_file) && File::read(md5_file).to_s == md5 && File::exists?(cache_file)
        config = Marshal.restore(File::read(cache_file))
      else
        config = Nori.parse(contents)
        File::open(md5_file, "w+") do |file|
          file.print md5
        end
        File::open(cache_file, "w+") do |file|
          file.print Marshal.dump(config)
        end
      end
      config
    end

    def self.configure(options = {})
      Nimbus.log = Logger.new(STDOUT)
      Nimbus.log.level = Logger::DEBUG
      Nimbus.log.formatter = proc do |severity, datetime, progname, msg|
        "#{severity} - #{datetime}: #{msg}\n"
      end
      api_xml = options[:api_xml] || (raise ArgumentError, "api_xml file: commands.xml file location required")
      api_uri = options[:api_uri] || (raise ArgumentError, "api_uri: URI of API required")
      @@default_response = options[:default_response] if options[:default_response]
      to_name = lambda { |a| a["name"].to_sym }

      config = self.load_config(api_xml)

      config["commands"]["command"].each do |c|
        command_name = c["name"]
        command_desc = c["description"]
        command_async = c["isAsync"] == "true" ? true : false

        action, target = parse_action(command_name)

        if c["request"] != nil
          all_args = c["request"]["arg"] || []
        else
          all_args = []
        end

        if all_args.is_a?(Hash)
          all_args = [all_args]
        end
        all_args.push({"name" => "response", "description" => "valid response types are yaml, xml, prettyxml, json, prettyjson (json is default)", "required" => "false"})

        required_args = all_args.select { |a| a["required"] == "true" }
        optional_args = all_args.select { |a| a["required"] == "false" }

        all_names = all_args.map(&to_name)
        required_names = required_args.map(&to_name)

        def self.class_exists?(class_name)
          c = self.const_get(class_name)
          return c.is_a?(Class)
        rescue NameError
          return false
        end

        def self.get_class(class_name)
          self.const_get(class_name)
        end

        def self.create_class(class_name, superclass, &block)
          c = Class.new superclass, &block
          self.const_set class_name, c
          c
        end

        if !self.class_exists?(target)
          target_clazz = self.create_class(target, Target) do
            cattr_accessor :actions, :opts
            self.actions = self.opts = []
          end
          @@targets << target_clazz
        else
          target_clazz = self.get_class(target)
        end


        target_clazz.class_eval do
          if !class_exists?(action.capitalize)
            action_clazz = create_class(action.capitalize, Action) do
              cattr_accessor :opts
              self.opts = []
            end
            target_clazz.actions << action_clazz
          else
            action_clazz = get_class(action.capitalize)
          end
          action_clazz.class_eval do
            class << self
              attr_accessor :name, :description, :is_async,
                            :required_args, :optional_args,
                            :action_name, :api_uri, :sync

              def prepare!(params = {}, callbacks = {})
                check_args(params, all_names, required_names)
                prepare(params, callbacks)
              end

              def prepare(params = {}, callbacks = {})
                params[:response] ||= Api.default_response
                Request.new(self.name, params, self.api_uri, callbacks)
              end
            end
          end
          action_clazz.name = command_name
          action_clazz.description = command_desc
          action_clazz.action_name = action
          action_clazz.required_args = required_args
          action_clazz.optional_args = optional_args
          action_clazz.api_uri = api_uri
          action_clazz.is_async = command_async
          action_clazz.sync = false


          define_method(action.to_sym) do |params = {}, callbacks = {}|
            action_clazz.prepare(params, callbacks)
          end
          define_method("#{action}!".to_sym) do |params = {}, callbacks = {}|
            action_clazz.prepare(params, callbacks)
          end

        end
      end
    end
  end
end