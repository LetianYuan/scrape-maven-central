#!/usr/bin/env ruby
# -*- coding:utf-8 -*-
# 不要删去上面这行注释
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
  # 国内访问maven仓库的网络连接不稳定，这里的循环是为了防止网络突然断开
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
  # 这里是处理maven仓库中第一种目录结构不自洽的情况，即超链接存在但是点进去404的情况
  # 例：https://repo1.maven.org/maven2/co/privacyone/ 下的 cerberus/
  if res.code != '200'
    ""
  else
    res.body
  end
end

def scrape(path, ignore = [], start = '')
  body = get(path)
  # 如果目录中存在jar包，那么直接访问maven-metadata.xml来得到artifact地址
  if body.include?('maven-metadata.xml')
    while true do
      match = body.match(%r{maven-metadata.xml</a>\s+(\d{4}-\d{2}-\d{2} )})
      date = Date.strptime(match[1], '%Y-%m-%d')
      meta = Nokogiri::XML(get("#{path}maven-metadata.xml"))
      group_id = meta.xpath('//groupId/text()')
      artifact_id = meta.xpath('//artifactId/text()')
      # 这里是处理maven仓库中第二种目录结构不自洽的情况，即jar包不存在的目录也会存在一个maven-metadata.xml
      # 例：https://repo1.maven.org/maven2/org/apache/
      if group_id.empty? or artifact_id.empty?
        break
      end
      latest_version = meta.xpath('//versions/version[last()]/text()')
      $result_file.puts("\"#{path}\",\"#{latest_version}\",\"#{date}\",\"#{group_id}:#{artifact_id}:#{latest_version}\"")
      # 如果要输出一个artifact的全部版本，使用下面的代码即可
      # versions = meta.xpath('//versions/version').each do |version|
      #   $result_file.puts("\"#{path}\",\"#{latest_version}\",\"#{date}\",\"#{group_id}:#{artifact_id}:#{version.content}\"")
      # end
      return
    end
  end
  # 否则（目录中不存在jar包），访问每个超链接
  found = false
  body.scan(%r{href="([a-zA-Z\-]+/)"}).each do |p|
    target = "#{path}#{p[0]}"
    found = true if target.start_with?(start)
    next unless found
    next unless ignore.select { |i| target.start_with?(i) }.empty?
    scrape(target, ignore)
  end
end

# 处理命令行指令
# -h 帮助
# -r 指定从哪个根目录开始爬取
# -i 忽略指定目录
# -s 指定从哪个目录开始爬取（前作者这个的实现有问题，不要使用，保持默认值即可）
# -o 指定输出的csv文件名
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

