require 'benchmark'

class MemoryLogger
  attr_reader :stages, :loglines
  def initialize
    @stages = {}
    @stage_id = nil
    @loglines = []
  end
  def inspect
    "MemoryLogger<stages.length=#{stages.length}, loglines.length=#{loglines.length}>"
  end
  alias to_s inspect

  def error(tag, text)
    @loglines << [:error, tag, text]
  end
  def info(tag, text)
    @loglines << [:info, tag, text]
  end
  def log(tag, text)
    @loglines << [:log, tag, text]
  end
  def warn(tag, text)
    @loglines << [:warn, tag, text]
  end

  def set_stage_id(id)
    @stage_id = id
  end
  def set_stage_data(data)
    (@stages[@stage_id] ||= {}).merge!(data)
  end
end

class StandardLogger < MemoryLogger
  def initialize
    super
    clear_forbid_tag_patterns
  end
  def inspect
    "StandardLogger<nstages=#{stages.length}, forbid_tag_patterns=#{@forbid_tag_patterns.keys}>"
  end
  alias to_s inspect

  def error(tag, text)
    super
    STDERR.puts "\033[31m#{tag}: #{text}\033[0m"
  end
  def info(tag, text)
    return if @forbid_tag_patterns.find do |pattern, _| pattern.match(tag) end
    super
    STDERR.puts "\033[36m#{tag}: #{text}\033[0m"
  end
  def log(tag, text)
    return if @forbid_tag_patterns.find do |pattern, _| pattern.match(tag) end
    super
    STDERR.puts "#{tag}: #{text}"
  end
  def warn(tag, text)
    super
    STDERR.puts "\033[33m#{tag}: #{text}\033[0m"
  end

  def clear_forbid_tag_patterns
    @forbid_tag_patterns = {}
  end
  def set_forbid_tag_pattern(pattern)
    @forbid_tag_patterns[pattern] = true
  end
  def unset_forbid_tag_pattern(pattern)
    @forbid_tag_patterns.delete(pattern)
  end
  def quiet
    set_forbid_tag_pattern(/.*/)
  end
end

def report_processing_time(msg, logger=$logger, at_start: false, &callback)
  logger&.info(:report_processing_time, "#{msg}: starting ...") if at_start
  value = nil
  tm = Benchmark.measure do value = callback.call end
  logger&.info(:report_processing_time, "#{msg}: finished in user #{'%.5f' % [tm.utime + tm.cutime]}s, system #{'%.5f' % [tm.stime + tm.cstime]}s and real #{'%.5f' % [tm.real]}s")
  value
end
