$HAKO_SHELL_NAME = 'katamuki.rb'
$:.unshift(File.join(File.dirname(__FILE__), './hako.rb/lib'))
require 'hako.rb'

require 'katamuki/logger'
require 'katamuki/jgram_database'
require 'katamuki/database_learner'
require 'katamuki/logistic_learner'
require 'katamuki/rule_learner'
