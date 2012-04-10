require 'cmdparse'
require 'nimbus/api'

module Nimbus

  attr_accessor :verbose

  class Cli
    include Api
    extend Api

    def initialize(options = {})
      configure(options)
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
      cmd = CmdParse::CommandParser.new( true, true )
      cmd.program_name = __FILE__
      cmd.program_version = [0, 0, 1]
      cmd.options = CmdParse::OptionParserWrapper.new do |opt|
        opt.separator "Global options:"
        opt.on("--verbose", "Be verbose when outputting info") {|t| Nimbus::verbose = true }
      end
      cmd.add_command( CmdParse::HelpCommand.new )
      cmd.add_command( CmdParse::VersionCommand.new )

      Api.targets.each do |t|
        target_name = class_string(t).downcase
        target_cmd = CmdParse::Command.new(target_name, true, true)
        cmd.add_command(target_cmd)
        t.actions.each do |a|
          action_name = a.action_name
          action_cmd = CmdParse::Command.new(action_name, false)
          action_cmd.set_execution_block do |args|
            p args
            p "#{t} #{a}"
          end
          target_cmd.add_command(action_cmd)
        end
      end
      cmd.parse
    end
  end
end