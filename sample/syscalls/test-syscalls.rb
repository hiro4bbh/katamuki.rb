#!/usr/bin/env ruby
require 'optparse'
require 'pathname'
require 'stringio'
require 'zlib'

$:.unshift(File.join(File.dirname(__FILE__), '../../lib'))
require 'katamuki.rb'

$logger = StandardLogger.new()
$stdout_logger = $logger

class SyscallDatabase
  class Trace
    include Enumerable
    include Alphamap16::Decoder
    include Alphamap16::Encoder
    attr_reader :path, :pid, :alphamap, :data
    def initialize(path, pid, alphamap, data)
      @path = path
      @pid = pid
      @alphamap = alphamap
      raise "data must be little-endian-uint16-encoded String" unless data.is_a? String
      @data = data
    end
    def inspect
      "SyscallDatabase::Trace<path=#{path}, pid=#{pid}, alphamap=#{alphamap}, data.length=#{data.length}>"
    end
    alias to_s inspect
    def length
      data.length/2
    end

    def each
      (data.length/2).times do |i| yield data[(i*2)..(i*2+1)] end
    end
    def each_Jgram(_J)
      (data.length/2 - _J + 1).times do |i| yield data[(i*2)..((i+_J)*2-1)] end
    end
  end
  class TraceFile
    include Enumerable
    include Alphamap16::Decoder
    include Alphamap16::Encoder
    attr_reader :path, :alphamap
    def initialize(path, alphamap)
      @path = path
      @alphamap = alphamap
      @traces = {}
      @Jgrams_cache = {}
    end
    def inspect
      "SyscallDatabase::TraceFile<path=#{path}, alphamap=#{@alphamap}, traces={#{
        @traces.map do |name, trace| "#{name.inspect}=>[size=#{trace.length}]" end.join(', ')
      }}>"
    end
    alias to_s inspect
    def ntraces
      @traces.length
    end

    def each
      @traces.each do |name, trace| yield(name, trace) end
    end
    def each_Jgram(_J)
      Jgrams(_J).each do |x, weight| yield(x, weight) end
    end
    def Jgram(*x)
      Jgrams(x.length)[encode(*x)] || 0
    end
    def Jgrams(_J)
      return @Jgrams_cache[_J] if @Jgrams_cache[_J]
      cache_path = File.join($work_path, "#{File.basename(path)}-#{_J}grams.bin.gz")
      if File.exist?(cache_path) then
        @Jgrams_cache[_J] = load_object(cache_path)
        return @Jgrams_cache[_J]
      end
      report_processing_time("loading and caching #{_J}-grams in #{path}", at_start: true) do
        _Jgrams = @Jgrams_cache[_J] = {}
        @traces.each do |name, trace|
          trace.each_Jgram(_J) do |x|
            _Jgrams[x] = (_Jgrams[x] || 0) + 1
          end
        end
        dump_object(cache_path, _Jgrams)
        _Jgrams
      end
    end
    def [](name)
      @traces[name]
    end

    def add_traces(io, subpath='')
      traces = {}
      io.read.split("\n").each do |line|
        key = line.split(' ')
        pid, x = key[0].to_i, key[1].to_i
        (traces[pid] ||= []).push(x)
      end
      traces.each do |pid, seq|
        fullpath = if subpath == '' then @path else File.join(@path, subpath) end
        name = "#{subpath}:#{pid}"
        raise "detected collision at #{name}" if @traces[name]
        @traces[name] = Trace::new(fullpath, pid, @alphamap, seq.pack('s<*'))
      end
    end
  end
  attr_reader :root_path
  def initialize(root_path)
    @root_path = root_path
    @files = {}
  end
  def inspect
    "SyscallDatabase<root_path=#{root_path}, files=#{@files.keys}>"
  end
  alias to_s inspect

  def each
    @files.each do |path, file| yield(path, file) end
  end
  def [](relpath)
    @files[relpath]
  end

  def load_file(file, subpath='', io=nil)
    fullpath = if subpath == '' then file.path else File.join(file.path, subpath) end
    case fullpath
    when /.int.gz$/ then
      gz = if io then Zlib::GzipReader.new(io) else Zlib::GzipReader.open(fullpath) end
      file.add_traces(gz, subpath)
      gz.close
    when /.int$/ then
      f = if io then io else File.open(fullpath) end
      file.add_traces(f, subpath)
      f.close
    when /.tar.gz$/ then
      Zlib::GzipReader.open(fullpath) do |gz|
        while true
          blk = gz.read(512)
          hdr = {
            :name => blk[0..(100-1)].gsub(/\0*$/, ''),
            :size => blk[124..(124+12-1)].to_i(8),
            :type => blk[156],
          }
          break if hdr[:name] == '' and hdr[:size] == 0 and hdr[:type] == "\0"
          if hdr[:type] == '0' then
            load_file(file, File.join(subpath, hdr[:name]), StringIO.new(gz.read(hdr[:size])))
            gz.read((hdr[:size]+511)/512*512 - hdr[:size])
          else
            gz.read((hdr[:size]+511)/512*512)
          end
        end
      end
    else
      throw "unsupported file: #{fullpath}"
    end
  end
  def load(relpath)
    return relpath if @files[relpath]
    cache_path = File.join($work_path, "#{File.basename(relpath)}.bin.gz")
    @files[relpath] = if File.exist?(cache_path) then
      load_object(cache_path)
    else
      report_processing_time("loading and caching #{relpath}", at_start: true) do
        fullpath = File.join(@root_path, relpath)
        raise "#{fullpath} not found" unless File.exist?(fullpath)
        file = TraceFile.new(fullpath, Alphamap16.new(File.read(File.join(@root_path, "#{relpath.split('-')[0..-2].join('-')}-alphamap.txt")).split("\n")))
        load_file(file)
        dump_object(cache_path, file)
        file
      end
    end
    return relpath
  end
