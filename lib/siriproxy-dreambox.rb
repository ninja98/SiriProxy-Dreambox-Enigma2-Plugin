require 'cora'
require 'siri_objects'
require 'pp'
require 'open-uri'
require 'hpricot'
require 'uri'
require 'yaml'
require 'twitter'
require 'language'
require 'json'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This
# is good base code for other plugins.
#
# Remember to add other plugins to the "config.yml" file if you create them!
######
class SiriProxy::Plugin::Dreambox < SiriProxy::Plugin
  @@CHANNELS = nil
  @@lastmatches  = []
  @@CURRENT_CHANNEL = nil
  if ENV["SIRIPROXY_DREAMBOX_LANG"]
    @@LANG = ENV["SIRIPROXY_DREAMBOX_LANG"].to_sym  #needs to be set correctly in code before startup (use :en or :ger)
  else
    @@LANG = :en
  end
  # These are some predined mappings , they are merged with the user defined mappings
  MAPPINGS = {}
  attr_accessor :ip_dreambox
  attr_accessor :mappings

  def initialize(config = {})

    #config.inspect
    @@since_id = 1 # used to get recent tweets
    @ip_dreambox = config["ip_dreambox"]
    @mappings = MAPPINGS
    puts "Using language : #{@@LANG.to_s}"
    puts "Using GMT timezone offset : #{Time.now.gmt_offset} seconds"
    if config["alias_file"] && FileTest.exists?(config["alias_file"])
      user_mappings = YAML.load(File.open(config["alias_file"]))
      @mappings = @mappings.merge(user_mappings)
      puts "User alias file found"
      puts "Mappings used : " + @mappings.inspect
    elsif config["alias_file"]
      puts "Specified User alias file not found, check config.yml : " + config["alias_file"]
    end
    if config["bouquet"]
      @@CHANNELS = load_channels(config["bouquet"]) if !@@CHANNELS
    else
      @@CHANNELS = load_channels if !@@CHANNELS
    end
    if config["twitter_consumer_key"]
      Twitter.configure do |config_twitter|
        config_twitter.consumer_key = config["twitter_consumer_key"]
        config_twitter.consumer_secret = config["twitter_consumer_secret"]
        config_twitter.oauth_token = config["twitter_oauth_token"]
        config_twitter.oauth_token_secret = config["twitter_token_secret"]
        puts "Twitter app initialized"
      end
    end
    puts "Channels loaded ::: " + @@CHANNELS.size.to_s
    puts "Dreambox Enigma2 plugin succesfully initialized"
  end

  def load_channels(onlybouquet=nil)
    #if you have custom configuration options, process them here!
    holder = {}
    puts "Initializing dreambox"
    xml = open("http://#{@ip_dreambox.to_s}/web/getservices")
    puts "Dreambox found - loading channels"
    channel_list_url = "http://#{@ip_dreambox.to_s}/web/getservices?sRef="
    doc = Hpricot(xml.read)
    doc.search("//e2service").each do |bouquet|
      bref = bouquet.search("//e2servicereference").inner_text
      bname = bouquet.search("//e2servicename").inner_text
      if !onlybouquet || onlybouquet == bname
        puts "Loading bouquet : #{bname}"
        url = channel_list_url + URI.escape(bref)
        channelsxml = open(url)
        channelsdoc = Hpricot(channelsxml.read)
        # process channel info
        channelsdoc.search("//e2service") do |channel|
          channel_name  = channel.search("//e2servicename").inner_text
          channel_ref = channel.search("//e2servicereference").inner_text
          holder[channel_name.strip.upcase] = {"sname" => channel_name , "bname" => bname , "bref" => bref , "sref" => channel_ref} if channel_name.size > 0 && channel_ref.size > 0
        end
      end #bouquet check
    end
    return holder
  end

  def convert_time(e2time)
    return Time.new('1970-01-01') + e2time.to_i + Time.new.gmt_offset 
  end

  #siri will give its opinion on the program using tweets about the program
  def say_tweets(channel, name) 
    @@since_id = 1 # reset for now to get some comments
    count_tweets = 0
    search = "\"#{channel}\" OR \"#{name}\" -rt -filter:links"
    puts "q = " + search
    Twitter.search(search, :since_id => @@since_id, :rpp => 10, :lang => 'en', :result_type => "recent").map do |status|
      next if status.text.match(/^@/) #skip direct mentions
      text = status.text.gsub("@","").gsub(/ #[^ ]*/,"")
      text = text.gsub(/^watching/i,"").strip

      #added to prevent repeat of broadcast name.. disabled for now
      #text = text.gsub(name,"").strip 

      #potential problem here with duplicate tweets - to be investigated
      puts (Time.now - status.created_at).to_s + " seconds ago"
      #say "#{status.from_user}: #{status.text}"
      say "#{text}" if text.size > 10
      @@since_id = status.id if status.id.to_i > @@since_id
      count_tweets = count_tweets + 1
    end 
    say "No comment" if count_tweets == 0
  end

  def search_epg(term)
    url = "http://#{@ip_dreambox}/web/epgsearch?search=#{URI.escape(term)}"
    event = {}
    searchresults = open(url)
    searchresultsdoc = Hpricot(searchresults.read) 
    nextevents = searchresultsdoc.search("//e2event")
    nextevent = nil
    # filter on channels in bouquet

    nextevents.each do |ev|
      nextname = ev.search("//e2eventservicename").inner_text 

      if  @@CHANNELS[nextname.strip.upcase]
        nextevent = ev 
        break 
      end
    end

    if nextevent 
      event = parse_epg_event(nextevent)
    end
    return event
  end

  def set_timer(epg, justplay=0)
    url = "http://#{@ip_dreambox}/web/timeraddbyeventid?sRef=#{epg[:sref]}&eventid=#{epg[:eventid]}&justplay=#{justplay}"
    open(url)
  end


  #get the user's location and display it in the logs
  #filters are still in their early stages. Their interface may be modified
  filter "SetRequestOrigin", direction: :from_iphone do |object|
    puts "[Info - User Location] lat: #{object["properties"]["latitude"]}, long: #{object["properties"]["longitude"]}"

    #Note about returns from filters:
    # - Return false to stop the object from being forwarded
    # - Return a Hash to substitute or update the object
    # - Return nil (or anything not a Hash or false) to have the object forwarded (along with any 
    #    modifications made to it)
  end 

  def say_related_tweets
    adress =  "http://#{@ip_dreambox.to_s}/web/subservices"
    currentdoc = Hpricot(open(adress).read)
    sref = currentdoc.search("//e2servicereference").inner_text
    name = currentdoc.search("//e2servicename").inner_text
    epg = get_epgdetails(sref)
    if epg.size > 0
      say_tweets(name, epg[0][:title]) 
    end
  end


  def current_channel_info
    adress =  "http://#{@ip_dreambox.to_s}/web/subservices"
    currentdoc = Hpricot(open(adress).read)
    sref = currentdoc.search("//e2servicereference").inner_text
    name = currentdoc.search("//e2servicename").inner_text
    epg = get_epgdetails(sref)
    if epg.size > 0 && epg[0][:title]
      say_channel_info(epg[0]) 
    else
      say "You're watching #{name}"
    end
  end

  def next_on_channel_info
    adress =  "http://#{@ip_dreambox.to_s}/web/subservices"
    currentdoc = Hpricot(open(adress).read)
    sref = currentdoc.search("//e2servicereference").inner_text
    name = currentdoc.search("//e2servicename").inner_text
    epg = get_epgdetails(sref)
    if epg.size > 0
      say_next_event_info(epg[1]) 
    end
  end


  def switch_channel(sref)
    adress =  "http://#{@ip_dreambox.to_s}/web/zap?sRef=#{URI.escape(sref)}"
    puts adress
    open(adress)
  end

  def next_channel
    adress =  "http://#{@ip_dreambox}/web/remotecontrol?command=108"
    open(adress)
    adress =  "http://#{@ip_dreambox}/web/remotecontrol?command=352"
    open(adress)
  end

  def previous_channel
    adress =  "http://#{@ip_dreambox}/web/remotecontrol?command=105"
    open(adress)
    adress =  "http://#{@ip_dreambox}/web/remotecontrol?command=352"
    open(adress)
  end

  def find(name)
    result = find_perfect(name)
    if false && result
      return result
    else
      replacedname = name
      @mappings.each do |k,v|
        replacedname = replacedname.gsub(k,v)
      end
      puts "Trying :" + replacedname + "|"
      result = find_perfect(replacedname)
      if result
        return result
      else
        replacedname = replacedname.gsub(" ","")
        puts "Trying :" + replacedname + "|"
        result = find_perfect(replacedname)
        if result
          return result
        else
          return false
        end 
      end 
    end
  end

  def find_perfect(name)
    if @@CHANNELS[name]
      return @@CHANNELS[name] 
    else
      return false
    end
  end

  def parse_epg_event(epgevent)
    event = {}
    event[:starttime] = Time.new('1970-01-01') + epgevent.search("//e2eventstart").inner_text.to_i 
    #timezone correction - need to look at this later
    event[:starttime] = event[:starttime] + Time.new.gmt_offset 
    event[:endtime] = event[:starttime] + epgevent.search("//e2eventduration").inner_text.to_i
    event[:title] = epgevent.search("//e2eventtitle").inner_text
    event[:description] = epgevent.search("//e2eventdescription").inner_text
    event[:servicename] = epgevent.search("//e2eventservicename").inner_text
    event[:sref] = epgevent.search("//e2eventservicereference").inner_text
    event[:eventid] = epgevent.search("//e2eventid").inner_text
    return event 
  end

  def get_epgdetails(sref)
    epgurl = "http://#{@ip_dreambox}/web/epgservice?sRef=" + URI.escape(sref)
    epgdoc = Hpricot(open(epgurl).read)
    currentevent = epgdoc.search("//e2event")[0]
    nextevent = epgdoc.search("//e2event")[1]
    event = {}
    nevent = {}
    if currentevent 
      event = parse_epg_event(currentevent)
      #nextevent = 
    end
    if nextevent
      nevent = parse_epg_event(nextevent)
    end

    return [event, nevent]
  end

  def say_channel_info(epg)
    if epg && epg[:title]
      say "Currently on #{epg[:servicename]} is a program called : #{epg[:title]}"
      say epg[:description]
      say "The program started at " + epg[:starttime].strftime('%H').to_s +
      ":" + epg[:starttime].strftime('%M').to_s +
      " and will end at " + epg[:endtime].strftime('%H').to_s + ":" + epg[:endtime].strftime('%M').to_s
      say "Thats another " +((epg[:endtime] - Time.now) / 60).round.to_i.to_s + " minutes."
    end
  end

  def say_next_event_info(epg)
    if epg[:title]
      say "Next on #{epg[:servicename]} is a program called : #{epg[:title]}" 
      say epg[:description] if epg[:description] && epg[:description].size > 1
    end
    #say "The program starts at " + epg[:starttime].strftime('%H').to_s +
    #     ":" + epg[:starttime].strftime('%M').to_s +
    #     " and will end at " + epg[:endtime].strftime('%H').to_s + ":" + epg[:endtime].strftime('%M').to_s
    #say "Thats another " +((epg[:endtime] - Time.now) / 60).round.to_i.to_s + " minutes."
  end

  def start_dreambox
    adress =  "http://#{@ip_dreambox}/web/powerstate?newstate=4"
    open(adress)
    say "Ok, let's watch tv"
  end

  def standby_dreambox
    adress =  "http://#{@ip_dreambox}/web/powerstate?newstate=5"
    open(adress)
    say "Ok"
  end

  def say_epg_full(epg)
    saystring = "The broadcast of #{epg[:title]} starts on #{epg[:servicename]} at #{epg[:starttime].strftime('%H')}:#{epg[:starttime].strftime('%M')} on #{epg[:starttime].strftime('%A')}"
    say saystring
    timediff = ((epg[:starttime] - Time.now) / 60).round.to_i
    epg[:timediff] = timediff
    if timediff < 0
      left = ((epg[:endtime] - Time.now) / 60).round.to_i
      say "Hey its currently broadcasting, for #{0-timediff} minutes already, #{left} minutes left" 
    else
      minutes = ((epg[:starttime] - Time.now) / 60).round.to_i
      hours = minutes/60
      minutes = minutes%60
      if hours == 0        
        say "That's #{minutes} minutes from now. "
      else
        say "That's #{hours} hours and #{minutes} minutes from now. "
      end
    end
  end

  def say_live_match(match_info,count)
    if count == 1
      say "I found a live match for you, number #{count}"
    else
      say "I found another live match for you, number #{count}"
    end
    #puts match_info.inspect
    #{:channel=>{"sname"=>"Sky Calcio 1", "bname"=>"Favs", "bref"=>"1:7:1:0:0:0:0:0:0:0:FROM BOUQUET \"userbouquet.aa83e.tv\" ORDER BY bouquet", "sref"=>"1:0:1:2DC7:1A2C:FBFF:820000:0:0:0:"}, :matchinfo=>{"source"=>"lst", "id"=>"227194", "home_team"=>"internazionale", "away_team"=>"parma", "competion"=>"Serie A", "livenow"=>true, "date"=>"2012-01-07", "time"=>"2:45pm", "fulltime"=>"2012-01-07 14:45:00 -0500", "type"=>"Live",

    say "It's on #{match_info[:channel]["sname"]} #{match_info[:channel][:country]}"  
    say "#{match_info[:matchinfo]["home_team"].capitalize} plays against #{match_info[:matchinfo]["away_team"].capitalize} in the #{match_info[:matchinfo]["competion"].capitalize}"  
    say "It starts at #{match_info[:matchinfo][:localruntime].strftime('%H')}:#{match_info[:matchinfo][:localruntime].strftime('%M')} on #{match_info[:matchinfo][:localruntime].strftime('%A')}"
    #puts match_info[:matchinfo].inspect
    timediff = ((match_info[:matchinfo][:localruntime] - Time.now) / 60).round.to_i
    match_info[:matchinfo][:timediff] = timediff
    if timediff < 0
      say "Its currently broadcasting, for #{0-timediff} minutes already" 
      response = ask "You want to watch it?"
      if(response =~ TRANSLATION[:lang => @@LANG, :response => :yes]) #process their response
        switch_channel(match_info[:channel]["sref"])
        say "Ok here you go"
      else
        say "Ok, I thought so"
      end
    else
      minutes = ((match_info[:matchinfo][:localruntime] - Time.now) / 60).round.to_i
      hours = minutes/60
      minutes = minutes%60
      if hours == 0        
        say "That's #{minutes} minutes from now. "
      else
        say "That's #{hours} hours and #{minutes} minutes from now. "
      end
    end
  end

  def send_tweet(tweettext, negative)
    adress =  "http://#{@ip_dreambox.to_s}/web/subservices"
    currentdoc = Hpricot(open(adress).read)
    sref = currentdoc.search("//e2servicereference").inner_text
    name = currentdoc.search("//e2servicename").inner_text
    epg = get_epgdetails(sref)
    if epg.size > 0 && epg[0][:title]
      tweettext = "Watching #{epg[0][:title]} on #{epg[0][:servicename]}. " + tweettext
    end
    if negative
      tweettext =tweettext + " #iTVSiri /cc: @BitchAboutTV"
    else
      tweettext =tweettext + " #iTVSiri "
    end
    say "Ok, lets send a tweet saying :" 
    say tweettext
    response = ask "Ready to send it?" 
    if(response =~ TRANSLATION[:lang => @@LANG, :response => :yes]) #process their response
      Twitter.update(tweettext)
      say TRANSLATION[:lang => @@LANG, :response => :sent_tweet]
    else
      say "Ok, I won't send it"
    end
  end

  def send_tweet_by_dialog(negative)
    response = ask TRANSLATION[:lang => @@LANG, :response => :ask_opinion]  
    send_tweet(response,negative) 
  end

  def help_on_dreambox
    say "I'll control the TV for you, here is what I can do:"
    say "This is help on English commands only for now although I understand some German, but I'm still learning that."
    say "'Siri switch to next channel'. Zaps to next channel"
    say "'Siri switch to previous channel'. Zaps to previous channel"
    say "'Siri whats currently on tv'. Give info about current channel (if epg available)"
    say "'Siri whats currently on this channel'. Give info about current channel (only if epg available)"
    say "'Siri whats next on this channel'. I will give info about next program on this channel (if epg available)"
    say "'Siri whats next on tv'. I will give info about next program on the current channel (if epg available)"
    say "'Siri lets stop watching tv'. I will set dreambox into standby mode"
    say "'Siri I want to watch tv'.  I will turn on dreambox"
    say "'Siri when is the next episode of the mentalist on tv'. I will tell you date and time of the next episode (if epg available). Also I'll ask you whether you want to record it. Wow."
    say "'Siri what do you think of this program on tv?'. I will give you its opinion of the current program"
    say "'Siri whats right now on tv'. I will provide info about whats currently on tv"
    say "'Siri whats right now on BBC2'. I will provide info about what's currently playing on BBC2"
    say "'Siri switch to channel RTL2'. I will switch to channel with the name RTL2 (uses alias file for your own naming)"
    say "'Siri I like the program on tv'"
    say "'Siri I want to bitch about the current shit on tv'. I help you manage your anger regarding the broadcast"
    say "'Siri I want to approve the program on tv saying this is nice!'. Let people know you like the current program on TV"
    say "'Siri I want to bitch about the program on tv saying yuk what is this? Terrible'. Release your frustration with the current broadcast"
    say "I will understand similar sentences, Apple has made me very clever, so try me"
  end

  def get_matches_for_keyword
    #to be completed
    adress =  "http://sirilive.cloudfoundry.com/live2?fromdate=01-07-2012&todate=01-07-2012&keyword=#{keyword}"

  end

  def get_live_schedule(fromdate, todate, onlylive=true, livenow=true, keyword="")

    hotchannels = {}
    failedchannels = {}
    adress =  "http://sirilive.cloudfoundry.com/live2?fromdate=#{fromdate.strftime('%m')}-#{fromdate.strftime('%d')}-#{fromdate.strftime('%Y')}&todate=#{todate.strftime('%m')}-#{todate.strftime('%d')}-#{todate.strftime('%Y')}&keyword=#{URI.escape(keyword)}"
    puts adress
    begin
      json = open(adress)
    rescue => e
      say "There was a problem getting match information, please try again later"
      return [hotchannels,failedchannels]
    end
    schedule = JSON.parse(json.read)
    #puts schedule.inspect
    #puts schedule.class.name.to_s
    hotchannels = {}
    failedchannels = {}
    selected = schedule.select do |v|
      include = false

      if v["type"] == 'Live' || !onlylive 
        puts "Found potential match candidate :: "
        puts v.inspect
        date = v["fulltime"]
        puts "startdate match :" + date
        parsedtime = Time.new(date[0..3].to_i, date[5..6].to_i, date[8..9].to_i, date[11..12].to_i, date[14..15].to_i, date[17..18].to_i, date[20..22]+ ":" + date[23..24])
        v["localtime"] = parsedtime.localtime 
        v[:localruntime] = parsedtime.localtime
        next if parsedtime.localtime < (Time.now - 3600 - 2700) #&& !v["livenow"] # skip if match ended
        v["channels"].each do |channel_name,meta|
          puts "Checking if #{channel_name.upcase} can be found (mapped or in epg)"
          foundit = find(channel_name.upcase)
          if foundit
            include = true
            foundit[:topcountry] =  meta["topcountry"]
            foundit[:country]   =   meta["country"]
            hotchannels[channel_name] = { :channel => foundit, :matchinfo => v}
            puts "Result : " + foundit.inspect
          else
            include = false
            failedchannels[channel_name] = {:channel_name => channel_name, :matchinfo => v}
            puts "Result fail : " + foundit.inspect
          end 
          # check time
          #include
        end 
      end
    end
    #puts "HC:" + hotchannels.inspect
    return [hotchannels, failedchannels]
  end

  listen_for /dump channels/i do
    @@CHANNELS.each do |k,v|
      puts "|#{k}|"
    end
    say "Ok, check your console"
  end

  #Siri is there a match of Manchester on TV today
  listen_for /match.*of (.*) on TV( right now|today| tomorrow| this week|.*)/i   do |team,period|
    puts "Looking up matches for #{team}"
    puts "Period #{period}"
    datefrom = Time.now
    dateto = Time.now + (3600*24*7)

    if period.match /today/i
      datefrom = Time.now
      dateto = Time.now
    end

    if period.match /right now/i
      datefrom = Time.now
      dateto = Time.now
    end

    if period.match /tomorrow/i
      datefrom = Time.now + (3600*24)
      dateto = Time.now + (3600*24)
    end

    if period.match /this week/i
      dateto = Time.now + (3600*24*7)
    end


    results = get_live_schedule(datefrom,dateto,true,true,team)
    matches = results[0]
    fails = results[1]
    if matches.size > 0
      count = 1
      @@lastmatches = []
      matches.each do |channel_name,match|
        #epg = get_epgdetails(match[:channel]["sref"])
        #puts "looked up epg" + epg.inspect
        #priority to top countries
        if  match[:channel][:topcountry] &&  match[:channel][:topcountry] == 1
          @@lastmatches << match
          say_live_match(match, count)
          count = count + 1 
        end
      end
      matches.each do |channel_name,match|
        #      epg = get_epgdetails(match[:channel]["sref"])
        #puts "looked up epg" + epg.inspect
        #priority to top countries
        if  !match[:channel][:topcountry] ||  match[:channel][:topcountry] == 0
          say_live_match(match, count) 
          count = count +1
        end
      end

    else
      if fails.size == 0 
        say "I did not find matches of #{team} you can watch #{period} "
      else
        #puts "Failed channels::" + fails.inspect
        if fails.size == 1
          say "I did find one match of #{fails[fails.keys[0]][:matchinfo]['home_team'].to_s.capitalize} against #{fails[fails.keys[0]][:matchinfo]['away_team'].to_s.capitalize} on the channels #{fails.keys[0].to_s}, but this is not a channel that you have subscribed to."
        else
          say "I did find one or more matches of #{team} on #{fails.size} different channels, like #{fails[fails.keys[0]][:channel_name]} and #{fails[fails.keys[1]][:channel_name]}, but no channels that you have subscribed to. "
        end
      end
    end 
  end

  listen_for /match.*TV( right now| today| tomorrow).*/i do |period|
    puts "Period #{period}"
    datefrom = Time.now
    dateto = Time.now + (3600*24*7)

    if period.match /today/i
      datefrom = Time.now
      dateto = Time.now
    end
    if period.match /right now/i
      datefrom = Time.now
      dateto = Time.now
    end

    if period.match /tomorrow/i
      datefrom = Time.now + (3600*24)
      dateto = Time.now + (3600*24)
    end
    # disabled for now - might cause backend side blowup
    if period.match /this week/i
      dateto = Time.now + (3600*24*7)
    end
    results = get_live_schedule(datefrom,dateto,true)
    
    matches = results[0]
    fails = results[1]
    if matches.size > 0
      count  = 1
      matches.each do |channel_name,match|
        #epg = get_epgdetails(match[:channel]["sref"])
        #puts "looked up epg" + epg.inspect
        say_live_match(match, count) 
        count  = count +1
      end
    else
      say "There are no live matches you can view at the moment"
    end 
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :voice_opinion]  do
    say_related_tweets
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :current_channel_info_1] do 
    current_channel_info
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :current_channel_info_2] do 
    current_channel_info
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :next_on_channel_info_1] do 
    next_on_channel_info
    #request_completed
  end


  listen_for COMMANDS[:lang => @@LANG, :command => :next_channel] do 
    next_channel
    say "Ok"
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :previous_channel] do 
    previous_channel
    say "Ok"
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :standby_dreambox] do 
    standby_dreambox
    request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :start_dreambox] do
    start_dreambox
    request_completed
  end


  listen_for COMMANDS[:lang => @@LANG, :command => :find_next_episode] do |term|
    event = search_epg(term) 
    if event.size > 0
      say_epg_full(event)
      if (event[:timediff] > 0)
        response = ask TRANSLATION[:lang => @@LANG, :response => :record_question]
        if(response =~ TRANSLATION[:lang => @@LANG, :response => :yes]) #process their response
          set_timer(event)
          say TRANSLATION[:lang => @@LANG, :response => :confirm_record]
        else
          say "Ok, I won't record it"
        end
      else
        response = ask "You want to watch it now?"
        if(response =~ TRANSLATION[:lang => @@LANG, :response => :yes]) #process their response
          switch_channel(event[:sref])
          say "Ok here you go"
        else
          say "Ok, I thought so"
        end
      end
    else
      say "I did not find any information about #{term}"
    end
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :next_on_channel_info_2] do 
    next_on_channel_info
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :current_channel_info_3] do 
    current_channel_info
    #request_completed
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :now_on_channel_info_1] do |channel_data|
    channel_data = channel_data.strip.upcase
    found = find(channel_data)
    if found && found.size  > 0
      epg = get_epgdetails(found["sref"])
      say_channel_info(epg[0]) if epg.size > 0
      response = ask "You want to watch it?"
      if(response =~ /yes/i) #process their response
        switch_channel(found["sref"])
        say "Ok, here you go"
      else
        say "Ok, fine"
      end
    else
      say "Did not find any info about #{channel_data}"
    end
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :switch_channel] do |channel_data|
    channel_data = channel_data.to_s.strip.upcase
    # phase I - try perfect match
    found = find(channel_data)
    if found 
      say "Ok lets watch " + found["sname"]
      switch_channel(found["sref"])
      epg = get_epgdetails(found["sref"])
      if epg.size > 0 
        say_channel_info(epg[0])
        say_next_event_info(epg[1])
      else
        say "No EPG details available"
        #request_completed 
      end 
    else
      response = ask "Did not find that channel,..what was the name if the channel again?"
      response = response.strip.upcase
      found = find(response)
      if found
        say "Ok lets watch " + found["sname"]
        switch_channel(found["sref"])
        epg = get_epgdetails(found["sref"])
        if epg.size > 0 
          say_channel_info(epg[0])
          say_next_event_info(epg[1])
          say "There you go"
        end
      else
        say "Can't find that channel"
      end
      #request_completed
    end
    #request_completed 
  end


  listen_for COMMANDS[:lang => @@LANG, :command => :bitch_about_tv_detailed] do |tweet_content|
    if tweet_content
      send_tweet(tweet_content, true)
    end
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :bitch_about_tv] do 
    send_tweet_by_dialog(true)
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :complain_about_tv_detailed] do |tweet_content|
    if tweet_content
      send_tweet(tweet_content, true)
    end
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :complain_about_tv] do 
    send_tweet_by_dialog(true)
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :like_about_tv_detailed] do |tweet_content|
    if tweet_content
      send_tweet(tweet_content, false)
    end
  end

  listen_for COMMANDS[:lang => @@LANG, :command => :like_about_tv] do
    send_tweet_by_dialog(false)
  end

  listen_for /itv help/i do
    help_on_dreambox
  end

  listen_for /idv help/i do
    help_on_dreambox
  end
end
