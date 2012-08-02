require 'rubygems'
require 'uri'
require 'sinatra'
require 'json'
require 'rest_client'
require 'data_mapper'
require 'active_support'
require 'twitter'
require 'nokogiri'

class User
  include DataMapper::Resource
  property :id, Serial 
  property :readmill_id, Integer
  property :name, String
  property :access_token, String
  property :twitter_handle, String  
end

class Message
  include DataMapper::Resource
  property :id, Serial 
  property :last_id, String, :default => 1
end

DataMapper.finalize
DataMapper::Logger.new($stdout, :debug)

configure do
  DataMapper.setup(:default, (ENV["DATABASE_URL"] || {
    :adapter  => 'mysql',
    :host     => 'localhost',
    :username => 'root' ,
    :password => '',
    :database => 'tweetmill'}))
  DataMapper.auto_upgrade!  
end

Twitter.configure do |config|
  config.consumer_key = "F6fdEc2IEDr8ysrOXeXwA"
  config.consumer_secret = "c6WNSEgqndgoOW8RW9oP7jtgEjpWwflnQJMvdzYso"
  config.oauth_token = "541793455-CoteuIjFNcz6qSy7wwgswSrX1d2ooSDBJTDJfS1N"
  config.oauth_token_secret = "Gm1Zb46QFQ3nV8qeRt7L5mtsKOAbxG81eWyyqj8mT4"
end

set :readmill_client_id, "3157dd6728aacd2cf93e3588893e9848"
set :readmill_client_secret, "d2ddd931b979fcc461e677497f22bafc"
set :readmill_redirect, "http://tweetmill.heroku.com/callback/readmill"

def fetch_and_parse(uri, token = nil, limit = nil)
  puts "Fetching and parsing: #{uri} with token #{session[:token]}"
  limit = "&count=#{limit}" if limit
  url = "#{uri}?client_id=#{settings.readmill_client_id}#{limit}"
  url = "#{url}&access_token=#{token}" if token
  content = RestClient.get(url, :accept => :json).to_str
  puts "  Got Content: #{content}"
  JSON.parse(content) rescue nil
end

get '/auth/readmill' do
  redirect "http://readmill.com/oauth/authorize?response_type=code&client_id=#{settings.readmill_client_id}&redirect_uri=#{settings.readmill_redirect}&scope=non-expiring"
end

get '/callback/readmill' do
  token_params = {
    :grant_type => 'authorization_code',
    :client_id => settings.readmill_client_id,
    :client_secret => settings.readmill_client_secret,
    :redirect_uri => settings.readmill_redirect,
    :code => params[:code],
    :scope => 'non-expiring'
  }
  resp = JSON.parse(RestClient.post("http://readmill.com/oauth/token.json", token_params).to_str) rescue nil
  
  data = {
    :user => fetch_and_parse("http://api.readmill.com/me.json", resp['access_token'])
  }
  
  user = User.first_or_create({ :readmill_id => data[:user]['id'] })
  user.name = data[:user]['username']
  user.access_token = resp['access_token']
  @access_token = resp['access_token']
  user.save!
  
  erb :twitter  
end

### -- TEMPLATES -- ###

get '/' do
  erb :index
end

post '/done' do
  user = User.first({:access_token => params[:access_token]})
  if user
    user.twitter_handle = params[:twitter_handle].downcase
    user.save
    Twitter.follow(user.twitter_handle)
    Twitter.update("@#{user.twitter_handle} Welcome to Tweetmill. Follow me and I will DM you otherwise @reply. Sometimes I take a few minutes to reply, sit tight.")
    
    redirect "/thanks"
  else
    redirect "/?error=no such user"
  end
end

get '/thanks' do
  erb :thanks
end

get('/static/:filename') { send_file("./static/#{params[:filename]}") }