end

$work_path = File.join(File.dirname(__FILE__), './.work')
Dir.mkdir($work_path) unless Dir.exist?($work_path)
$syscalldb = SyscallDatabase.new(File.join(File.dirname(__FILE__), './data'))
Dir.glob(File.join($syscalldb.root_path, '*-{normal,abnormal}.{int,int.gz,tar.gz}')).each do |path|
  relpath = Pathname.new(path).relative_path_from(Pathname.new($syscalldb.root_path)).to_s
  $syscalldb.load(relpath)
end

$train_dbs, $train_splitted_dbs, $train_subdbs, $test_normal_dbs, $test_abnormal_dbs = {}, {}, {}, {}, {}

def load_normal_Jgram_database(_J, relpaths, alphamap=nil)
  files = relpaths.map do |relpath|
    file = $syscalldb[relpath]
    raise "#{relpath} not found" unless file
    file
  end
  return nil if files.length == 0
  db = JgramDatabase16.new(_J, alphamap || Alphamap16::from_alphamaps(files.map do |file| file.alphamap end))
  files.each do |file|
    file.each_Jgram(_J) do |x, weight|
      db.add_weight(db.encode(file.decode(x, to_sym: true).reverse), weight)
    end
  end
  db
end
def load_abnormal_Jgram_databases(_J, train_db, relpaths)
  files = relpaths.map do |relpath|
    file = $syscalldb[relpath]
    raise "#{relpath} not found" unless file
    file
  end
  dbs = []
  files.each do |file|
    file.each do |name, trace|
      db = JgramDatabase16.new(_J, train_db.alphamap)
      n_contains_unknown = 0
      trace.each_Jgram(_J) do |x|
        x_encoded = db.encode(file.decode(x, to_sym: true).reverse)
        $logger&.warn(:load_abnormal_Jgram_databases_malformed, "x=#{x.inspect}, x_encoded=#{x_encoded.inspect}: #{db.decode(x_encoded, to_sym: true)} != #{file.decode(x, to_sym: true)}") if db.decode(x_encoded, to_sym: true).reverse != file.decode(x, to_sym: true)
        if db.decode(x_encoded).include?(-1) then
          n_contains_unknown += 1
        else
          db.add_weight(x_encoded, 1)
        end
      end
      $logger&.warn(:load_abnormal_Jgram_databases, "detected and eliminated :__UNKNOWN__ (weight=#{n_contains_unknown}) in abnormal trace #{file.path}/#{name}") if n_contains_unknown > 0
      dbs << db if db.weight > 0
    end
  end
  dbs
