#!/usr/bin/env ruby

# Soundlrous
#   Embed SoundCloud players on Tumblr and/or Posterous
#   I read the tumblr-api and postly ruby gems and took the parts I liked.
# Hannes Tydén, 2010-02-06
# hannes@tyden.name

# Copyright (c) 2010 Hannes Tydén
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

require 'rubygems'
require 'httparty'
require 'json'
require 'cgi'
require 'optparse'

# Taken from ActiveSupport 3.0.0 Beta, with some recurion sprinkled on top.
module HashSymbolizeKeys
  # Return a new hash with all keys converted to symbols, as long as
  # they respond to +to_sym+.
  def symbolize_keys
    dup.symbolize_keys!
  end

  # Destructively convert all keys to symbols, as long as they respond
  # to +to_sym+.
  def symbolize_keys!
    keys.each do |key|
      value = delete(key)
      value.symbolize_keys! if value.is_a?(Hash)
      self[(key.to_sym rescue key) || key] = value
    end
    self
  end
end

class Hash
  include HashSymbolizeKeys
end

module Soundlrous
  EMBED_CODE = <<EMBED_CODE
<object height="{size}" width="{size}">
  <param name="movie" value="http://player.soundcloud.com/player.swf?url={url}&amp;auto_play=false&amp;player_type={type}&amp;color{color}"></param>
  <param name="allowscriptaccess" value="always"></param>
  <embed
    allowscriptaccess="always" height="{size}"
    src="http://player.soundcloud.com/player.swf?url={url}&amp;auto_play=false&amp;player_type={type}&amp;color={color}"
    type="application/x-shockwave-flash" width="{size}"></embed>
</object>
EMBED_CODE
  
  DEFAULT_OPTIONS = {
    :title => "{soundcloud::full_title}",
    :body  => %Q(<p>{soundcloud::code}</p><p>Posted using <a href="http://github.com/hannestyden/soundlrous">Soundlrous</a></p>),
    :color => "ff6600",
    :size  => 425,
    :type  => 'artwork',
    :tags  => "soundcloud, soundlrous",
  }
  
  DEBUGMODE = false
  
  extend self
  
  def services
    (@services ||= {})
  end
  
  class Base
    def self.register_as(name)
      Soundlrous.services[name] = self
    end
    
    def initialize(email, password)
      @email    = email
      @password = password
    end
  
  private
  
    def process_for_soundcloud(params)
      data = get_soundcloud_data(params)
    
      params[:body]  = (params[:body] || "{soundcloud::code}").gsub(/\{soundcloud::code\}/, data[:code])
      params[:title] = (params[:title] || "{soundcloud::full_title}").gsub(/\{soundcloud::full_title\}/, data[:full_title])
    
      params
    end
  
    def get_soundcloud_data(options)
      response = HTTParty.get("http://api.soundcloud.com/resolve", {
        :headers => {
          "Accept" => 'application/json',
        },
        :query => {
          :url => options[:url],
        }
      })
    
      if response.is_a?(String)
        result = JSON.parse(response).symbolize_keys
    
        result[:code]       = embed_code(options)
        result[:full_title] = result[:title] || result[:name] || result[:username]
        result[:full_title] += " by #{result[:user][:username]}" if result[:user]
      end
    
      result
    end
  
    def embed_code(options)
      options.merge(:url => CGI.escape(options[:url])).inject(EMBED_CODE) do |memo, (key, value)|
        memo.gsub(%r{\{#{key}\}}, value.to_s)
      end
    end
    
    def post(endpoint, options)
      if DEBUGMODE
        puts endpoint
        puts
        p options
        "Running debug mode."
      else
        HTTParty.post(endpoint, options)
      end
    end
  end
  
  class Tumblr < Base
    register_as :tumblr
    
    def post(params)
      default_options = {
        :type => 'regular',
      }
    
      process_for_soundcloud(params)
    
      options = authentication.merge(default_options.merge(params))
      
      super('http://www.tumblr.com/api/write', :body => options)
    end
  
  private
    def authentication
      {
        :email    => @email,
        :password => @password,
      }
    end
  end

  class Posterous < Base
    register_as :posterous
    
    def post(params)
      process_for_soundcloud(params)
      
      options = authentication.merge(:body => params)
      
      super('http://posterous.com/api/newpost', options)
    end
  
  private
    def authentication
      {
        :basic_auth => {
          :username => @email,
          :password => @password,
        }
      }
    end
  end
end

begin
  config_path = File.expand_path("~/.soundlrous")
  
  options = {}
  opp = OptionParser.new do |opts|
    opts.banner = "Usage: #{__FILE__} [options] URL"

    opts.separator "URL - Permalink for embeddable object"
    opts.separator ""
    opts.separator "Specific options:"

    opts.on("-e", "--email EMAIL", "Email address for your account") do |email|
      options[:email] = email
    end
  
    opts.on("-p", "--password PASSWORD", "Password for your account") do |passw|
      options[:passw] = passw
    end
    
    opts.on("-s", "--service NAME", "Name of service. Tumblr or Posterous") do |service|
      options[:service] = service.downcase
    end
    
    opts.on("-c", "--color HEX", "Color in hexadecimal RGB") do |color|
      options[:color] = color
    end
  
    opts.on("-z", "--size PIXELS", Integer, "Size in pixels") do |size|
      options[:size] = size
    end
  
    opts.on("-y", "--type TYPE", "Type of player") do |type|
      options[:type] = type
    end
  
    opts.on("-t", "--title STRING", "Title for the post, may contain interpolated template strings.") do |title|
      options[:title] = title
    end
  
    opts.on("-b", "--body STRING", "Body for the post, may contain interpolated template strings.") do |body|
      options[:body] = body
    end
  
    opts.on("-w", "--write", "Write arguments to defaults") do |persist|
      options[:save] = true
    end
    
    opts.separator ""
    opts.separator "Common options:"
  
    opts.on_tail("-h", "--help", "Show this message") do
      raise OptionParser::MissingArgument
    end
  end
  opp.parse!(ARGV)
  
  if ARGV.length == 1
    url = ARGV.pop
    options[:url] = url if (URI.parse(url) rescue nil).is_a?(URI::HTTP)
  end
  
  config = Soundlrous::DEFAULT_OPTIONS
  
  # Merge persisted options with defaults
  if File.exists?(config_path)
    begin
      config.merge!(JSON.parse(File.read(config_path)).symbolize_keys)
    rescue
      puts "Unable to load configuration from #{config_path}."
    end
  end
  
  # Merge passed options with loaded
  options = config.merge!(options)
  
  # Required options, must be passed or saved in config
  [ :email, :passw, :url, :service ].each do |argument|
    if options[argument].nil?
      puts "Missing required argument: #{argument}"
      puts
      raise OptionParser::MissingArgument
    end
  end
  
  # If there are options to persits
  #   do so if no config persited
  #   or persistance is wanted
  if options.size > 0 && (!File.exists?(config_path) || options[:save])
    to_persist = Hash[*(options.select { |key, value| ![ :url, :save ].include?(key) }.flatten)]
    File.open(config_path, 'w') do |file|
      file << JSON.pretty_generate(to_persist)
    end
  end
  
  email   = options.delete(:email)
  passw   = options.delete(:passw)
  service = options.delete(:service)
  
  response = Soundlrous.services[service.to_sym].new(email, passw).post(options)
  
  puts "Posted to #{service}"
  puts "Response:"
  p response
rescue OptionParser::MissingArgument
  puts opp
end