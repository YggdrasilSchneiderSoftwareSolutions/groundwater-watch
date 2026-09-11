require 'sinatra'
require 'sinatra/cross_origin'
require 'nokogiri'
require 'rufus-scheduler'
require 'pony'
require 'open-uri'

configure do
  set :allow_methods, [:get, :options]
  set :allow_credentials, true
  set :max_age, "1728000"
  set :expose_headers, ['Content-Type']
end

get '/' do
  "Hello, world!"
end

get '/api' do
  cross_origin
  "API response"
end