end
def load_Jgrams(_J)
  train_db = $train_dbs[_J] = load_normal_Jgram_database(_J, $options[:training_set])
  $train_splitted_dbs[_J] = train_db.split($options[:nsplits])
  $train_subdbs[_J] = $train_splitted_dbs[_J].collect.with_index do |train_subdb, m|
    train_subdb = JgramDatabase16.new(_J, train_subdb.alphamap)
    $train_splitted_dbs[_J].each.with_index do |subdb, m_|
      train_subdb.merge!(subdb) unless m == m_
    end
    train_subdb
  end
  $test_normal_dbs[_J] = load_normal_Jgram_database(_J, $options[:testing_set].select do |relpath| relpath.include?('-normal') end, train_db.alphamap)
  $test_abnormal_dbs[_J] = load_abnormal_Jgram_databases(_J, train_db, $options[:testing_set].select do |relpath| relpath.include?('-abnormal') end)
end

$models = {}

def run_onestage(_J, t)
  train_splitted_dbs = $train_splitted_dbs[_J]
  models = $models[_J]
  tprs, fprs = [], []
  models.each.with_index do |model, m|
    $logger&.set_stage_id([_J, t, m])
    report_processing_time("learn model<J=#{_J},t=#{t},m=#{m}: #{model.parameter_string}>") do
      model.learn(t)
    end
    classifier = model.classifier
    start = Time.now()
    report_processing_time("test model<J=#{_J},t=#{t},m=#{m}>") do
      tp, fp = [0,0], [0,0]
      train_splitted_dbs[m].each do |row, weight|
        fp[0] += if classifier.calculate_score(row) <= 0 then weight else 0 end
      end
      fp[1] += train_splitted_dbs[m].weight
      if $test_normal_dbs[_J] then
        $test_normal_dbs[_J].each do |row, weight|
          fp[0] += weight if classifier.calculate_score(row) <= 0
        end
        fp[1] += $test_normal_dbs[_J].weight
      end
      $test_abnormal_dbs[_J].each do |db|
        detected = !db.each do |row, _|
          break false if classifier.calculate_score(row) <= 0
        end
        tp[0] += 1 if detected
        tp[1] += 1
      end
      tpr, fpr = Float(tp[0]).divorinf(tp[1]), Float(fp[0]).divorinf(fp[1])
      tprs << tpr
      fprs << fpr
      $logger&.set_stage_data({
        :test_npositives => tp[1], :test_nnegatives => fp[1],
        :test_tp => tp[0], :test_fp => fp[0],
      })
    end
  end
  return unless tprs.length > 0 and fprs.length > 0
  avg_tpr, avg_fpr = tprs.inject(&:+)/models.length, fprs.inject(&:+)/models.length
  $logger&.log(
    :test_stage_tprs_fprs,
    "J=%2u,t=%2u; (min,avg,max)(TPR)=(%.5f,%.5f,%.5f), (min,avg,max)(FPR)=(%.5f,%.5f,%.5f)" % [
      _J, t, tprs.min, avg_tpr, tprs.max, fprs.min, avg_fpr, fprs.max
    ])
end

def run_Jgram(_J, _Tmax)
  _Tmax = [_Tmax, _J].min if $options[:model] == 'db'
  report_processing_time("loading #{_J}-grams", at_start: true) do
    load_Jgrams(_J)
  end
  train_subdbs = $train_subdbs[_J]
  $logger&.info(:run_Jgram_database_split, "#{
    train_subdbs.collect do |subdb| "<size=#{subdb.size}, weight=#{subdb.weight}>" end.join(',')
  }")
  $models[_J] = train_subdbs.map.with_index do |subdb, m|
    report_processing_time("initialize model<J=#{_J},m=#{m}>") do
      case $options[:model]
      when 'db' then DatabaseLearner.new(subdb)
      when /logistic/ then
        LogisticLearner.new(
          subdb,
          min_weight: $options[:min_weight],
          shrinkage: $options[:shrinkage],
          clustering_method: $options[:clustering],
          order: $options[:clustering_order])
      when 'rule' then
        RuleLearner.new(
          subdb,
          $options[:impurity],
          max_depth: $options[:max_depth],
          min_weight: $options[:min_weight])
      else throw "unknown --model=#{$options[:model]}, but supported models are db, logistic, rule"
      end
    end
  end
  1.upto _Tmax do |t| run_onestage(_J, t) end
