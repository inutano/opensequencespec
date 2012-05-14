# -*- coding: utf-8 -*-

require "yaml"

class QCprocess
  @@path = YAML.load_file("#{File.expand_path(File.dirname(__FILE__))}/config.yaml")["path"]

  def initialize(runid)
    @runid = runid
  end
  
  def get_fq(subid, expid)
    location = "ftp.ddbj.nig.ac.jp/ddbj_database/dra/fastq/#{subid.slice(0,6)}/#{subid}/#{expid}"
    log = @@path["log"] + "/lftp_#{@runid}_#{Time.now.strftime("%m%d%H%M%S")}.log"
    `lftp -c "open #{location} && mget -O #{@@path["data"]} #{@runid}* " >& #{log}`
  end
  
  def ftp_failed?
    log = Dir.glob(@@path["log"] + "/lftp_#{@runid}*.log").sort.last
    (log && open(log).read =~ /fail/)
  end

  def fastqc
    log = @@path["log"] + "/fastqc_#{@runid}_#{Time.now.strftime("%m%d%H%M%S")}.log"
    `/home/geadmin/UGER/bin/lx-amd64/qsub -N #{@runid} -o #{log} #{@@path["lib"]}/fastqc_fq.sh #{@runid}`
  end
end
