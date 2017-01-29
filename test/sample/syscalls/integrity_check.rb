require 'fileutils'
require 'open-uri'

require 'katamuki.rb'

require 'minitest/autorun'

class TestSampleSyscalls < MiniTest::Test
  def test_integrity_check
    rootpath = File.join(File.dirname(__FILE__), '../../../sample/syscalls')
    FileUtils.rm_rf("#{rootpath}/.work")
    FileUtils.rm_rf("#{rootpath}/data")
    FileUtils.rm_rf("#{rootpath}/integrity-data")
    open("#{rootpath}/syscalls_data.zip", 'wb') do |f|
      open('https://www.dropbox.com/s/lqbfptatb9axe0a/syscalls_data.zip?dl=1') do |f2|
        f.write(f2.read)
      end
    end
    Kernel.system("unzip #{rootpath}/syscalls_data.zip -d #{rootpath}")
    assert_equal true, Kernel.system("#{rootpath}/test-syscalls.rb --integrity-check")
  end
end