end

# Auxiliary functions in IRB
def get_stages_data
  stages = $logger&.stages
  return unless stages
  colnames = stages[stages.keys[0]].keys
  df = DataFrame.from_a([], colnames: ['J', 't', 'm'] + colnames)
  stages.each do |_J_t_m, row|
    next unless row
    df << _J_t_m + colnames.collect do |colname| row[colname] end
  end
  df
end

load(File.join(File.dirname(__FILE__), './auxs.rb'))

$output_path = File.join(File.dirname(__FILE__), './output')
Dir.mkdir($output_path) unless Dir.exist?($output_path)
def write_to_file(title, filename, data)
  path = File.join($output_path, filename)
  $logger&.log(:report_model_write_to_file, "writing #{title} to #{path} ...")
  File.write(path, data)
end
def save
  path = "#{$options[:experiment_name]}-Jmin#{$options[:Jmin]}-#{
      if $options[:J] then "J#{$options[:J]}" else "Jmax#{$options[:Jmax]}" end
    }-Tmax#{$options[:Tmax]}-#{$models[$options[:J] || $options[:Jmax]].first.parameter_string}.csv"
  write_to_file('training and testing results', path, get_stages_data.to_csv)
end

def set_default_options
  $options[:experiment_name] ||= 'ftpd_login_sendmail'
  $options[:training_set] ||= case $options[:experiment_name]
  when 'ftpd' then 'ftpd-normal.int.gz'
  when 'ftpd_login_sendmail' then 'ftpd-normal.int.gz,login-live-normal.tar.gz,sendmail-normal.tar.gz'
  else raise "specify --training-set"
  end
  $options[:testing_set] ||= case $options[:experiment_name]
  when 'ftpd' then 'ftpd-abnormal.int.gz'
  when 'ftpd_login_sendmail' then 'ftpd-abnormal.int.gz,login-live-abnormal.int.gz,named-live-abnormal.tar.gz,named-live-normal.int.gz,ps-live-abnormal.int.gz,ps-live-normal.tar.gz'
  else raise "specify --testing-set"
  end
  $options[:training_set] = $options[:training_set].split(',')
  $options[:testing_set] = $options[:testing_set].split(',')
  $options[:Jmin] ||= 2
  $options[:max_depth] ||= 1
  $options[:min_weight] ||= 1.0e-05
  $options[:nsplits] ||= 10
  $options[:shrinkage] ||= 1.0
end

