require 'cmdparse'
require 'arcus/api'
require 'json'

module Arcus

  class Cli
    include Api

    def initialize(options = {})
      options[:api_xml] = File.dirname(__FILE__) + "/commands.xml"
      Api.configure(options)
    end

    def word_wrap(text, *args)
      options = args.extract_options!
      unless args.blank?
        options[:line_width] = args[0] || 80
      end
      options.reverse_merge!(:line_width => 80)

      text.split("\n").collect do |line|
        line.length > options[:line_width] ? line.gsub(/(.{1,#{options[:line_width]}})(\s+|$)/, "\\1\n").strip : line
      end * "\n"
    end

    def text_width(text, width)
      word_wrap(text, :line_width => width).split("\n") if !text.nil?
    end

    def class_string(clazz)
      clazz.name.split('::').last
    end

    def class_sym(clazz)
      class_string(clazz).to_sym
    end

    def method_sym(meth)
      meth["name"].to_sym
    end

    def method_string(meth)
      meth["name"]
    end

    def run
      cmd = CmdParse::CommandParser.new(true, true)
      cmd.program_name = $0

      cmd.program_version = [0, 0, 1]
      cmd.options = CmdParse::OptionParserWrapper.new do |opt|
        opt.separator "Global options:"
        opt.on("--verbose", "Be verbose when outputting info") { Arcus::Api.verbose = true }
      end
      cmd.add_command(CmdParse::HelpCommand.new)
      cmd.add_command(CmdParse::VersionCommand.new)

      Api.targets.each do |t|
        target_name = class_string(t).downcase
        target_cmd = CmdParse::Command.new(target_name, true, true)
        cmd.add_command(target_cmd)
        t.actions.each do |a|
          action_name = a.action_name
          action_cmd = CmdParse::Command.new(action_name, false)
          action_cmd.short_desc = a.description.split(".").first

          required_params = optional_params = {}
          action_cmd.options = CmdParse::OptionParserWrapper.new do |opt|

            if !a.required_args.empty?
              opt.separator "Required:"
              opt.separator ""
              a.required_args.each do |ra|
                opt.on("--#{ra['name']} #{ra['name'].upcase}", *text_width(ra["description"], 100)) do |val|
                  required_params[ra["name"].to_sym] = val
                end
              end
            end
            if !a.optional_args.empty?
              opt.separator ""
              opt.separator "Optional:"
              opt.separator ""
              a.optional_args.each do |ra|
                opt.on("--#{ra['name']} #{ra['name'].upcase}", *text_width(ra["description"], 100)) do |val|
                  required_params[ra["name"].to_sym] = val
                end
              end
            end
            if a.is_async
              opt.on("--sync POLL_INTERVAL", "continuously poll the job for results ever POLL_INTERVAL seconds") do |val|
                a.sync = val
              end
            end
          end
          action_cmd.set_execution_block {
            missing_params = a.required_args.map { |n| n["name"].to_sym } - required_params.keys
            if (missing_params.empty?)
              begin
                response_type = optional_params[:response] || Api.default_response
                if a.sync
                  result = a.prepare(required_params.merge(optional_params)).fetch
                  job_id = result["#{a.name.downcase}response"]["jobid"]
                  job_finished = false
                  until job_finished
                    sleep a.sync.to_i.seconds
                    job_result = AsyncJobResult.new.query({:jobid => job_id}).fetch
                    if job_result["queryasyncjobresultresponse"]["jobstatus"] != 0
                      job_finished = true
                    end
                  end
                  puts AsyncJobResult.new.query({:jobid => job_id}).fetch(response_type.to_sym)
                else
                  puts a.prepare(required_params.merge(optional_params)).fetch(response_type.to_sym)
                end
              rescue Timeout::Error => e
                puts "Timeout connecting to #{e.api_uri}"
                exit(false)
              end
            else
              puts "Missing required ARGS: #{missing_params.map { |n| "--#{n}" }.join(", ")}\n"
              action_cmd.show_help
              exit(false)
            end
          }
          target_cmd.add_command(action_cmd)
        end
      end
      cmd.parse
    end
  end
end