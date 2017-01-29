$:.unshift(File.join(File.dirname(__FILE__), './hako.rb/lib'))

$HAKO_SHELL_NAME = 'katamuki.rb'
require 'hako.rb'

require 'katamuki/logger'
require 'katamuki/jgram_database'
require 'katamuki/database_learner'
require 'katamuki/logistic_learner'
require 'katamuki/rule_learner'