def run_integrity_check
  def assert_equal_dataframes(df1, df2, looses=nil)
    raise "df1.nrows = #{df1.nrows} but df2.nrows = #{df2.nrows}" unless df1.nrows == df2.nrows
    raise "df1.ncols = #{df1.ncols} but df2.ncols = #{df2.ncols}" unless df1.ncols == df2.ncols
    df1.each do |row1|
      rowid = row1.rowid
      row1 = row1[:*]
      row2 = df2.row(rowid)[:*]
      row1.each.with_index do |cell1, j|
        unless cell1.round(10) == row2[j].round(10) then
          msg = "df1.row(#{rowid})[:*] = #{row1} but df2.row(#{rowid})[:*] = #{row2}"
          if looses and looses.include?(j) then
            $stdout_logger.warn(:run_integrity_check, "hit loose check: #{msg}")
          else
            raise msg
          end
        end
      end
    end
  end
  answer_filename_prefix = File.join(File.dirname(__FILE__), 'integrity-data/')
  report_processing_time('testing case `--model=db -J4 --Tmax=4`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'db'
    $options[:J] = 4
    $options[:Tmax] = 4
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'db.csv')), get_stages_data)
  end
  report_processing_time('testing case `--model=rule --impurity=entropy -J4 --Tmax=8`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'rule'
    $options[:impurity] = :entropy
    $options[:J] = 4
    $options[:Tmax] = 8
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'rule-entropy-1.csv')), get_stages_data)
  end
  report_processing_time('testing case `--model=rule --impurity=entropy --max-depth=2 -J4 --Tmax=4`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'rule'
    $options[:impurity] = :entropy
    $options[:max_depth] = 2
    $options[:J] = 4
    $options[:Tmax] = 4
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'rule-entropy-2.csv')), get_stages_data)
  end
  report_processing_time('testing case `--model=rule --impurity=gini -J4 --Tmax=8`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'rule'
    $options[:impurity] = :gini
    $options[:J] = 4
    $options[:Tmax] = 8
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'rule-gini-1.csv')), get_stages_data)
  end
  report_processing_time('testing case `--model=rule --impurity=gini --max-depth=2 -J4 --Tmax=4`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'rule'
    $options[:impurity] = :gini
    $options[:max_depth] = 2
    $options[:J] = 4
    $options[:Tmax] = 4
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'rule-gini-2.csv')), get_stages_data)
  end
  report_processing_time('testing case `--model=logistic --shrinkage=0.0625 --clustering=hierarchical --clustering-order=0 -J3 --Tmax=4`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'logistic'
    $options[:shrinkage] = 0.0625
    $options[:clustering] = :hierarchical
    $options[:clustering_order] = 0
    $options[:J] = 3
    $options[:Tmax] = 4
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'logistic.csv')), get_stages_data, [5])
  end
  report_processing_time('testing case `--model=logistic --shrinkage=0.0625 --clustering=hierarchical --clustering-order=-1 -J12 --Tmax=4`', $stdout_logger, at_start: true) do
    $logger = MemoryLogger.new
    $options = {:shell => $options[:shell]}
    $options[:model] = 'logistic'
    $options[:shrinkage] = 0.0625
    $options[:clustering] = :hierarchical
    $options[:clustering_order] = -1
    $options[:J] = 12
    $options[:Tmax] = 4
    set_default_options
    run_Jgram($options[:J], $options[:Tmax])
    assert_equal_dataframes(DataFrame.from_csv(File.read(answer_filename_prefix+'hierarchical-logistic-1.csv')), get_stages_data, [5])
  end
end

begin
  $options = {}
  OptionParser.new do |parser|
    parser.on('--clustering=VAL') do |value| $options[:clustering] = value.to_sym end
    parser.on('--clustering-order=VAL') do |value| $options[:clustering_order] = Integer(value) end
    parser.on('--experiment-name=VAL') do |value| $options[:experiment_name] = value end
    parser.on('--impurity=VAL') do |value| $options[:impurity] = value.to_sym end
    parser.on('--integrity-check') do |value| $options[:integrity_check] = true end
    parser.on('-JVAL') do |value| $options[:J] = Integer(value) end
    parser.on('--Jmax=VAL') do |value| $options[:Jmax] = Integer(value) end
    parser.on('--Jmin=VAL') do |value| $options[:Jmin] = Integer(value) end
    parser.on('--model=VAL') do |value| $options[:model] = value end
    parser.on('--max-depth=VAL') do |value| $options[:max_depth] = Integer(value) end
    parser.on('--min-weight=VAL') do |value| $options[:min_weight] = Float(value) end
    parser.on('--nsplits=VAL') do |value| $options[:nsplits] = Integer(value) end
    parser.on('--shell') do $options[:shell] = true end
    parser.on('--shrinkage=VAL') do |value| $options[:shrinkage] = Float(value) end
    parser.on('--testing-set=VAL') do |value| $options[:testing_set] = value end
    parser.on('--Tmax=VAL') do |value| $options[:Tmax] = Integer(value) end
    parser.on('--training-set=VAL') do |value| $options[:training_set] = value end
    parser.on('--quiet') do |value| $logger&.quiet end
    parser.parse!(ARGV)
    set_default_options
  end
  if $options[:integrity_check] then
    run_integrity_check
  elsif $options[:model] then
    throw 'specify -J or --Jmax' unless $options[:J] or $options[:Jmax]
    throw 'specify --Tmax' unless $options[:Tmax]
    report_processing_time("test syscalls") do
      if $options[:J] then
        run_Jgram($options[:J], $options[:Tmax])
      else
        $options[:Jmin].upto($options[:Jmax]) do |_J| run_Jgram(_J, $options[:Tmax]) end
      end
      save
    end
  end
rescue Exception
  $stdout_logger&.error(:exception, "#{$!.inspect}\n  #{$@.join("\n  ")}")
  unless $options[:shell] then
    save
    exit 1
  end
ensure
  start_hako_shell if $options[:shell]
end
