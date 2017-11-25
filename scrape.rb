# Copyright (c) 2017 Yegor Bugayenko
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

def get(path)
  uri = URI.parse("http://repo1.maven.org/maven2/#{path}")
  req = Net::HTTP::Get.new(uri.to_s)
  res = Net::HTTP.start(uri.host, uri.port) do |http|
    http.request(req)
  end
  res.body
end

def scrape(path)
  body = get(path)
  if (body.include?('maven-metadata.xml'))
    match = body.match(%r{maven-metadata.xml</a>\s+(\d{4}-\d{2}-\d{2} )})
    date = Date.strptime(match[1], '%Y-%m-%d')
    meta = Nokogiri::XML(get("#{path}maven-metadata.xml"))
    version = meta.xpath('//versions/version[last()]/text()')
    puts "#{path} #{version} #{date}"
  else
    body.scan(%r{href="([a-zA-Z\-]+/)"}).each do |p|
      scrape("#{path}#{p[0]}")
    end
  end
end

scrape(ARGV[1])
