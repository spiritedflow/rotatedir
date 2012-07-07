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

    # Symlink - skip
    if File.symlink?(path)
      Time.at(0)

    # Directory - recursively get max mtime
    elsif File.directory?(path)
      times = Dir.glob("#{path}/*", File::FNM_DOTMATCH).map do |entry|
        next nil if ['.', '..'].include?(File.basename(entry))
        calculate_last_modified(entry)
      end.compact
      times << File.mtime(path)
      times.max

    # File - own mtime
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

def parse_options
  opts = {
    :base => nil,
    :history_base => nil,
    :expire => 7,
    :verbose => false,
    :dry => false
  }

  OptionParser.new do |o|
    o.banner = <<ENDL
Description:
  This script should archive all obsolete files and directories
  to special 'history' directory and group them by date. So all
  history will be observable and searchable.

Usage: #{File.basename($0)} BASE [-h|--history-base DIR] [-e|--expire DAYS]}

Options:
ENDL

    o.on('-h', '--history-base', 'Directory to save history. Default: <BASE>/HISTORY') {|val| opts[:history_base] = val}
    o.on('-e N', '--expire N', 'How many days files will wait before being rotated') {|val| opts[:expire] = val.to_i}
    o.on('-v', '--verbose', 'Do verbose logging') {|val| opts[:verbose] = val}
    o.on('-d', '--dry', 'Do not actually archive files, only log') {|val| opts[:dry] = val}
  end.parse!

  opts[:base] = ARGV[0] or raise OptionParser::MissingArgument
  opts[:history_base ]||= "#{opts[:base]}/HISTORY"
  opts
end

# --------------------------------------------------
# Main
# --------------------------------------------------

# Parse options
opts = parse_options

$log = Logger.new(STDOUT)
$log.level = opts[:verbose] ? Logger::DEBUG : Logger::WARN

now = Date.parse(Time.now.to_s)

history = HistoryDir.new(opts[:history_base], :dry => opts[:dry])

# Walk through all entries
Dir.glob("#{opts[:base]}/*", File::FNM_DOTMATCH).each do |path|
  next if File.expand_path(path) == File.expand_path(opts[:history_base])
  next if ['.', '..'].include?(File.basename(path))

  entry = Entry.new(path)
  if entry.mdate + opts[:expire] < now
    history.archive(entry)
  else
    $log.debug("Skip #{entry.inspect}, it's too fresh")
  end
end