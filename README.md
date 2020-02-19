# telnyx-nomad

I will discuss the main use case for this program in a blog post that I haven't written yet.

This program implements a server that accepts webhook connections from [Telnyx](https://refer.telnyx.com/asgvm) to receive SMS messages and calls. In the latter case, it also acts as an answering machine by playing a recorded message and recording the call into an mp3 file. Notifications are sent to the recipient using [Pushbullet](https://www.pushbullet.com/).

The program is written in Crystal using the [Kemal](https://kemalcr.com/) framework. The server is self-contained (it doesn't need another server like Apache or nginx) and can (and should) be run with normal user credentials.


## Installation

This program needs to run on a computer with a public IP, because Telnyx will access the webhooks via standard URL endpoints, so most likely you'll be running it on a VPS (you can get one cheaply from a company like [Virmach](https://billing.virmach.com/aff.php?aff=9686)).

If you don't have Crystal yet, you need to first [install](https://crystal-lang.org/install/) it. After that, installation is simple:

1. `git clone https://github.com/larilampen/telnyx-nomad.git`
2. `cd telnyx-nomad && shards install`
3. `cp config.json.template config.json`
4. Edit `config.json` with your details, as described below.


## Configuration file

Look at the provided template (if you followed the above steps, `config.json` now contains a copy of it) to see the structure of the configuration file. There are three types of items in it.

**Credentials**: For Pushbullet, the API token (unique to each user account) is needed, along with a device ID (which specifies which of your devices the notifications will be sent to). For Telnyx, an API key is required.

**Numbers**: A list of the phone numbers you use at Telnyx. Each has a name (used instead of the number simply to keep the notifications shorter and easier to read) and a message URL, which is the message that will be played when a call is received.

**Other options**: The field `default-message` specifies what message will be played in case a number is called that isn't included in the numbers section. The field `port` specifies the port number to listen to.

The best format for the answer message files is a monaural mp3 with a relatively low bitrate, because phone lines don't support stereo, nor are they exactly high fidelity in terms of sound quality.

You can choose to host the message files on another server, or they can be placed in the folder `public` (create it if it doesn't exist), which will cause Kemal to automatically serve them when requested.


## Usage

Simply run with `crystal src/telnyx.cr`, or build into a binary (`crystal build src/telnyx.cr`) if desired. Running inside `tmux` or `screen` makes it easy to detach and rejoin the session when needed.


## Contributing

1. Fork it (<https://github.com/larilampen/telnyx-nomad/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request


## Contributors

- [Lari Lampen](https://github.com/larilampen)
