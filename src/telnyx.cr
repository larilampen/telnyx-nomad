# telnyx.cr: Webhooks for receiving SMS and calls via Telnyx. See the
# readme file for details.
#
# Lari Lampen, 2020
#
# MIT License

require "./notifier.cr"

require "kemal"
require "digest/md5"
require "http/client"
require "json"
require "log"


# These two channels are used to pass tasks to the secondary threads.
alias Action = NamedTuple(action: String, id: String, content: String)
alias DownloadTask = NamedTuple(url: String, filename: String)
action_queue = Channel(Action).new(3)
download_queue = Channel(DownloadTask).new(3)

config = Config.new("config.json")



# The configuration file contains the needed tokens and API keys, plus
# some other settings.
class Config
  getter pb_token : String? = nil
  getter pb_device : String? = nil
  getter tg_token : String? = nil
  getter tg_chat : Int32? = nil
  getter telnyx_apikey : String
  getter port : Int32

  def initialize(filename)
    @names = {} of String => String
    @urls = {} of String => String
    unless File.exists? filename
      abort "The configuration file is missing. Please read the setup instructions."
    end

    conf = JSON.parse(File.read(filename))
    if conf.as_h.has_key? "pushbullet"
      @pb_token = conf["pushbullet"]["token"].as_s?
      @pb_device = conf["pushbullet"]["device-id"].as_s?
    end
    if conf.as_h.has_key? "telegram"
      @tg_token = conf["telegram"]["token"].as_s?
      @tg_chat = conf["telegram"]["chat-id"].as_i?
    end
    @telnyx_apikey = conf["telnyx"]["apikey"].as_s
    default_url = conf["default-message"].as_s
    @port = conf["port"].as_i
    conf["numbers"].as_h.each do |number, details|
      @names[number] = if details.as_h.has_key?("name")
                         details["name"].as_s
                       else
                         number
                       end
      @urls[number] = if details.as_h.has_key?("message")
                        details["message"].as_s
                      else
                        default_url
                      end
    end
  end

  def name(number)
    @names[number]
  end

  def message_url(number)
    @urls[number]
  end
end


# Generate unique filename and save content there. Return the
# filename.
def save_file(dir, extension, content)
  Dir.mkdir(dir) unless Dir.exists?(dir)
  time = (Time.utc - Time::UNIX_EPOCH).to_i
  hash = Digest::MD5.hexdigest content
  filename = "#{dir}/#{time}-#{hash[0..5]}.#{extension}"
  File.write filename, content
  filename
end



# Sender thread: consumes messages from queue and sends requests to
# the Telnyx API.
spawn do
  loop do
    act = action_queue.receive
    url = "https://api.telnyx.com/v2/calls/#{act[:id]}/actions/#{act[:action]}"

    headers = HTTP::Headers.new
    headers.add "Authorization", "Bearer #{config.telnyx_apikey}"
    headers.add "Accept", "application/json"
    headers.add "Content-Type", "application/json"

    Log.info { "Sending action '#{act[:action]}', cid #{act[:id]}, content: #{act[:content]}" }
    res = HTTP::Client.post url, headers: headers, body: act[:content]
    unless res.success?
      Log.error { "Request failed with code #{res.status_code}: #{res.body}" }
    end
  end
end


# Downloader thread: downloads files (call recordings in mp3 format).
spawn do
  loop do
    item = download_queue.receive
    res = HTTP::Client.get item[:url]
    if res.success?
      File.write item[:filename], res.body
      Log.info { "Saved recording in #{item[:filename]}" }
    else
      Log.error { "Download failed: #{res.status_code}: #{res.body}" }
    end
  end
end


module Telnyx
  VERSION = "0.1.0"

  notifiers = [] of Notifier
  if (tok = config.pb_token) && (pbd = config.pb_device)
    notifiers << PushbulletNotifier.new(tok, pbd)
  end
  if (tok = config.tg_token) && (tgc = config.tg_chat)
    notifiers << TelegramNotifier.new(tok, tgc)
  end

  # Receiving SMS is simple: just store it and send a notification.
  post "/sms" do |env|
    req = env.request.body
    if req.nil?
      Log.warn { "Empty content received." }
      env.response.status_code = 400
      next
    end

    payload = req.gets_to_end
    filename = save_file "sms", "json", payload
    Log.info { "Saved message to file #{filename}" }

    data = JSON.parse(payload)["data"]["payload"]
    text = data["text"].as_s
    from = data["from"]["phone_number"].as_s
    to = config.name(data["to"].as_s)
    notifiers.each do |notifier|
      notifier.notify text, "Text message from #{from} to #{to}"
    end
  end

  # Processing a call is more complicated due to the many state
  # transitions needed.
  post "/call" do |env|
    req = env.request.body
    if req.nil?
      Log.warn { "Empty content received." }
      env.response.status_code = 400
      next
    end

    payload = req.gets_to_end
    data = JSON.parse(payload)["data"]

    event = data["event_type"].as_s
    outfilename = save_file "data", "#{event}.json", payload

    # Events that take place after the call ends do not come with a
    # control ID, so we check them first.
    if event == "call.hangup"
      Log.info { "Call finished." }
      next
    elsif event == "call.recording.saved"
      url = data["payload"]["recording_urls"]["mp3"].as_s
      Log.info { "Recording saved." }
      soundfile = outfilename.gsub(/json$/, "mp3")
      download_queue.send({url: url, filename: soundfile})
      notifiers.each do |notifier|
        notifier.notify "Recording saved as #{soundfile}, available at #{url}", "You missed a call!"
      end
      next
    end

    # At this point, a call is ongoing or starting, so there should be
    # a control ID available.
    id_control = data["payload"]["call_control_id"].as_s
    Log.info { "Received call event #{event} for cid #{id_control}" }

    case event
    when "call.initiated"
      Log.info { "Call incoming, trying to answer" }
      action_queue.send({id: id_control, action: "answer", content: ""})
    when "call.answered"
      Log.info { "Call started, trying to enable recording + start playback" }
      action_queue.send({id: id_control, action: "record_start",
                         content: "{\"format\": \"mp3\", \"channels\": \"single\"}"})
      target = data["payload"]["to"].as_s
      answer_url = config.message_url(target)
      action_queue.send({id: id_control, action: "playback_start",
                         content: "{\"audio_url\": \"#{answer_url}\"}"})
    when "call.playback.started"
      Log.info { "Playback started (doing nothing)" }
    when "call.playback.ended"
      Log.info { "Playback ended (doing nothing)" }
    else
      Log.warn { "Received unknown webhook: #{event} (doing nothing)" }
    end
  end
end

Kemal.config.port = config.port
Kemal.run
