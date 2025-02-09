require 'net/http'
require 'net/https'
require 'uri'
require 'json'
require 'set'

module Slackbotsy

  class Bot

    def initialize(options)
      @options = options

      ## use set of tokens for (more or less) O(1) lookup on multiple channels
      @options['outgoing_token'] = Array(@options['outgoing_token']).to_set
      
      @regexes = {}
      setup_incoming_webhook    # http connection for async replies
      yield if block_given?     # run any hear statements in block
    end

    ## setup http connection for sending async incoming webhook messages to slack
    def setup_incoming_webhook
      @uri  = URI.parse "https://#{@options['team']}.slack.com/services/hooks/incoming-webhook?token=#{@options['incoming_token']}"
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = true
      @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    ## format to send text to incoming webhook
    def encode_payload(text, options = {})
      payload = {
        text:     text,
        username: @options['name'],
        channel:  @options['channel'].gsub(/^#?/, '#'), # ensure channel begins with #
      }.merge(options)

      "payload=#{payload.to_json.to_s}"
    end

    ## send text to slack using incoming webhook
    def say(text, options = {})
      request = Net::HTTP::Post.new(@uri.request_uri)
      request.body = encode_payload(text, options)
      response = @http.request(request)
      return nil                # so as not to trigger text in outgoing webhook reply
    end

    def attach(text, attachment, options = {})
      options = { attachments: [ attachment ] }.merge(options)
      say(text, options)
    end

    ## add regex to things to hear
    def hear(regex, &block)
      @regexes[regex] = block
    end

    ## pass list of files containing hear statements, to be opened and evaled
    def eval_scripts(*files)
      files.flatten.each do |file|
        self.instance_eval File.open(file).read
      end
    end
    
    ## check message and run blocks for any matches
    def handle_item(msg)
      return nil unless @options['outgoing_token'].include? msg[:token] # ensure messages are for us from slack
      return nil if msg[:user_name] == 'slackbot'  # do not reply to self
      return nil unless msg[:text].is_a?(String) # skip empty messages

      ## loop things to look for and collect immediate responses
      ## rescue everything here so the bot keeps running even with a broken script
      responses = @regexes.map do |regex, proc|
        if mdata = msg[:text].strip.match(regex)
          begin
            Slackbotsy::Message.new(self, msg).instance_exec(mdata, &proc)
          rescue => err
            err
          end
        end
      end

      ## format any replies for http response
      if responses
        { text: responses.compact.join("\n") }.to_json
      end
    end

  end

end
