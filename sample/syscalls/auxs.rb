def get_abnormal_databases(_J)
  models = $models[_J]
  df = DataFrame.from_a([], colnames: ['dbindex', 'weight'] + models.length.times.map do |m| "score#{m}" end  + _J.times.map do |j| "V#{j}" end)
  $test_abnormal_dbs[_J].each.with_index do |db, i|
    db.each do |row, weight|
      df << [i, weight] + models.each.collect do |m| m.classifier.calculate_score(row) end + db.decode(row, to_sym: true).reverse!
    end
  end
  df
end
def get_database_traces(per_trace=false, path_pattern: /.*/)
  df = DataFrame.from_a([], colnames: ['path', 'ntraces', 'trace_length'])
  counts = {}
  $syscalldb.each do |path, file|
    next unless path.match(path_pattern)
    count = counts[path] = {:ntraces => 0, :trace_length => 0} unless per_trace
    file.each do |name, trace|
      count = counts[File.join(path, name)] = {:ntraces => 0, :trace_length => 0} if per_trace
      count[:ntraces] += 1
      count[:trace_length] += trace.length
    end
  end
  counts.each do |path, count|
    df << [path, count[:ntraces], count[:trace_length]]
  end
  df
end
def get_Jgram_database(_J=1, path_pattern: /.*/)
  df = DataFrame.from_a([], colnames: ['path', 'weight'] + 1.upto(_J).collect do |j| "V#{j}" end)
  counts_set = {}
  $syscalldb.each do |path, file|
    next unless path.match(path_pattern)
    counts = counts_set[path] = {}
    file.each_Jgram(_J) do |x, weight|
      counts[x] = (counts[x] || 0) + weight
    end
  end
  counts_set.each do |path, counts|
    counts.each do |x, count|
      df << [path, count] + $syscalldb[path].decode(x, to_sym: true).reverse!
    end
  end
  df
end
def get_unigram_database(path_pattern: /.*/)
	counts_set = {}
	names = {}
  $syscalldb.each do |path, file|
    next unless path.match(path_pattern)
    counts = counts_set[path] = {}
    file.each_Jgram(1) do |x, weight|
      x_decoded = file.decode(x, to_sym: true)[0]
      counts[x_decoded] = (counts[x_decoded] || 0) + weight
      names[x_decoded] ||= true
    end
  end
  names = names.keys.sort
  df = DataFrame.from_a([], colnames: ['path'] + names)
  names_inverse = {}
  names.each.with_index do |name, i| names_inverse[name] = i + 1 end
  counts_set.each do |path, counts|
    row = Array.new(df.ncols, 0)
    row[0] = path
    counts.each do |name, weight|
      row[names_inverse[name]] = weight
    end
    df << row
  end
  df
end

def get_score_deltas(_J)
  models = $models[_J]
  comps_set = models.collect do |model| model.classifier.score_deltas end
  df = DataFrame.from_a([], colnames: ['m', 'name', 'score', 'delta'])
  comps_set.each.with_index do |comps, m|
    comps[:scores].each do |k, score|
      df << [m, models[0].db.alphamap[k], score, comps[:deltas][k]]
    end
  end
  df
end
def get_logistic_partial_dependence_components(_J)
  models = $models[_J]
  comps_set = models.collect do |model| model.classifier.partial_dependence_components end
  df = DataFrame.from_a([], colnames: ['m', 'name', 'intercept', 'slope'])
  comps_set.each.with_index do |comps, m|
    comps[:intercepts].each do |k, intercept|
      df << [m, models[m].db.alphamap[k], intercept, comps[:slopes][k]]
    end
  end
  df
end

