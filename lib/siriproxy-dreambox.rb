require 'cora'
require 'siri_objects'
require 'pp'
require 'open-uri'
require 'hpricot'
require 'uri'
require 'yaml'
require 'twitter'
require 'language'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This 
# is good base code for other plugins.
# 
# Remember to add other plugins to the "config.yml" file if you create them!
######
class SiriProxy::Plugin::Dreambox < SiriProxy::Plugin
  @@CHANNELS = nil
  @@CURRENT_CHANNEL = nil
  if ENV["SIRIPROXY_DREAMBOX_LANG"] 
    @@LANG = ENV["SIRIPROXY_DREAMBOX_LANG"].to_sym  #needs to be set correctly in code before startup (use :en or :ger)
  else
    @@LANG = :en
  end
  # These are some predined mappings , they are merged with the user defined mappings
  MAPPINGS = {'BBC1' => 'BBC 1 LONDON', 'BBC2' => 'BBC 2 ENGLAND', 'CNN International' => 'CNN INT.', 'CNN' => 'CNN INT.', 'THE NETHERLANDS' => 'NED', 'NETHERLANDS' => 'NED', 'ONE' => '1', 'TWO' => '2', 'THREE' => '3', 'FOUR' => '4', 'FIVE' => '5' , 'SIX' =>'6' , 'SEVEN' => '7', 'EIGHT' => '8' , 'NINE' => '9' , 'TEN' => '10'}
  attr_accessor :ip_dreambox
  attr_accessor :mappings

  def initialize(config = {})
    @@since_id = 1 # used to get recent tweets
    @ip_dreambox = config["ip_dreambox"]
    @mappings = MAPPINGS
    puts "Using language : #{@@LANG.to_s}"
    if config["alias_file"] && FileTest.exists?(config["alias_file"])
     user_mappings = YAML.load(File.open(config["alias_file"])) 
     @mappings = @mappings.merge(user_mappings)
     puts "Mappings used : " + @mappings.inspect
    elsif config["alias_file"]
     puts "Specified User alias file not found, check config.yml : " + config["alias_file"]
    end
    if config["bouquet"]
     @@CHANNELS = load_channels(config["bouquet"]) if !@@CHANNELS 
    else
     @@CHANNELS = load_channels if !@@CHANNELS 
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
     return Time.new('1970-01-01') + e2time.to_i + 3600
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
    nextevent = searchresultsdoc.search("//e2event")[0]
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
    event[:starttime] = event[:starttime] + 3600
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
      saystring = "The next broadcast of #{epg[:title]} starts on #{epg[:servicename]} at #{epg[:starttime].strftime('%H')}:#{epg[:starttime].strftime('%M')} on #{epg[:starttime].strftime('%A')}"
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
  
  listen_for /dump channels/i do
    @@CHANNELS.each do |k,v|
      puts "|#{k}|"
    end
    say "Ok, check your console"
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
     channel_data = channel_data.strip.upcase
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
        #response = ask('Spell it out for me')
     end
     #request_completed 
  end

end
