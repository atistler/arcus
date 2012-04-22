require 'net/http'
require 'active_support/core_ext'
require 'active_support/inflector'
require 'active_support/core_ext/hash/reverse_merge'
require 'nori'
require 'nokogiri'
require 'digest/md5'
require 'logger'
require 'json'
require 'arcus/helpers'

module Arcus
  Nori.parser = :nokogiri
  Nori.advanced_typecasting = false

  class << self
    attr_accessor :log
  end

  module Api

    @@targets = []

    class Settings
      attr_accessor :api_uri, :api_xml, :api_key, :api_secret, :default_response, :verbose

      def initialize
        @api_xml = File.dirname(__FILE__) + "/commands.xml"
        @default_response = "json"
        @verbose = false;
      end
    end

    @@settings = Settings.new

    def self.settings
      @@settings
    end

    def self.settings=(val)
      @@settings = val
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
        req_url = @api_uri.path + "?" + URI.encode_www_form(params.merge({:command => @command_name}))
        Arcus.log.debug { "Sending: #{req_url}" } if Api.settings.verbose
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
        Arcus.log.debug { "Received: #{response.body}" } if Api.settings.verbose
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

    class Scope
      attr_accessor :options

      def initialize(options = {})
        @options = options;
      end
    end


    def self.parse_action(name)
      action, target = name.split(/([A-Z].*)/, 2)
      target = "User" if %w(login logout).include?(action)
      target = target.singularize
      [action, target]
    end

    def self.load_config_file(api_xml)
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

    def scoped(options = {})
      yield Scope.new(options = {})
    end

    def self.configure
      Arcus.log = Logger.new(STDOUT)
      Arcus.log.level = Logger::DEBUG
      Arcus.log.formatter = proc do |severity, datetime, progname, msg|
        "#{severity} - #{datetime}: #{msg}\n"
      end

      yield(self.settings)

      self.settings.api_xml || (raise ArgumentError, "api_xml file: commands.xml file location required")
      self.settings.api_uri || (raise ArgumentError, "api_uri: URI of API required")

      api_config = self.load_config_file(self.settings.api_xml)

      api_config["commands"]["command"].each do |c|
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
            cattr_accessor :actions
            self.actions = []
          end
          @@targets << target_clazz

        else
          target_clazz = self.get_class(target)
        end

        target_clazz.class_eval do

          if !class_exists?(action.capitalize)
            action_clazz = create_class(action.capitalize, Action) do
              cattr_accessor :name, :description, :is_async,
                             :required_args, :optional_args,
                             :action_name, :sync

              self.name = command_name
              self.description = command_desc
              self.action_name = action
              self.required_args = required_args
              self.optional_args = optional_args
              self.is_async = command_async
              self.sync = false

              def prepare!(params = {}, callbacks = {})
                check_args(params, all_names, required_names)
                prepare(params, callbacks)
              end

              def prepare(params = {}, callbacks = {})
                params[:response] ||= Api.settings.default_response
                Request.new(self.name, params, Api.settings.api_uri, callbacks)
              end
            end
            target_clazz.actions << action_clazz

            target_clazz.define_singleton_method(action.to_sym) do |params = {}, callbacks = {}|
              action_clazz.new.prepare(params, callbacks)
            end
            target_clazz.define_singleton_method("#{action}!".to_sym) do |params = {}, callbacks = {}|
              action_clazz.new.prepare(params, callbacks)
            end
          end
        end
      end
    end
  end
end
