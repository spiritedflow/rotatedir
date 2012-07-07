#!/usr/bin/env ruby

require 'optparse'
require 'logger'
require 'date'
require 'fileutils'

# --------------------------------------------------
# Entry. is created for each file or dir in 'base'
# --------------------------------------------------
class Entry
  attr_reader :path
  def initialize(path)
    @path = path
  end

  def mdate
    @mdate ||= Date.parse(calculate_last_modified(@path).to_s)
  end

  def inspect
    "<Entry mdate=[#{mdate}] path=[#{@path}]>"
  end

  private

  def calculate_last_modified(path)
    if File.directory?(path)
      times = Dir["#{path}/*"].map do |entry|
        calculate_last_modified(entry)
      end
      times.max || File.mtime(path)
    else
      File.mtime(path)
    end
  end
  rescue Exception
    e.error("Failed to calculate mtime for #{@path}: $!")
    Time.now()
end

# --------------------------------------------------
# History base dir
# --------------------------------------------------
class HistoryDir
  def initialize(path, options={})
    @base_dir = path
    @dry = options[:dry]

    ensure_exists(@base_dir)
  end

  def archive(entry)
    $log.info "Archive #{entry.inspect} to #{entry.mdate.to_s}"

    target = "#{@base_dir}/#{entry.mdate.to_s}"
    ensure_exists(target)

    FileUtils.mv(entry.path, target) unless @dry
  end

  def ensure_exists(path)
    return if File.directory?(path)
    $log.info("Create directory missing #{path}")
    Dir.mkdir(path) unless @dry
  end
end

# --------------------------------------------------
# Main
# --------------------------------------------------

# Parse options
history_base = nil
expire = 7
verbose = false
dry = false

OptionParser.new do |opts|
  opts.banner = <<ENDL
Description:
  This script should archive all obsolete files and directories
  to special 'history' directory and group them by date. So all
  history will be observable and searchable.

Usage: #{File.basename($0)} BASE [-h|--history-base DIR] [-e|--expire DAYS]}

Options:
ENDL

  opts.on('-h', '--history-base', 'Directory to save history. Default: BASE/history') {|val| history_base = val}
  opts.on('-e N', '--expire N', 'How many days files will wait before being rotated') {|val| expire = val.to_i}
  opts.on('-v', '--verbose', 'Do verbose logging') {|val| verbose = val}
  opts.on('-d', '--dry', 'Do not actually archive files, only log') {|val| dry = val}
end.parse!

$log = Logger.new(STDOUT)
$log.level = verbose ? Logger::DEBUG : Logger::WARN

now = Date.parse(Time.now.to_s)

base = ARGV[0] or raise OptionParser::MissingArgument
history_base ||= "#{base}/history"
history = HistoryDir.new(history_base, :dry => dry)

# Walk through all entries
Dir["#{base}/*"].each do |path|
  next if File.expand_path(path) == File.expand_path(history_base)
  entry = Entry.new(path)
  if entry.mdate + expire < now
    history.archive(entry)
  else
    $log.debug("Skip #{entry.inspect}, it's too fresh")
  end
end