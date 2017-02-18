require 'rake/testtask'

$:.unshift(File.join(File.dirname(__FILE__), './lib'))

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/*.rb']
  t.verbose = true
end
Rake::TestTask.new(:test_samples) do |t|
  t.test_files = FileList['test/sample/**/*.rb']
  t.verbose = true
end

task :default => [:build, :test, :test_samples]
task :build do |t|
  sh 'rake -f lib/hako.rb/Rakefile build'
end
