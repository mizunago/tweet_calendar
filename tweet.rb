# frozen_string_literal: true

require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/calendar_v3'
require 'simple_twitter'
require 'pp'
require 'active_support'
require 'active_support/core_ext'
require 'sanitize'
require 'twitter-text'

class String
  def length_split(n = 0)
    return [self] if n.zero?
    split_num = (self.length / n) + 1
    array = Array.new
    split_num.times do |num|
      array << self[num * n, n]
    end
    return array
  end
end

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
scope = 'https://www.googleapis.com/auth/calendar'

authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open('secret.json'),
  scope: scope
)
config = YAML.load(File.open('twitter_secret.yml')).with_indifferent_access
client = SimpleTwitter::Client.new(
  api_key: config[:api_key],
  api_secret_key: config[:api_secret_key],
  access_token: config[:access_token],
  access_token_secret: config[:access_token_secret]
)
hash_tag = ' #SeaOfThieves #シーオブシーブス'
continue_text = "…(続"
tweet_limit = 280

authorizer.fetch_access_token!

service = Google::Apis::CalendarV3::CalendarService.new
service.authorization = authorizer

base_time = DateTime.now

calendar_id = 'ls7g7e2bnqmfdq846r5f59mbjo@group.calendar.google.com'
response = service.list_events(calendar_id,
                               max_results: 10,
                               single_events: true,
                               order_by: 'startTime',
                               time_min: base_time.rfc3339)
events = response.items.select do |item|
  # 本日開始のイベント
  (base_time..(base_time + 1.day)).cover?(item.start.date_time)
end

end_events = response.items.select do |item|
  # 明日終了のイベント
  ((base_time.to_date + 1.day)..(base_time.to_date + 2.day)).cover?(item.end.date_time) && !(base_time.to_date..(base_time.to_date + 1.day)).cover?(item.start.date_time)
  # ((base_time.to_date + 1.day)..(base_time.to_date + 2.day)).cover?(item.end.date_time)
end

end_events.each do |item|
  events.append(item)
end

def post(client, text, res)
  if res && res[:id]
    res = client.post('https://api.twitter.com/1.1/statuses/update.json', status: text, in_reply_to_status_id: res[:id])
  else
    res = client.post('https://api.twitter.com/1.1/statuses/update.json', status: text)
  end
  #puts text
  #puts "----------"
  res
end

events.each do |item|
  str = "名称：#{item.summary}
日時：#{item.start.date_time.strftime('%Y年%m月%d日%H:%M')}-#{item.end.date_time.strftime('%m月%d日%H:%M')} JST
概要：
#{item.description ? Sanitize.clean(item.description&.gsub('<br>', "\n")) : '記載なし'}
"
  valid_result = Twitter::TwitterText::Validation.parse_tweet(str + hash_tag)
  res = nil
  if valid_result[:valid]
    res = post(client, str + hash_tag, res)
  else
    part_num = valid_result[:weighted_length] / tweet_limit
    part_num.times do
      position = 0
      last_valid_text = ''
      loop do
        text = str[0..position]
        valid_result = Twitter::TwitterText::Validation.parse_tweet(text + continue_text + hash_tag)
        if valid_result[:valid]
          last_valid_text = text
        else
          res = post(client, last_valid_text + continue_text + hash_tag, res)
          str = str.dup.delete_prefix!(str[0..position - 1])
          break
        end
        position += 1
      end
    end
    res = post(client, str + hash_tag, res)
  end
  notice = '@SoTJPNDiscord こちらはSoT日本語Wikiのイベントカレンダーの自動ツイートです。詳細や全文はこちらを御覧ください https://sot.nagonago.tv/doku.php 返信頂いても回答不可 誤り等のご報告は @dictnago まで'
  post(client, notice, res)
end

