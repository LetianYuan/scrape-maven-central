#!/usr/bin/env ruby
# -*- coding:utf-8 -*-
# Copyright (c) 2017-2020 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

STDOUT.sync = true

require 'net/http'
require 'date'
require 'nokogiri'
require 'slop'

$result_file = nil

def get(path)
  puts path
  uri = URI.parse("https://repo1.maven.org/maven2/#{path}")
  req = Net::HTTP::Get.new(uri.to_s)
  finished = false
  res = nil
  until finished do
    begin
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(req)
      end
      finished = true
    rescue
      # Ignored
    end
  end
  if res.code != '200'
    ""
  else
    res.body
  end
end

def scrape(path, ignore = [], start = '')
  body = get(path)
  if body.include?('maven-metadata.xml')
    while true do
      match = body.match(%r{maven-metadata.xml</a>\s+(\d{4}-\d{2}-\d{2} )})
      date = Date.strptime(match[1], '%Y-%m-%d')
      meta = Nokogiri::XML(get("#{path}maven-metadata.xml"))
      group_id = meta.xpath('//groupId/text()')
      artifact_id = meta.xpath('//artifactId/text()')
      if group_id.empty? or artifact_id.empty?
        break
      end
      latest_version = meta.xpath('//versions/version[last()]/text()')
      $result_file.puts("\"#{path}\",\"#{latest_version}\",\"#{date}\",\"#{group_id}:#{artifact_id}:#{latest_version}\"")
      # versions = meta.xpath('//versions/version').each do |version|
      #   puts "\"#{path}\",\"#{latestVersion}\",\"#{date}\",\"#{groupId}:#{artifactId}:#{version.content}\""
      # end
      return
    end
  end
  found = false
  body.scan(%r{href="([a-zA-Z\-]+/)"}).each do |p|
    target = "#{path}#{p[0]}"
    found = true if target.start_with?(start)
    next unless found
    next unless ignore.select { |i| target.start_with?(i) }.empty?
    scrape(target, ignore)
  end
end

begin
  opts = Slop.parse(ARGV, strict: true, help: true) do |o|
    o.banner = "Usage: ruby scrape.rb [options]"
    o.bool '-h', '--help', 'Show these instructions'
    o.string '-r', '--root', 'Root path to start from', default: ''
    o.array '-i', '--ignore', 'Prefixes to ignore, like "org/", for example'
    o.string '-s', '--start', 'Start from this path', default: ''
    o.string '-o', '--output', 'Specify output to a .csv file', default: 'result.csv'
  end
rescue Slop::Error => ex
  raise StandardError, "#{ex.message}, try --help"
end

if opts.help?
  puts opts
  exit
end

$result_file = File.new(opts[:output], "w+")
$result_file.puts("path,latestVersion,date,artifactAddress")
begin
  scrape(opts[:root], opts[:ignore], opts[:start])
  $result_file.close
rescue Interrupt
  $result_file.close
end

