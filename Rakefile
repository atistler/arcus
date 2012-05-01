#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << 'test'
end
desc "Run tests"

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new('spec')
