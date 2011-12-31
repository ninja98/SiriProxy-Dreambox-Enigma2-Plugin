USED_LANGUAGE = :ger
COMMANDS = {
             {:lang => :en,  :command => :next_channel} => /next channel(.*)/i,
             {:lang => :ger, :command => :next_channel} => /n.chster kanal(.*)/i,   
             {:lang => :en , :command => :previous_channel} => /previous channel(.*)/i,
             {:lang => :ger, :command => :previous_channel} => /letzter kanal(.*)/i,
             {:lang => :en,  :command => :current_channel_info_1} => /currently(.*) on tv/i,
             {:lang => :ger, :command => :current_channel_info_1} => /derzeit(.*) I'm fernsehen/i,
             {:lang => :en,  :command => :current_channel_info_2} => /currently(.*) on this channel/i,
             {:lang => :ger, :command => :current_channel_info_2} => /derzeit(.*) auf diesem kanal/i,
             {:lang => :en,  :command => :next_on_channel_info_1} => /next(.*) on this channel/i,
             {:lang => :ger, :command => :next_on_channel_info_1} => /was(.*) kommt danach/i,
             {:lang => :en,  :command => :next_on_channel_info_2} => /next(.*) on tv/i,
             {:lang => :ger, :command => :next_on_channel_info_2} => /was(.*) nachst im fernsehen/i,
             {:lang => :en,  :command => :standby_dreambox} => /stop(.*)watching(.*)tv/i,
             {:lang => :ger, :command => :standby_dreambox} => /schalte(.*)fernseher(.*)aus/i,
             {:lang => :en,  :command => :start_dreambox} => /want(.*)watch(.*)tv/i,
             {:lang => :ger, :command => :start_dreambox} => /schalte(.*)fernseher(.*)ein/i,
             {:lang => :en,  :command => :find_next_episode} => /next episode of (.*) on TV/i,
             {:lang => :ger, :command => :find_next_episode} => /n.chste folge von (.*) im fernsehen/i,
             {:lang => :en,  :command => :voice_opinion} => /(.*)what d?o? ?you think(.*)/i,
             {:lang => :ger, :command => :voice_opinion} => /(.*)was denkst du(.*)/i,
             {:lang => :en,  :command => :now_on_channel_info_1} => /right now on (.*)/i,
             {:lang => :ger, :command => :now_on_channel_info_1} => /derzeit auf (.*)/i,
             {:lang => :en,  :command => :current_channel_info_3} => /(.*)right now on tv/i,
             {:lang => :ger, :command => :current_channel_info_3} => /(.*)derzeit im fernsehen/i,
             {:lang => :en,  :command => :switch_channel} => /channel (.*)/i,
             {:lang => :ger, :command => :switch_channel} => /kanal (.*)/i 
}

TRANSLATION = {
             {:lang => :en, :response => :record_question } => "Shall I set a timer to record it?",
             {:lang => :ger,:response => :record_question } => "Soll ich eine Aufnahme programmieren?",
             {:lang => :en, :response => :confirm_record } => "Ok, I'll record it for you",
             {:lang => :ger, :response => :confirm_record } => "Ok,ich werde es fuer dich aufnehmen",
             {:lang => :en, :response => :yes} => /yes/i,
             {:lang => :ger, :response => :yes} => /ja/i,
             {:lang => :en, :response => :no} => /no/i,
             {:lang => :ger, :response => :no} => /nein/i 
            }