def fit_models(_J, ms=nil, with_train: true, with_test_normal: true, with_test_abnormals: true)
  train_db = $train_dbs[_J]
  test_normal_db = $test_normal_dbs[_J]
  test_abnormal_dbs = $test_abnormal_dbs[_J]
  models = $models[_J]
  ms = (0..(models.length - 1)).to_a
  ms = [ms] unless ms.is_a? Array
  classifiers = ms.collect do |m| models[m].classifier end
  db = models[0].db
  alphamap_inverse = db.alphamap.to_a + [:__UNKNOWN__]
  counts = {}
  colnames = ms.collect do |m| "score#{m}" end
  colnames << 'train_weight' if with_train
  colnames << 'test_normal_weight' if with_test_normal
  colnames << 'test_abnormals_weight' if with_test_abnormals
  colnames += 1.upto(_J).collect do |j| "V#{j}" end
  df = DataFrame.from_a([], colnames: colnames)
  start = Time.now
  collect_rows_from_database = lambda do |db, type|
    db.each do |x, weight|
      count = counts[x] ||= {
        :count => {},
        :score => classifiers.collect do |classifier| classifier.calculate_score(x) end,
      }
      count[:count][type] = (count[:count][type] || 0) + weight
    end
  end
  collect_rows_from_database.call(train_db, :train) if train_db and with_train
  collect_rows_from_database.call(test_normal_db, :test_normal) if test_normal_db and with_test_normal
  test_abnormal_dbs.each do |test_abnormal_db|
    collect_rows_from_database.call(test_abnormal_db, :test_abnormal)
  end if test_abnormal_dbs and with_test_abnormals
  counts.each do |x, count|
    row = count[:score].clone
    row << (count[:count][:train] || 0) if with_train
    row << (count[:count][:test_normal] || 0) if with_test_normal
    row << (count[:count][:test_abnormal] || 0) if with_test_abnormals
    df << row + db.decode(x, to_sym: true).reverse!
  end
  df
end

def convert_to_count_data_frame(df, start: 0)
  alphamap = {}
  df.each do |rowid, row|
    row[(start + 1)..-1].each do |name| alphamap[name] ||= alphamap.size end
  end
  alphamap[:__UNKNOWN__] = alphamap.size
  colnames = []
  colnames[0..(start - 1)] = df.colnames[0..(start - 1)]
  colnames[start] = 'target'
  alphamap.each do |name, id| colnames[start + 1 + id] = name end
  df_count = DataFrame.from_a([], colnames: colnames)
  df.each do |row|
    row_count = Array.new(df_count.ncols, 0)
    row_count[0..(start - 1)] = row[0..(start - 1)]
    row_count[start] = row[start]
    row[(start + 1)..-1].each do |name| row_count[start + 1 + alphamap[name]] += 1 end
    df_count << row_count
  end
  df_count
end

def dump_all_models(_J)
  models = $models[_J]
  dump_object(File.join($output_path, "#{$options[:experiment_name]}-J#{_J}-Tmax#{$options[:Tmax]}-#{models[0].parameter_string}.bin.gz"), models)
end

def report_model(_J, m, inspect_detail: true, ndigits: -1)
  model = $models[_J][m]
  classifier = model.classifier
  prefix = "#{$options[:experiment_name]}-J#{_J}-Tmax#{$options[:Tmax]}-m#{m}-#{model.parameter_string}"
  write_to_file('fitting results', "#{prefix}-fitting_results.csv", fit_models(_J, m).to_csv)
  write_to_file('inspect_detail', "#{prefix}-inspect_detail.txt", classifier.inspect_detail(ndigits: ndigits)) if inspect_detail
  return model
end

def report_all_models(_J, force_all: false, ndigits: -1)
  models = $models[_J]
  case models[0]
  when LogisticLearner then
    dfs = models.collect do |model| model.classifier.coefficients end
    resultdf = DataFrame.from_a([], colnames: dfs[0].colnames + ['m'])
    dfs.each.with_index do |df, m|
      df.each do |row|
        resultdf << row[:*] + [m]
      end
    end
    prefix = "#{$options[:experiment_name]}-J#{_J}-Tmax#{$options[:Tmax]}-#{models[0].parameter_string}"
    write_to_file('inspect_details', "#{prefix}-inspect_details.csv", resultdf.to_csv)
    write_to_file('score deltas', "#{prefix}-score_deltas.csv", get_score_deltas(_J).to_csv)
    write_to_file('partial dependence', "#{prefix}-partial_dependence.csv", get_logistic_partial_dependence_components(_J).to_csv)
    write_to_file('fitting results', "#{prefix}-fitting_results.csv", fit_models(_J).to_csv)
    prefix = "#{$options[:experiment_name]}-J#{_J}-Tmax#{$options[:Tmax]}-m0-#{models[0].parameter_string}"
    write_to_file('dendrogram', "#{prefix}-dendrogram.json", JSON::dump(models[0].clustering.dendrogram))
    write_to_file('dendrogram', "#{prefix}-dissimilarity_matrix.csv", models[0].clustering.dissimilarity_data_frame.to_csv)
    return
  end unless force_all
  return models.each.with_index do |model, m| report_model(_J, m, ndigits: ndigits) end
end
