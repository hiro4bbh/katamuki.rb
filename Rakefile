require 'rake/testtask'

$:.unshift(File.join(File.dirname(__FILE__), './lib'))

Rake::TestTask.new do |t|
  t.test_files = FileList['test/**/*.rb']
  t.verbose = true
end

task :default => [:test]
