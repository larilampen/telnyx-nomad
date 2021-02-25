require "http/client"

# Pushbullet and Telegram implementations of a simple notifier. See
# README.md for more details.

class Notifier
  def initialize
    @headers = HTTP::Headers.new
    @headers.add("Content-Type", "application/json;charset=utf-8")
  end

  private def post(data)
    HTTP::Client.post @url, headers: @headers, body: data.to_json
  end

  def notify(text, title = "Notification")
  end
end


class PushbulletNotifier < Notifier
  def initialize(token, @device_id : String)
    super()
    @headers.add("Access-Token", token)
    @url = "https://api.pushbullet.com/v2/pushes"
  end

  def notify(text, title = "Notification")
    data = {
      type: "note",
      title: title,
      device_iden: @device_id,
      body: text
    }
    post data
  end
end


class TelegramNotifier < Notifier
  def initialize(token : String, @chat_id : Int32)
    super()
    @url = "https://api.telegram.org/bot#{token}/sendMessage"
  end

  def notify(text, title = nil)
    if title
      title = "*#{title}*: "
    else
      title = ""
    end
    data = {
      chat_id: @chat_id,
      text: "#{title}#{text}",
      parse_mode: "MarkdownV2"
    }
    post data
  end
end
