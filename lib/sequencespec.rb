# -*- coding: utf-8 -*-

require "parallel"
require "json"

require File.expand_path(File.dirname(__FILE__)) + "/sra_metadata_parser"

class SRAIDTable
  def initialize(data_dir, symbol)
    @accessions = File.join data_dir, "SRA_Accessions.tab"
    @sra_metadata = File.join data_dir, "sra_metadata"
    @symbol = symbol
    @table = load_table
  end
  attr_accessor :table
  
  def load_table
    idlist = exec_awk(target_columns).split("\n")
    idlist_array = Parallel.map(idlist, :in_processes => 4){|line| line.split("\t") }
    grouped_by_id = idlist_array.group_by{|line| line.first }
    grouped_by_id.each{|k,v| grouped_by_id[k] = v.flatten }
  end
  
  def target_columns
    # DEFINE COLUMN NUMBERS TO BE EXTRACTED FROM "SRA_Accessions.tab"
    # id, acc, received, alias, exp, smaple, project, bioproject, biosample
    [ 1, 2, 6, 10, 11, 12, 13, 18, 19 ]
  end
  
  def exec_awk(columns)
    prefix = { run: "RR", experiment: "RX", sample: "RS" }
    match = "$1 ~ /^.#{prefix[@symbol]}/ && $3 == \"live\" && $9 == \"public\""
    column_string = columns.map{|num| "$#{num}" }.join(' "\t" ')
    `awk -F '\t' '#{match} { print #{column_string} }' #{@accessions}`
  end
  
  def get_id_related_run
    # get live experiment/sample id, related to live run id
    col_num = { experiment: 4, sample: 5 }
    @run_table ||= load_table(:run)
    Parallel.map(@run_table.values){|props| props[col_num[@symbol]] }
  end
  
  def parse_metadata(id)
    p = case @symbol
        when :experiment
          SRAMetadataParser::Experiment.new(id, get_xml_path(id))
        when :sample
          SRAMetadataParser::Sample.new(id, get_xml_path(id))
        end
    field_define[@symbol].map{|f| p.send(f) }
  rescue NameError, Errno::ENOENT
    nil
  end
  
  def get_xml_path(id)
    subid = @table[id][1]
    fname = [subid, @symbol.to_s, "xml"].join(".")
    File.join @sra_metadata, subid.slice(0..5), subid, fname
  end
  
  def field_define
    { experiment:
        [ :alias, :library_strategy, :library_source, :library_selection,
          :library_layout, :platform, :instrrument_model ],
      sample:
        [ :alias, :taxon_id ] }
  end
  
  def get_metadata_hash
    metadatalist = Parallel.map(@table.keys, :in_processes => 4) do |id|
      metad = parse_metadata(id)
      [id] + metad if metad
    end
    grouped_by_id = metadatalist.compact.group_by{|array| array.first }
    grouped_by_id.each{|k,v| grouped_by_id[k] = v.flatten }
  end
end

if __FILE__ == $0
  data_dir = "/home/inutano/project/opensequencespec/data"
  # parse metadata for all experiment/sample
  exptable = SRAIDTable.new(data_dir, :experiment)
  exp_metadata_hash = exptable.get_metadata_hash
  
  sampletable = SRAIDTable.new(data_dir, :sample)
  sample_metadata_hash = sampletable.get_metadata_hash
  
  # merge all information to runid
  runtable = SRAIDTable.new(data_dir, :run).table.keys.first(50) # limit
  
  merged_table = Parallel.map(runtable) do |table|
    runid = table.shift
    expid = table[3]
    sampleid = table[4]
    [ runid,
      table,
      exp_metadata_hash[expid],
      sample_metadata_hash[sampleid] ].flatten
  end
  open("sequencespec.json","w"){|f| JSON.dump(merged_table, f) }
end