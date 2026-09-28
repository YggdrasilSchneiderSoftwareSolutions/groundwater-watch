require 'sinatra'
require 'sinatra/cross_origin'
require 'nokogiri'
require 'rufus-scheduler'
require 'pony'
require 'open-uri'
require_relative 'secrets'

register Sinatra::CrossOrigin

$latest_data = { groundwater_level: nil, timestamp: nil, status: "Keine Daten vorhanden" }

scheduler = Rufus::Scheduler.new

$alert_levels = []

configure do
  set :allow_origin, :any
  set :allow_methods, [:get, :options]
  set :expose_headers, ['Content-Type']
end

# Initiale Abfrage beim Start der Anwendung
scheduler.in '2s' do
  # Alert Levels lesen
  $alert_levels = read_alert_levels
  # 1. Element in $alert_levels finden, bei dem alert = false ist
  alert_level = $alert_levels.find { |level| !level['email_alert_sent'] }

  # Grundwasserstand lesen
  check_groundwater_level

  # Willkommens-E-Mail senden
  subject = "Grundwasser-Überwachungsdienst"
  body = <<~TEXT
    Hallo,

    das Grundwasser-Überwachungssystem wurde gestartet und die aktuellen Grundwasserdaten wurden abgerufen:

    Grundwasserstand: #{$latest_data[:groundwater_level]} m
    Zeitstempel: #{$latest_data[:timestamp]}
    Status: #{$latest_data[:status]}

    Der Service ruft nun regelmäßig die Daten ab und sendet Benachrichtigungen, wenn der Grundwasserstand unter eine bestimmte Marke fällt.
    Die nächste Marke beträgt #{alert_level['level']} m.

    Mit freundlichen Grüßen,
    Ihr Grundwasser-Überwachungsdienst
  TEXT
  send_email_notification(subject, body)
end

# Job: jede Stunde die Daten holen
scheduler.every '1h' do
  check_groundwater_level
end

def check_groundwater_level
  url = 'https://www.hnd.bayern.de/grundwasser/isar/st-andrae-612-25117/tabelle'

  begin
    doc = Nokogiri::HTML(URI.open(url))
    first_row = doc.css('tbody tr').at(0)
    return if first_row.nil?

    gw_value = first_row.css('td')[2].text.strip.gsub(',', '.').to_f
    gw_timestamp = first_row.css('td')[0].text.strip

    $latest_data[:groundwater_level] = gw_value
    $latest_data[:timestamp] = gw_timestamp
    $latest_data[:status] = "Daten erfolgreich aktualisiert"

    # Grundwasserstand prüfen
    # 1. Element in $alert_levels finden, bei dem alert = false ist
    alert_level = $alert_levels.find { |level| !level['email_alert_sent'] }
    if alert_level && gw_value >= alert_level['level']
      # Alert senden
      subject = "Alarm: Grundwasserstand unterhalb der Grenze"
      body = <<~TEXT
        Hallo,

        Der Grundwasserstand hat den Wert #{alert_level['level']} m erreicht.

        Aktueller Stand: #{$latest_data[:groundwater_level]} m
        Zeitstempel: #{$latest_data[:timestamp]}

        Bitte prüfen Sie die Situation und ergreifen Sie gegebenenfalls Maßnahmen.

        Mit freundlichen Grüßen,
        Ihr Grundwasser-Überwachungsdienst
      TEXT
      send_email_notification(subject, body)
      
      # Alert als gesendet markieren und speichern
      alert_level['email_alert_sent'] = true
      alert_level['timestamp'] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      write_alert_levels
    end
  rescue => e
    puts "Fehler beim Parsen: #{e.message}"
    $latest_data[:status] = "Fehler beim Parsen: #{e.message}"
  end 
end

def send_email_notification(subject, body)
  Pony.mail(
    :to => EMAIL_RECEPIENTS,
    :from => EMAIL_SENDER,
    :subject => subject,
    :body => body,
    headers: {
      'Content-Type' => 'text/plain; charset=UTF-8',
      'Content-Transfer-Encoding' => '8bit'
    },
    :via => :smtp,
    :via_options => {
      :address => 'smtp.gmail.com',
      :port => '587',
      :enable_starttls_auto => true,
      :user_name => EMAIL_SENDER,
      :password => EMAIL_PASSWORD, # app passwort von Google verwenden
      :authentication => :plain,
      :domain => 'localhost.localdomain'
    }
  )
end

def read_alert_levels
  JSON.load_file('./gw_level_alerts.json')
end

def write_alert_levels
  File.open('./gw_level_alerts.json', 'w') do |file|
    file.write(JSON.pretty_generate($alert_levels))
  end
end

get '/' do
  @daten = $latest_data
  erb :index
end

get '/api' do
  cross_origin
  $latest_data.to_json
end