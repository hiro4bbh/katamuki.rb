require 'rake/testtask'

$:.unshift(File.join(File.dirname(__FILE__), './lib'))

Rake::TestTask.new do |t|
  t.test_files = FileList['test/**/*.rb']
  t.verbose = true
end

task :default => [:build, :test]
task :build do |t|
  sh 'rake -f lib/hako.rb/Rakefile build'
end
