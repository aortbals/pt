#!/usr/bin/env ruby

require 'json'
require 'time'
require 'open-uri'
require 'pry'
require 'net/https'
require 'logger'

BASE_URI   = 'https://www.pivotaltracker.com/services/v5'
TOKEN      = ''
PROJECT_ID = ''
LOG_LEVEL  = Logger::DEBUG

ENDPOINTS = {
  projects:    "#{BASE_URI}/projects",
  stories:     "#{BASE_URI}/projects/#{PROJECT_ID}/stories",
  memberships: "#{BASE_URI}/projects/#{PROJECT_ID}/memberships",
}

class String
  def black;          "\033[30m#{self}\033[0m" end
  def red;            "\033[31m#{self}\033[0m" end
  def green;          "\033[32m#{self}\033[0m" end
  def yellow;         "\033[33m#{self}\033[0m" end
  def brown;          "\033[33m#{self}\033[0m" end
  def blue;           "\033[34m#{self}\033[0m" end
  def magenta;        "\033[35m#{self}\033[0m" end
  def cyan;           "\033[36m#{self}\033[0m" end
  def gray;           "\033[37m#{self}\033[0m" end
  def bg_black;       "\033[40m#{self}\0330m"  end
  def bg_red;         "\033[41m#{self}\033[0m" end
  def bg_green;       "\033[42m#{self}\033[0m" end
  def bg_brown;       "\033[43m#{self}\033[0m" end
  def bg_blue;        "\033[44m#{self}\033[0m" end
  def bg_magenta;     "\033[45m#{self}\033[0m" end
  def bg_cyan;        "\033[46m#{self}\033[0m" end
  def bg_gray;        "\033[47m#{self}\033[0m" end
  def bold;           "\033[1m#{self}\033[22m" end
  def reverse_color;  "\033[7m#{self}\033[27m" end
end

module Requests
  protected

  def make_request(endpoint, params = {})
    query_string = URI.encode_www_form(params)
    url = "#{endpoint}?#{query_string}"
    Tracker.logger.debug "Requesting: #{url}".red
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    request = Net::HTTP::Get.new(uri.request_uri)
    request['X-TrackerToken'] = TOKEN
    response = http.request(request)
    JSON.parse response.body
  end
end

module Stories
  class Base
    include Requests

    attr_reader :story
    def initialize(story, user=nil)
      @story = story
    end

    def to_stdout
      out =  "* #{id} - #{current_state} #{story_type} #{name}"
      out += " (#{accepted_at})".green if accepted_at
      out += " <#{username}>".blue if username
      out
    end

    private

    def id
      story['id'].to_s.yellow
    end

    def name
      story['name'].to_s
    end

    def story_type
      if story['estimate']
        "[#{story['story_type']}:#{story['estimate']}]"
      else
        "[#{story['story_type']}]"
      end
    end

    def current_state
      "[#{story['current_state']}]".send current_state_color
    end

    def accepted_at
      story['accepted_at'] ? DateTime.parse(story['accepted_at']).strftime("%m/%d/%Y") : nil
    end

    def username
      user = User.find_by_id(story["owner_ids"].first)
      return user.username if user
    end

    def current_state_color
      case story['current_state']
      when 'accepted'  then :green
      when 'finished'  then :blue
      when 'started'   then :yellow
      when 'unstarted' then :magenta
      when 'rejected'  then :red
      else :gray
      end
    end
  end

  class Bug < Base
    def story_type
      super.red
    end
  end

  class Feature < Base
    def story_type
      super.green
    end
  end

  class Chore < Base
    def story_type
      super.magenta
    end
  end

  class Release < Base
    def to_stdout
      "\n### Release #{accepted_at}: #{name} ###\n".blue
    end
  end
end

class User
  extend Requests

  def self.users
    @users ||= begin
      results = make_request ENDPOINTS[:memberships]
      results.map do |user|
        new(user)
      end
    end
  end

  def self.find_by_id(id)
    users.select { |user| user.id == id }.first
  end

  attr_reader :user
  def initialize(user)
    @user = user["person"]
  end

  def id
    user['id']
  end

  def username
    user['username']
  end
end

class Tracker
  include Requests

  def self.logger
    @logger ||= begin
      @logger = Logger.new(STDOUT)
      @logger.level = LOG_LEVEL
      @logger
    end
  end

  def stories(options = {})
    results = make_request ENDPOINTS[:stories], options
    results.map do |story|
      story_class(story).new(story)
    end
  end

  private

  def story_class(story)
    case story['story_type']
    when 'release' then Stories::Release
    when 'feature' then Stories::Feature
    when 'bug'     then Stories::Bug
    when 'chore'   then Stories::Chore
    else Stories::Base
    end
  end
end

def days_ago(days)
  (Time.now - days * 86400).utc.iso8601
end

def colorize(str, color)
  "\e[#{COLOR_CODES[color]}m#{str}\e[0m"
end

tracker = Tracker.new
stories = tracker.stories({ updated_after: days_ago(14) } )
puts stories.map(&:to_stdout)

# puts stories({ filter: "-state:unscheduled accepted_after:#{days_ago(14)} updated_since:#{days_ago(14)}" })
