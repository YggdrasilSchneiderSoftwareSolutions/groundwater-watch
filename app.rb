require 'sinatra'
require 'sinatra/cross_origin'
require 'nokogiri'
require 'rufus-scheduler'
require 'pony'
require 'open-uri'

register Sinatra::CrossOrigin

$latest_data = { groundwater_level: nil, timestamp: nil, status: "Keine Daten vorhanden" }

scheduler = Rufus::Scheduler.new

configure do
  set :allow_origin, :any
  set :allow_methods, [:get, :options]
  #set :allow_credentials, true
  #set :max_age, "1728000"
  set :expose_headers, ['Content-Type']
end

scheduler.in '2s' do
  check_groundwater_level
end

def check_groundwater_level
  url = 'https://www.hnd.bayern.de/grundwasser/isar/st-andrae-612-25117/tabelle'

  begin
    doc = Nokogiri::HTML(URI.open(url))
    first_row = doc.css('tbody tr').at(0)
    return if first_row.nil?

    gw_value = first_row.css('td')[2].text.strip
    gw_timestamp = first_row.css('td')[0].text.strip

    $latest_data[:groundwater_level] = gw_value
    $latest_data[:timestamp] = gw_timestamp
    $latest_data[:status] = "Daten erfolgreich aktualisiert"
  rescue => e
    puts "Fehler beim Parsen: #{e.message}"
    $latest_data[:status] = "Fehler beim Parsen: #{e.message}"
  end
  
end

get '/' do
  "Hello, world!"
end

get '/api' do
  cross_origin
  $latest_data.to_json
end