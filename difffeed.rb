#!/usr/bin/ruby
# DiffFeed
# ========
#
# Makes a feed (currently RSS 2.0) of the new and deleted files in a path.
#
# by Sunny Ripert - sunfox.org
#
# Usage
# -----
#
# In a daily cron, for example:
#
#     $ ruby difffeed.rb path [configfile] > changes.rss
#
# Note that it needs (or creates) a configuration file to store
# the list of files between each call.

%w{ rubygems find yaml active_support }.each { |lib| require lib }

IGNORE = /^(\.|cvs|.svn|trash)/i

module Find
  # Returns array with the path to all files in a given directory
  def self.files_array(from_dir, ignore = nil)
    raise ArgumentError, "Argument must be a directory" unless File.directory?(from_dir)
    files = []
    Find.find(from_dir) do |path|
      fname = path.sub(from_dir, '')
      fdir, base = File.split(fname)
      if base =~ ignore
        Find.prune
      elsif File.file?(path)
        files.push fname
      end
    end
    files
  end
end

# DiffFeed class, stores its list of DiffFeedItems and of filenames
class DiffFeed
  attr_accessor :items, :files

  def initialize
    @items = []
    @files = []
  end

  # Add an item and pulls out another in case it overflows
  def push(item)
    @items.push item
    @items.shift if @items.size > MAX_FEED_ITEMS
  end

  # Adds a new DiffFeedItem with the latest changes
  # returns true if there was a change
  def update(path)
    new_files = Find.files_array(path, IGNORE)
    added = new_files - @files
    removed = files - new_files
    return false if added.empty? and removed.empty?
    push DiffFeedItem.new(Time.now, added, removed)
    @files = new_files
    true
  end


  # Save as yml
  def save(filename)
    File.open(filename, "w") { |file| file.puts(self.to_yaml) }
  end

  # Load as yml or blank slate
  def self.load(filename)
    YAML.load_file(filename) rescue DiffFeed.new
  end

  # Loads, updates and saves a DiffFeed
  def self.update(filename, path)
    d = DiffFeed.load(filename)
    d.save(filename) if d.update(path)
    d
  end

  def last_update
    @items.empty? ? Time.now : @items.first.time
  end

  # XML RSS 2.0 representation
  def to_s
    <<RSS
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>#{FEED_TITLE}</title>
    <link>#{FEED_LINK}</link>
    <description>#{FEED_TITLE}</description>
    <pubDate>#{last_update.httpdate}</pubDate>
    <generator>DiffFeed/1.0</generator>
    <language>fr</language>

#{@items.reverse.join}
  </channel>
</rss>
RSS
  end

end

# Item in a feed, contains arrays of added and removed files
class DiffFeedItem
  attr_accessor :time, :added, :removed

  def initialize(time, added, removed)
    @time, @added, @removed = time, added, removed
  end

  # Array of all sorted files, with a "+" or "-" before their name
  def formatted_files
    @added.sort.collect { |f| "+ #{f}" } + @removed.sort.collect { |f| "- #{f}" }
  end

  # Short (40 characters) string describing changes, serves as a title
  def summary
    summary = formatted_files.join(" ")
    summary = summary[0..40-3].strip + "..." if summary.size > 40
    summary
  end

  # XML RSS 2.0 representation
  def to_s
    <<ITEM
    <item>
      <title>#{summary}</title>
      <link>#{FEED_LINK}</link>
      <pubDate>#{@time.httpdate}</pubDate>
      <guid isPermaLink="false">#{FEED_LINK}##{@time.to_i}</guid>
      <description><![CDATA[#{formatted_files.join("<br/>\n")}]]></description>
    </item>
ITEM
  end
end


if __FILE__ == $0
  abort "Usage: #{$0} path [config.yml [http://base-uri/ [title [max-items]]]]" if ARGV.size == 0
  path = ARGV[0]
  filename = ARGV[1] || "difffeed.yml"
  FEED_LINK = ARGV[2] || "http://diffeed.example.com/"
  FEED_TITLE = ARGV[3] || "Directory changes"
  MAX_FEED_ITEMS = ARGV[4] || 30
  puts DiffFeed.update(filename, path)
end
