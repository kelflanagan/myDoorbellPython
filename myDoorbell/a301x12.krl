ruleset a301x12 {
  meta {
    name "myDoorbell"
    description <<
      Doorbell Application
    >>
    author "Kelly Flanagan"
    // Uncomment this line to require Marketplace purchase to use this app.
    // authz require user
    logging on
    
    // functions available through API
    provides myDoorbellRingtoneChunk, myDoorbellConfig

    sharing on

    key dropbox {
      "app_key" : "nml34ywdqiosl0q",
      "app_secret" : "y93546ekbkfe1pu"
    }

    use module a169x701 alias CloudRain
    use module a41x196 alias SquareTag

  }

  dispatch {
    // Some example dispatch domains
    // domain "example.com"
    // domain "other.example.com"
  }

  global {
    // Dropbox base url
    dropbox_base_url = "https://api.dropbox.com/1";

    // convert url encoded strings to key, value pair map
    decode_content = function(content) {
      content.split(re/&/).map(function(x){x.split(re/=/)})
			  .collect(function(a){a[0]})
			  .map(function(k,v){a = v[0];a[1]})
    }

    // Oauth header constructor
    create_oauth_header_value = function(key, key_secret, token, token_secret) {
      'OAuth oauth_version="1.0", oauth_signature_method="PLAINTEXT", 
      oauth_consumer_key="' + key + (token => '", oauth_token="' + token + '", ' | '", ') + 
      'oauth_signature="' + key_secret + '&' + token_secret + '"';
    }

    // Dropbox API call
    dropbox_core_api_call = function(method) {
      http:get(dropbox_base_url+method,
      {},
      {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
						   keys:dropbox('app_secret'),
              		 			   ent:access_token,
       			 			   ent:access_token_secret)
      });
    }

    // list files in root directory of Dropbox sandbox
    dropbox_list_files = function() {
      list = dropbox_core_api_call('/metadata/sandbox/?list=true');
      list = list{'content'}.decode();
      list{'contents'}.map(function(x){x{'path'}}).sort();
    }
			    
    // Dropbox API call
    // get a file from dropbox
    dropbox_get_file = function(filename) {
      http:get('https://api-content.dropbox.com/1/files/sandbox/' + filename,
      {},
      {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
						   keys:dropbox('app_secret'),
                         			   ent:access_token,
                         			   ent:access_token_secret)
      })
    }

    // get a chunk of a file from dropbox
    dropbox_get_file_chunk = function(filename, start, end) {
      http:get('https://api-content.dropbox.com/1/files/sandbox/' + filename,
      {},
      {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
						   keys:dropbox('app_secret'),
                         			   ent:access_token,
                         			   ent:access_token_secret),
       "Range" : 'bytes=' + start + '-' + end
      })
    }

    // Dropbox API call
    // this returns the size of the file pointed to by filename parameter
    // if the file doesn't exist a size of zero is returned
    dropbox_get_file_size = function(filename) {
      status = http:get('https://api.dropbox.com/1/metadata/sandbox/' + filename,
               {},
               {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
						   keys:dropbox('app_secret'),
                         			   ent:access_token,
                         			   ent:access_token_secret)
               }).pick("$.status_code");

      (status eq 404) => 0 |
               http:get('https://api.dropbox.com/1/metadata/sandbox/' + filename,
               {},
               {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
						   keys:dropbox('app_secret'),
                         			   ent:access_token,
                         			   ent:access_token_secret)
               }).pick("$.content").decode().pick("$.bytes");
    }

    // file_list2html() recursively traverses an array of list data and for
    // each entry in the array prepend and append the appropriate html to add the
    // file list data to the file area in the applicaiton.  This creates <option>
    // elements for each file for a "select" element in the html
    //
    // list is an array that will be passed in
    // where each entry is a string containing the file in the format /file_name.extension
    file_list2html = function(flist) {
      // remove preceeding /
      list_item = flist.head().replace(re/\//, "");

      (flist.length() > 0) => 
        '<option value="#{list_item}">#{list_item}</option>' + file_list2html(flist.tail())
	|
	"";
    }

    // log2html() recursively traverses an array of log data and for
    // each entry in the array appends the appropriate html to add the
    // log data to a textarea that will be rendered elsewhere.
    //
    // log is an array that will be passed in
    // where each entry is a string containing the date and time.
    log2html = function(log) {
      item_map = log.head();
      item_time = item_map{"time"};
      this_date = date(item_time);
      todays_date = date(time:now());
      this_door = item_map{"door"};

      (log.length() > 0) => 
        (this_date eq todays_date) =>
	  (this_door eq "front") =>
	    "<font color=\"#00aa00\">" + "<b>" + time:strftime(item_time, "%c") + "</b>" + "<br>" +
	    "</font>" + log2html(log.tail()) |
	    "<font color=\"#0000aa\">" + "<b>" + time:strftime(item_time, "%c") + "</b>" + "<br>" + 
	    "</font>" + log2html(log.tail())
	  |
	  (this_door eq "front") =>
	    "<font color=\"#00aa00\">" + time:strftime(item_time, "%c") + "<br>" + "</font>" + 
	    log2html(log.tail()) |
	    "<font color=\"#0000aa\">" + time:strftime(item_time, "%c") + "<br>" + "</font>" + 
	    log2html(log.tail())
	|
	"";
    }

    // date() returns the date from the passed in time
    date = function(time) {
      time.split(re/T/).head();
    }

    // insertTime() inserts the time value into a map where the key == "time"
    insertTime = function(k, v) {
      (k eq "time") => time:now() | v;
    }

    // API functions available at 
// https://cs.kobj.net/sky/cloud/a301x7/fn?_eci=C695CE4E-0B91-11E3-9DB3-90EBE71C24E1

    // myDoorbellConfig()
    // Input: no parameters
    // Returns: JSON repreentation of the virtual doorbell state
    //          the physical device should adjust its state to match
    // Example Return: {"ringtone_new_rear":"true",
    // 	       	        "silent_rear":"false",
    //		        "volume_rear":63,
    //		        "volume_front":79,
    //		        "ringtone_new_front":"true",
    //		        "silent_front":"false"
    //                  etc...
    //                 }
    //
    // Example curl: curl https://cs.kobj.net/sky/cloud/b502118x0/
    //              myDoorbellConfig?_eci=C695CE4E-0B91-11E3-9DB3-90EBE71C24E1
    //
    myDoorbellConfig = function() {
      ent:myDoorbellState;
    }

    // myDoorbellRingtoneChunk()
    // Input: parameter indicating "front" or "rear" door
    //        parameters indicating start and end bytes
    // Returns: JSON containing ringtone chunk
    // Example Return: {"ringtone_chunk":"utf-8 encoded chunk"}
    //
    // Example curl: curl http://cs.kobj.net/sky/cloud/a301x7/myDoorbellRingtoneChunk?door=front&
    //							_eci=C695CE4E-0B91-11E3-9DB3-90EBE71C24E1&
    //                                                  start=#&end=#
    //
    myDoorbellRingtoneChunk = function(door, start, end) {
      currentState = ent:myDoorbellState;

      ringtone = (door eq "front") => currentState.pick("$.ringtone_name_front") |
      	         (door eq "rear") => currentState.pick("$.ringtone_name_rear") |
		 "error";
		 
      str = (ringtone neq "error") => dropbox_get_file_chunk(ringtone,start,end).pick("$.content") |
            "error";

      h = {};
      (str neq "error") =>  h.put(["ringtone_file"], str) |
      	       		    h.put(["ringtone_error"], "error");
    }

    // function newRingtone
    //
    // parameters: filename of new ringtone to be found at dropbox
    // 		   oldSize is the size of the previous ringtone
    //		   door is either front ot rear
    // return:     A map such a	{"ringtone_new_front":"true",
    //			         "ringtone_size_front":112,
    //			 	 "ringtone_name_front":"my_ringtone"}
    // errors:     If the filename doesn't exist the ringtone file is
    // 		   set to the new filename, the size is set to 0 and the
    //		   need for a new ringtone is set to false.
    newRingtone = function(filename, oldSize, door) {
      newSize = dropbox_get_file_size(filename);
      // if newSize == zero then the file didnt exist
      validSize = ((newSize > 0) && (newSize < 4194304)) => "true" | "false";
      size = (validSize eq "true") => newSize | oldSize;
      returnMap = ((validSize eq "true") && (door eq "front")) =>
      		  	{"ringtone_new_front":"true",
			 "ringtone_size_front":size.as("num"),
			 "ringtone_name_front":"#{filename}"} |
		  ((validSize eq "true") && (door eq "rear")) =>			 
      		  	{"ringtone_new_rear":"true",
			 "ringtone_size_rear":size.as("num"),
			 "ringtone_name_rear":"#{filename}"} |
      		  ((validSize eq "false") && (door eq "front")) =>
      		  	{"ringtone_new_front":"false",
			 "ringtone_size_front":0,
			 "ringtone_name_front":"#{filename}"} |
		  ((validSize eq "false") && (door eq "rear")) =>			 
      		  	{"ringtone_new_rear":"false",
			 "ringtone_size_rear":0,
			 "ringtone_name_rear":"#{filename}"} |
			 "";
      returnMap;
    } // end newRingtone

    // check to see if we are authorized on Dropbox
    account_info_result = dropbox_core_api_call('/account/info');
    authorized = account_info_result{'status_code'} eq '200';
  }


  // beginning of event rules
  // this event is raised to modify doorbell state
  // event:attrs() are passed in with the raising of the event
  // keys that are not part of the doorbell state are silently ignored
  rule myDoorbellConfigEvent {
    select when myDoorbell Config
    pre {
      // initialize status message and be optimistic
      status = "OK";

      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      // only include key/value pairs that are part of doorbell state
      // silently ignore others, status remains OK
      changes = event:attrs().filter(function(k,v) {
      	      					   (k eq "volume_front") ||
						   (k eq "volume_rear") ||
						   (k eq "silent_front") ||
						   (k eq "silent_rear") ||
						   (k eq "email_front") ||
						   (k eq "email_rear") ||
						   (k eq "sms_front") ||
						   (k eq "sms_rear") ||
						   (k eq "webhook_server") ||
						   (k eq "webhook_resource_front") ||
						   (k eq "webhook_resource_rear") ||
						   (k eq "webhook_method") ||
						   (k eq "webhook_payload_rear") ||
						   (k eq "webhook_payload_front") ||
						   (k eq "webhook_http_headers") ||
						   (k eq "poll_time") ||
						   (k eq "ringtone_name_front") ||
						   (k eq "ringtone_name_rear") ||
						   (k eq "ringtone_resource_front") ||
						   (k eq "ringtone_resource_rear") ||
						   (k eq "ringtone_size_front") ||
						   (k eq "ringtone_ack_resource_front") ||
						   (k eq "ringtone_ack_resource_rear") ||
						   (k eq "ringtone_ack_method") ||
						   (k eq "ringtone_ack_payload_rear") ||
						   (k eq "ringtone_ack_payload_front") ||
						   (k eq "ringtone_size_rear") ||
						   (k eq "sms_email_message")
						   });

      // webhook_http_headers, check length and replace if appropriate
      newHeaders = (changes.keys().any(function(x){x eq "webhook_http_headers"})) =>
		    changes.pick("$.webhook_http_headers") | config.pick("$.webhook_http_headers");
      status = ((newHeaders.length() >= 0) && (newHeaders.length() < 101)) => status 
      	       | "Error: Headers";
      changes = ((newHeaders.length() >= 0) && (newHeaders.length() < 101)) => 
  	            changes.put(["webhook_http_headers"], newHeaders) |
      	      	    changes.put(["webhook_http_headers"], config.pick("$.webhook_http_headers"));
      
      // ringtone resource front, check length and replace if appropriate
      newRingtoneResource = (changes.keys().any(function(x){x eq "ringtone_resource_front"})) =>
		              changes.pick("$.ringtone_resource_front")
		            | config.pick("$.ringtone_resource_front");
      status = ((newRingtoneResource.length() > 0) && (newRingtoneResource.length() < 101)) => 
 		   status | "Error: Ringtone Resource";
      changes = ((newRingtoneResource.length() > 0) && (newRingtoneResource.length() < 101)) => 
  	            changes.put(["ringtone_resource_front"], newRingtoneResource) |
      	      	    changes.put(["ringtone_resource_front"], config.pick("$.ringtone_resource_front"));
      
      // ringtone resource rear, check length and replace if appropriate
      newRingtoneResource = (changes.keys().any(function(x){x eq "ringtone_resource_rear"})) =>
		     changes.pick("$.ringtone_resource_rear")
		  |  config.pick("$.ringtone_resource_rear");
      status = ((newRingtoneResource.length() > 0) && (newRingtoneResource.length() < 101)) => 
 		   status | "Error: Ringtone Resource";
      changes = ((newRingtoneResource.length() > 0) && (newRingtoneResource.length() < 101)) => 
  	            changes.put(["ringtone_resource_rear"], newRingtoneResource) |
      	      	    changes.put(["ringtone_resource_rear"], config.pick("$.ringtone_resource_rear"));
      
      // webhook method, check if PUT, POST, or GET and replace if appropriate
      newWebhookMethod = (changes.keys().any(function(x){x eq "webhook_method"})) =>
		     changes.pick("$.webhook_method")
		  |  config.pick("$.webhook_method");
      status = (newWebhookMethod eq "GET") => status |
      	       (newWebhookMethod eq "PUT") => status |
      	       (newWebhookMethod eq "POST") => status |
	       "Error: Webhook Method";
      changes = (newWebhookMethod eq "GET") => changes.put(["webhook_method"], newWebhookMethod) |
      	        (newWebhookMethod eq "PUT") => changes.put(["webhook_method"], newWebhookMethod) |
      	        (newWebhookMethod eq "POST") => changes.put(["webhook_method"], newWebhookMethod) |
	        changes.put(["webhook_method"], config.pick("$.webhook_method"));
      
      // webhook method, check if PUT, POST, or GET and replace if appropriate
      newRingtoneAckMethod = (changes.keys().any(function(x){x eq "ringtone_ack_method"})) =>
		     changes.pick("$.ringtone_ack_method")
		  |  config.pick("$.ringtone_ack_method");
      status = (newRingtoneAckMethod eq "GET") => status |
      	       (newRingtoneAckMethod eq "PUT") => status |
      	       (newRingtoneAckMethod eq "POST") => status |
	       "Error: Ringtone Ack Method";
      changes = (newRingtoneAckMethod eq "GET") => changes.put(["ringtone_ack_method"], 
      	      			      	 	   		newRingtoneAckMethod) |
      	        (newRingtoneAckMethod eq "PUT") => changes.put(["ringtone_ack_method"], 
				      	 	   		newRingtoneAckMethod) |
      	        (newRingtoneAckMethod eq "POST") => changes.put(["ringtone_ack_method"], 
				      	 	                 newRingtoneAckMethod) |
	        changes.put(["ringtone_ack_method"], config.pick("$.ringtone_ack_method"));
      
      // email / sms message, check length and replace if appropriate
      newMessage = (changes.keys().any(function(x){x eq "sms_email_message"})) =>
		    changes.pick("$.sms_email_message") | config.pick("$.sms_email_message");
      status = ((newMessage.length() >= 0) && (newMessage.length() < 111)) => status 
      	       | "Error: SMS/EMAIL Message";
      changes = ((newMessage.length() >= 0) && (newMessage.length() < 111)) => 
  	            changes.put(["sms_email_message"], newMessage) |
      	      	    changes.put(["sms_email_message"], config.pick("$.sms_email_message"));
      
      // webhook payload front, check length and replace if appropriate
      newWebhookPayload = (changes.keys().any(function(x){x eq "webhook_payload_front"})) =>
		     changes.pick("$.webhook_payload_front")
		  |  config.pick("$.webhook_payload_front");
      status = ((newWebhookPayload.length() > 0) && (newWebhookPayload.length() < 101)) => 
 		   status | "Error: Webhook Payload";
      changes = ((newWebhookPayload.length() > 0) && (newWebhookPayload.length() < 101)) => 
  	            changes.put(["webhook_payload_front"], newWebhookPayload) |
      	      	    changes.put(["webhook_payload_front"], config.pick("$.webhook_payload_front"));
      
      // webhook payload rear, check length and replace if appropriate
      newWebhookPayload = (changes.keys().any(function(x){x eq "webhook_payload_rear"})) =>
		     changes.pick("$.webhook_payload_rear")
		  |  config.pick("$.webhook_payload_rear");
      status = ((newWebhookPayload.length() > 0) && (newWebhookPayload.length() < 101)) => 
 		   status | "Error: Webhook Payload";
      changes = ((newWebhookPayload.length() > 0) && (newWebhookPayload.length() < 101)) => 
  	            changes.put(["webhook_payload_rear"], newWebhookPayload) |
      	      	    changes.put(["webhook_payload_rear"], config.pick("$.webhook_payload_rear"));
      
      // webhook payload front, check length and replace if appropriate
      newRingtoneAckPayload = (changes.keys().any(function(x){x eq "ringtone_ack_payload_front"})) =>
		     changes.pick("$.ringtone_ack_payload_front")
		  |  config.pick("$.ringtone_ack_payload_front");
      status = ((newRingtoneAckPayload.length() > 0) && (newRingtoneAckPayload.length() < 101)) => 
 		   status | "Error: Ringtone Ack Payload";
      changes = ((newRingtoneAckPayload.length() > 0) && (newRingtoneAckPayload.length() < 101)) => 
  	            changes.put(["ringtone_ack_payload_front"], newRingtoneAckPayload) |
      	      	    changes.put(["ringtone_ack_payload_front"], config.pick("$.ringtone_ack_payload_front"));
      
      // webhook payload rear, check length and replace if appropriate
      newRingtoneAckPayload = (changes.keys().any(function(x){x eq "ringtone_ack_payload_rear"})) =>
		     changes.pick("$.ringtone_ack_payload_rear")
		  |  config.pick("$.ringtone_ack_payload_rear");
      status = ((newRingtoneAckPayload.length() > 0) && (newRingtoneAckPayload.length() < 101)) => 
 		   status | "Error: Ringtone Ack Payload";
      changes = ((newRingtoneAckPayload.length() > 0) && (newRingtoneAckPayload.length() < 101)) => 
  	            changes.put(["ringtone_ack_payload_rear"], newRingtoneAckPayload) |
      	      	    changes.put(["ringtone_ack_payload_rear"], config.pick("$.ringtone_ack_payload_rear"));
      
      // webhook resource front, check length and replace if appropriate
      newWebhookResource = (changes.keys().any(function(x){x eq "webhook_resource_front"})) =>
		     changes.pick("$.webhook_resource_front")
		  |  config.pick("$.webhook_resource_front");
      status = ((newWebhookResource.length() > 0) && (newWebhookResource.length() < 101)) => 
 		   status | "Error: Webhook Resource";
      changes = ((newWebhookResource.length() > 0) && (newWebhookResource.length() < 101)) => 
  	            changes.put(["webhook_resource_front"], newWebhookResource) |
      	      	    changes.put(["webhook_resource_front"], config.pick("$.webhook_resource_front"));
      
      // webhook resource rear, check length and replace if appropriate
      newWebhookResource = (changes.keys().any(function(x){x eq "webhook_resource_rear"})) =>
		     changes.pick("$.webhook_resource_rear")
		  |  config.pick("$.webhook_resource_rear");
      status = ((newWebhookResource.length() > 0) && (newWebhookResource.length() < 101)) => 
 		   status | "Error: Webhook Resource";
      changes = ((newWebhookResource.length() > 0) && (newWebhookResource.length() < 101)) => 
  	            changes.put(["webhook_resource_rear"], newWebhookResource) |
      	      	    changes.put(["webhook_resource_rear"], config.pick("$.webhook_resource_rear"));
      
      // ringtone ack resource front, check length and replace if appropriate
      newRingtoneAckResource = (changes.keys().any(function(x){x eq "ringtone_ack_resource_front"})) =>
		     changes.pick("$.ringtone_ack_resource_front")
		  |  config.pick("$.ringtone_ack_resource_front");
      status = ((newRingtoneAckResource.length() > 0) && (newRingtoneAckResource.length() < 101)) => 
 		   status | "Error: Ringtone Ack Resource";
      changes = ((newRingtoneAckResource.length() > 0) && (newRingtoneAckResource.length() < 101)) => 
  	            changes.put(["ringtone_ack_resource_front"], newRingtoneAckResource) |
      	      	    changes.put(["ringtone_ack_resource_front"], config.pick("$.ringtone_ack_resource_front"));
      
      // ringtone ack resource rear, check length and replace if appropriate
      newRingtoneAckResource = (changes.keys().any(function(x){x eq "ringtone_ack_resource_rear"})) =>
		     changes.pick("$.ringtone_ack_resource_rear")
		  |  config.pick("$.ringtone_ack_resource_rear");
      status = ((newRingtoneAckResource.length() > 0) && (newRingtoneAckResource.length() < 101)) => 
 		   status | "Error: Ringtone Ack Resource";
      changes = ((newRingtoneAckResource.length() > 0) && (newRingtoneAckResource.length() < 101)) => 
  	            changes.put(["ringtone_ack_resource_rear"], newRingtoneAckResource) |
      	      	    changes.put(["ringtone_ack_resource_rear"], config.pick("$.ringtoneAck_resource_rear"));
      
      // webhook server, check length and replace if appropriate
      newWebhookServer = (changes.keys().any(function(x){x eq "webhook_server"})) =>
		     changes.pick("$.webhook_server")
		  |  config.pick("$.webhook_server");
      status = ((newWebhookServer.length() > 0) && (newWebhookServer.length() < 51)) => 
 		   status | "Error: Webhook Server";
      changes = ((newWebhookServer.length() > 0) && (newWebhookServer.length() < 51)) => 
  	            changes.put(["webhook_server"], newWebhookServer) |
      	      	    changes.put(["webhook_server"], config.pick("$.webhook_server"));
      
      // get poll time
      newPollTime = (changes.keys().any(function(x){x eq "poll_time"})) =>
		     changes.pick("$.poll_time")
		  |  config.pick("$.poll_time");
      // test for legal range from 1 - 65535
      // if illegal set status to error and leave value as is
      // if legal change value and leave status as OK
      status = ((newPollTime >= 1) && (newPollTime < 65536)) => status | "Error: Polltime";
      changes = ((newPollTime >= 1) && (newPollTime < 65536)) => 
		    changes.put(["poll_time"], math:int(newPollTime)) |
      	      	    changes.put(["poll_time"], math:int(config.pick("$.poll_time")));

      // get silent mode
      // front
      silent = (changes.keys().any(function(x){x eq "silent_front"})) =>
		     changes.pick("$.silent_front")
		  |  config.pick("$.silent_front");
      // test for legal values of true and false
      status = ((silent eq "true") || (silent eq "false")) => status | "Error: Silent";
      changes = ((silent eq "true") || (silent eq "false")) => 
		    changes.put(["silent_front"], silent.as("str")) |
		    changes.put(["silent_front"], config.pick("$.silent_front").as("str"));
		    
      // rear
      silent = (changes.keys().any(function(x){x eq "silent_rear"})) =>
		     changes.pick("$.silent_rear")
		  |  config.pick("$.silent_rear");
      // test for legal values of true and false
      status = ((silent eq "true") || (silent eq "false")) => status | "Error: Silent";
      changes = ((silent eq "true") || (silent eq "false")) => 
		    changes.put(["silent_rear"], silent.as("str")) |
		    changes.put(["silent_rear"], config.pick("$.silent_rear").as("str"));

      // get sms mode
      // front
      sms = (changes.keys().any(function(x){x eq "sms_front"})) =>
		     changes.pick("$.sms_front")
		  |  config.pick("$.sms_front");
      // test for legal values of true and false
      status = ((sms eq "true") || (sms eq "false")) => status | "Error: SMS";
      changes = ((sms eq "true") || (sms eq "false")) => 
		    changes.put(["sms_front"], sms.as("str")) |
		    changes.put(["sms_front"], config.pick("$.sms_front").as("str"));
		    
      // rear
      sms = (changes.keys().any(function(x){x eq "sms_rear"})) =>
		     changes.pick("$.sms_rear")
		  |  config.pick("$.sms_rear");
      // test for legal values of true and false
      status = ((sms eq "true") || (sms eq "false")) => status | "Error: SMS";
      changes = ((sms eq "true") || (sms eq "false")) => 
		    changes.put(["sms_rear"], sms.as("str")) |
		    changes.put(["sms_rear"], config.pick("$.sms_rear").as("str"));

      // get email mode
      // front
      email = (changes.keys().any(function(x){x eq "email_front"})) =>
		     changes.pick("$.email_front")
		  |  config.pick("$.email_front");
      // test for legal values of true and false
      status = ((email eq "true") || (email eq "false")) => status | "Error: EMAIL";
      changes = ((email eq "true") || (email eq "false")) => 
		    changes.put(["email_front"], email.as("str")) |
		    changes.put(["email_front"], config.pick("$.email_front").as("str"));
		    
      // rear
      email = (changes.keys().any(function(x){x eq "email_rear"})) =>
		     changes.pick("$.email_rear")
		  |  config.pick("$.email_rear");
      // test for legal values of true and false
      status = ((email eq "true") || (email eq "false")) => status | "Error: EMAIL";
      changes = ((email eq "true") || (email eq "false")) => 
		    changes.put(["email_rear"], email.as("str")) |
		    changes.put(["email_rear"], config.pick("$.email_rear").as("str"));

      // get volume front value
      newVolume = (changes.keys().any(function(x){x eq "volume_front"})) =>
		     changes.pick("$.volume_front")
		  |  config.pick("$.volume_front");
      // test for legal range from 0-99
      // if illegal set status to error and leave value as is
      // if legal change value and leave status as OK
      status = ((newVolume >= 0) && (newVolume < 100)) => status | "Error: Volume";
      changes = ((newVolume >= 0) && (newVolume < 100)) => 
		    changes.put(["volume_front"], math:int(newVolume)) |
      	      	    changes.put(["volume_front"], math:int(config.pick("$.volume_front")));

      // repeat process for rear volume
      newVolume = (changes.keys().any(function(x){x eq "volume_rear"})) =>
		     changes.pick("$.volume_rear")
		  |  config.pick("$.volume_rear");
      status = ((newVolume >= 0) && (newVolume < 100)) => status | "Error: Volume";
      changes = ((newVolume >= 0) && (newVolume < 100)) => 
		    changes.put(["volume_rear"], math:int(newVolume)) |
      		    changes.put(["volume_rear"], math:int(config.pick("$.volume_rear")));

      // deal with ringtone size
      // check for size greater than 0, but less than 4,194,304
      newSize = (changes.keys().any(function(x){x eq "ringtone_size_front"})) =>
	           changes.pick("$.ringtone_size_front")
		|  config.pick("$.ringtone_size_front");
      status = ((newSize >= 0) && (newSize < 4194304)) => status | "Error: Ringtone Size";
      changes = ((newSize >= 0) && (newSize < 4194304 )) => 
	    changes.put(["ringtone_size_front"], math:int(newSize)) |
	    changes.put(["ringtone_size_front"], math:int(config.pick("$.ringtone_size_front")));

      newSize = (changes.keys().any(function(x){x eq "ringtone_size_rear"})) =>
	           changes.pick("$.ringtone_size_rear")
		|  config.pick("$.ringtone_size_rear");
      status = ((newSize >= 0) && (newSize < 4194304)) => status | "Error: Ringtone Size";
      changes = ((newSize >= 0) && (newSize < 4194304 )) => 
	    changes.put(["ringtone_size_rear"], math:int(newSize)) |
	    changes.put(["ringtone_size_rear"], math:int(config.pick("$.ringtone_size_rear")));

      // if we changed a ringtone filename figure out what map entries need changing
      newRingtoneMap = (changes.keys().any(function(x){x eq "ringtone_name_front"})) =>
      		          newRingtone(changes.pick("$.ringtone_name_front"),
		    		      math:int(changes.pick("$.ringtone_size_front")),
				      "front") | "";
      changes = changes.put(newRingtoneMap);

      newRingtoneMap = (changes.keys().any(function(x){x eq "ringtone_name_rear"})) =>
      		          newRingtone(changes.pick("$.ringtone_name_rear"), 
		    		      math:int(changes.pick("$.ringtone_size_rear")),
				      "rear") | "";
      changes = changes.put(newRingtoneMap);

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      send_directive("status") with status = status;
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
    }
  }

  // this event is raised to indicate that a new doorbell ringtone
  // was successfully downloaded.  This sets ringtone_new_front = false
  rule myDoorbellGotFrontRingtone {
    select when myDoorbell gotFrontRingtone
    pre {
      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      changes = {"ringtone_new_front":"false"};

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      noop();
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
    }
  }

  // this event is raised to indicate that a new doorbell ringtone
  // was successfully downloaded.  This sets ringtone_new_rear = false
  rule myDoorbellGotRearRingtone {
    select when myDoorbell gotRearRingtone
    pre {
      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      changes = {"ringtone_new_rear":"false"};

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      noop();
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
    }
  }

  // this event is raised to initialize the doorbell state
  rule myDoorbellInit {
    select when myDoorbell initialize
    pre {
      // clear outstanding scheduled events
      eventID = (event:get_list().length() > 0) => event:delete(event:get_list().head().head())
            	      				   | "no Events";

      initVolume = 70;
      message = "Someone rang my #DOOR door on #TIME, wish they would go away!";

      payloadFront = {"_domain":"myDoorbell",
      		      "_type":"frontRing",
		      "_async":"true"};

      payloadRear  = {"_domain":"myDoorbell",
      		      "_type":"rearRing",
		      "_async":"true"};

      ackpayloadFront = {"_domain":"myDoorbell",
      		      "_type":"gotFrontRingtone",
		      "_async":"true"};

      ackpayloadRear  = {"_domain":"myDoorbell",
      		      "_type":"gotRearRingtone",
		      "_async":"true"};

      webhookResourceFront = '/sky/event/' + meta:eci();

      webhookResourceRear = '/sky/event/' + meta:eci();

      ringtoneResourceFront = '/sky/cloud/' + 
      			       meta:rid() + 
			       '/myDoorbellRingtoneChunk?door=front&_eci=' +
			       meta:eci();

      ringtoneResourceRear = '/sky/cloud/' + 
      			       meta:rid() + 
			       '/myDoorbellRingtoneChunk?door=rear&_eci=' +
			       meta:eci();

      ringtoneAckResourceFront = '/sky/event/' + meta:eci() + '/12345';

      ringtoneAckResourceRear = '/sky/event/' + meta:eci() + '/12345';

      initState = {"volume_front":initVolume,
      	           "volume_rear":initVolume,
		   "silent_front":"false",
		   "silent_rear":"false",
		   "email_front":"false",
		   "email_rear":"false",
		   "sms_front":"false",
		   "sms_rear":"false",
		   "webhook_server":"cs.kobj.net",
		   "webhook_resource_front":"#{webhookResourceFront}",
		   "webhook_resource_rear":"#{webhookResourceRear}",
		   "webhook_method":"POST",
		   "webhook_payload_rear":payloadRear.encode(),
		   "webhook_payload_front":payloadFront.encode(),
		   "webhook_http_headers":"Content-Type: application/json\r\n",
		   "poll_time":1,
		   "ringtone_new_front":"false",
		   "ringtone_new_rear":"false",
		   "ringtone_name_front":"",
		   "ringtone_name_rear":"",
		   "ringtone_resource_front":"#{ringtoneResourceFront}",
		   "ringtone_resource_rear":"#{ringtoneResourceRear}",
		   "ringtone_size_front":0,
		   "ringtone_size_rear":0,
		   "ringtone_ack_resource_front":"#{ringtoneAckResourceFront}",
		   "ringtone_ack_resource_rear":"#{ringtoneAckResourceRear}",
		   "ringtone_ack_method":"POST",
		   "ringtone_ack_payload_rear":ackpayloadRear.encode(),
		   "ringtone_ack_payload_front":ackpayloadFront.encode(),
		   "sms_email_message":"#{message}"
	          };
    }
    {
      noop();
    }
    fired {
      set ent:myDoorbellState initState;

      // these are app specific
      set ent:myDoorbellRingLog [];
      clear ent:myDoorbellRearRingCount;
      clear ent:myDoorbellFrontRingCount;
      clear ent:myDoorbellRingsToday;
    }
  }

  // this event is raised to indicate that the front doorbell was rung
  rule myFrontDoorbellRang {
    select when myDoorbell frontRing
    pre {
      // gather state
      currentState = ent:myDoorbellState;
      
      // pick out variables
      emailFront = currentState.pick("$.email_front");
      smsFront = currentState.pick("$.sms_front");
      message = currentState.pick("$.sms_email_message");

      todaysRings = ent:myDoorbellRingsToday;
      new_log_entry = {"time":0, "door":"front"}.map(insertTime);
      log_length = ent:myDoorbellRingLog.length();

      // if log has length 100, tail it to get the last 99 entries and then append the new
      // element
      new_log = (log_length == 100) => ent:myDoorbellRingLog.tail().append(new_log_entry) |
      	        ent:myDoorbellRingLog.append(new_log_entry);

      // replace time and door indicators with appropriate strings
      message = message.replace(re/#TIME/, time:strftime(time:now(), "%c"));
      message = message.replace(re/#DOOR/, "Front");
      // truncate the message so it can be sent via SMS
      sms_message = (message.length() > 110) => message.substr(0, 110) | message;
    }
    {
      noop();
    }
    fired {
      // if we are suppose to send an email, send it
      raise notification event status with
        priority = -1 and
	application = "myDoorbell" and 
        description = message  if (emailFront eq "true");

      // if we are suppose to send an sms, send it
      raise notification event status with
        priority = 2 and
	application = "myDoorbell" and 
        description = sms_message if (smsFront eq "true");

      set ent:myDoorbellRingLog new_log;
      ent:myDoorbellFrontRingCount += 1 from 1;
      ent:myDoorbellRingsToday += 1 from 1;
    }
  }

  // this event is raised to indicate the rear doorbell was rung
  rule myRearDoorbellRang {
    select when myDoorbell rearRing
    pre {
      // gather state
      currentState = ent:myDoorbellState;
      
      // pick out variables
      emailRear = currentState.pick("$.email_rear");
      smsRear = currentState.pick("$.sms_rear");
      message = currentState.pick("$.sms_email_message");

      log_time = time:now();
      new_log_entry = {"time":0, "door":"rear"}.map(insertTime);
      log_length = ent:myDoorbellRingLog.length();

      // if log has length 100 tail it to get the last 99 entries and then append the new
      // element
      new_log = (log_length == 100) => ent:myDoorbellRingLog.tail().append(new_log_entry) |
      	        ent:myDoorbellRingLog.append(new_log_entry);

      // replace time and door indicators with appropriate strings
      message = message.replace(re/#TIME/, time:strftime(time:now(), "%c"));
      message = message.replace(re/#DOOR/, "Rear");
      // truncate the message so it can be sent via SMS
      sms_message = (message.length() > 110) => message.substr(0, 110) | message;
    }
    {
      noop();
    }
    fired {
      // if we are suppose to send an email, send it
      raise notification event status with
        priority = -1 and
	application = "myDoorbell" and 
        description = message if (emailRear eq "true");

      // if we are suppose to send an sms, send it
      raise notification event status with
        priority = 2 and
	application = "myDoorbell" and 
        description = sms_message if (smsRear eq "true");

      set ent:myDoorbellRingLog new_log;
      ent:myDoorbellRearRingCount += 1 from 1;
      ent:myDoorbellRingsToday += 1 from 1;
    }
  }

  // this event is raised once each day at midnight to
  // clasify log data as not being on the current day
  rule myDoorbellDay {
    select when explicit myDoorbellNewDay
    pre {
    }
    {
      noop();
    }
    always {
      clear ent:myDoorbellRingsToday;
    }
  }


  // this event is raised by the action button on the web UI
  // the attributes are the form entries, check boxes, etc.
  rule myDoorbellActionRule {
    select when web submit "#myDoorbellActions"
    pre {
      // when the save action web button is depressed this event is invoked
      // the values on the web form are extraced
      volFront = event:attr("volumeFront");
      volRear = event:attr("volumeRear");
      message = event:attr("myDoorbellMessage");

      SMSFront = (event:attr("SMSFront") eq "SMS") => "true" | "false";
      SMSRear = (event:attr("SMSRear") eq "SMS") => "true" | "false";
      EmailFront = (event:attr("EmailFront") eq "Email") => "true" | "false";
      EmailRear = (event:attr("EmailRear") eq "Email") => "true" | "false";
      SilentFront = (event:attr("SilentFront") eq "Silent") => "true" | "false";
      SilentRear = (event:attr("SilentRear") eq "Silent") => "true" | "false";

      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      changes = {"volume_front":math:int(volFront),
      	         "volume_rear":math:int(volRear),
		 "sms_email_message":message,
		 "silent_front":"#{SilentFront}",
		 "silent_rear":"#{SilentRear}",
		 "email_front":"#{EmailFront}",
		 "email_rear":"#{EmailRear}",
		 "sms_front":"#{SMSFront}",
		 "sms_rear":"#{SMSRear}"
                };

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      CloudRain:hideSpinner();
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
    }
  }

  // this event is raised by the new ringtone seciton of the web UI
  rule myDoorbellFrontRingtone {
    select when web submit "#myDoorbellFrontRingtone"
    pre {
      // get ringtone name and size
      frontRingtone = event:attr("frontRingtone");
      frontRingtoneSize = dropbox_get_file_size(frontRingtone);

      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      changes = {"ringtone_new_front":"true",
		 "ringtone_name_front":frontRingtone,
      		 "ringtone_size_front":frontRingtoneSize
		};

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      CloudRain:hideSpinner();
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
      raise explicit event myDoorbellHome;
    }
  }

  // this event is raised in response to the rear ringtone button on the web UI
  rule myDoorbellRearRingtone {
    select when web submit "#myDoorbellRearRingtone"
    pre {
      // get ringtone name and size
      rearRingtone = event:attr("rearRingtone");
      rearRingtoneSize = dropbox_get_file_size(rearRingtone);

      // capture current doorbell state
      config = ent:myDoorbellState;

      // gather potential changes as a map
      changes = {"ringtone_new_rear":"true",
		 "ringtone_name_rear":rearRingtone,
      		 "ringtone_size_rear":rearRingtoneSize
		};

      // merge modifications with current state
      config = config.put(changes);
    }
    {
      CloudRain:hideSpinner();
    }
    fired {
      // save current state as state
      set ent:myDoorbellState config;
      raise explicit event myDoorbellHome;
    }
  }

  // Dropbox OAuth authentication / authorization rules
  rule get_request_token {
    select when web cloudAppSelected
    pre {
    }
    if(not authorized) then {
      http:post(dropbox_base_url + '/oauth/request_token') with
        body = {} and
        headers = {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'), 
                                                               keys:dropbox('app_secret'))
          	  } and
        autoraise = "request_token"
    }   
  }

  rule process_request_token {
    select when http post label "request_token"
    pre {
      eci = event:channel('id');
      tokens = decode_content(event:attr('content'));
      callback = 'http://' + meta:host() + '/sky/event/' + eci + '/12345/oauth/response/' + 
      	          meta:rid() + '/' + math:random(999999);
      url = "https://www.dropbox.com/1/oauth/authorize?oauth_token=" + tokens{'oauth_token'} + 
      	    "&oauth_callback=" + callback;
      dropbox_html = <<
      	          <div style="margin: 0px 0px 20px 20px">
		  <a href="#{url}" class="btn btn-large btn-primary">Click to Link to Dropbox<a>
		  </div>
		>>;
    }
    {
      CloudRain:createLoadPanel("Link to Dropbox", {}, dropbox_html);
    }
    always {
      set ent:request_token_secret tokens{'oauth_token_secret'};
      set ent:request_token tokens{'oauth_token'};
    }
  }

  rule get_access_token {
    select when oauth response
      if(not authorized) then {
        http:post(dropbox_base_url+"/oauth/access_token") with
          body = {} and
          headers = {"Authorization" : create_oauth_header_value(keys:dropbox('app_key'),
                                                           keys:dropbox('app_secret'),
                                   			   ent:request_token,
                                   			   ent:request_token_secret)
                    } and
        	      autoraise = "access_token"
      }   
  }

  rule process_access_token {
    select when http post label "access_token"
    pre {
      tokens = decode_content(event:attr('content'));
      url = "https://squaretag.com/app.html#!/app/#{meta:rid()}/show";
      js = <<
             <html>
	       <head>
  	         <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  		   <title></title>
  		   <META HTTP-EQUIV="Refresh" CONTENT="0;#{url}">
  		   <meta name="robots" content="noindex"/>
  		   <link rel="canonical" href="#{url}"/>
	       </head>
	       <body>
	         <p>You are being redirected to <a href="#{url}">#{url}</a></p>
		 <script type="text/javascript">
		   window.location = #{url};
		 </script>
	       </body>
	     </html>
	   >>;
    }
    send_raw("text/html")
      with content= js
    always {
      set ent:dropbox_uid tokens{'uid'};
      set ent:access_token_secret tokens{'oauth_token_secret'};
      set ent:access_token tokens{'oauth_token'};
    }
  }


  // this event is raised when the Home tab is selected
  rule myDoorbellHomeTab {
    select when web submit "#myDoorbellHomeBtn"
    pre {
    }
    {
      CloudRain:hideSpinner();
    }
    always {
      raise explicit event myDoorbellHome;
    }
  }


  // this event is raised when the Setup tab is selected
  rule myDoorbellSetupTab {
    select when web submit "#myDoorbellSetupBtn"
    pre {
    }
    {
      CloudRain:hideSpinner();
    }
    always {
      raise explicit event myDoorbellSetup;
    }
  }


  rule myDoorbellHome {
    select when explicit myDoorbellHome
    pre {
      // gather state
      currentState = ent:myDoorbellState;
      
      // pick out variables used in folowing html
      currentFrontRingtone = currentState.pick("$.ringtone_name_front");
      currentRearRingtone = currentState.pick("$.ringtone_name_rear");
      volumeFront = currentState.pick("$.volume_front");
      volumeRear = currentState.pick("$.volume_rear");
      silentFront = (currentState.pick("$.silent_front") eq "true") => "checked" | "";
      silentRear = (currentState.pick("$.silent_rear") eq "true") => "checked" | "";
      emailFront = (currentState.pick("$.email_front") eq "true") => "checked" | "";
      emailRear = (currentState.pick("$.email_rear") eq "true") => "checked" | "";
      smsFront = (currentState.pick("$.sms_front") eq "true") => "checked" | "";
      smsRear = (currentState.pick("$.sms_rear") eq "true") => "checked" | "";
      myDoorbellMessage = currentState.pick("$.sms_email_message");

      // calculate a few needful things
      totalRings = ent:myDoorbellFrontRingCount + ent:myDoorbellRearRingCount;
      log = ent:myDoorbellRingLog;
      list = dropbox_list_files();

      // generate html to display
      app_html = << 
        <head>
	  <style type="text/css">
	    .left {
	      text-align:left;
	      float:left;
	      clear:none;
	      width:50%;
	    }
	    .right {
	      text-align:right;
	      float:right;
	      clear:none;
	      width:50%;
	    }
	    .use-case-box {
	      border-radius:5%;
	      align:center;
	      height:500px;
	      border:solid 3px #777777;
	      padding:2pt;
	      margin:3pt;
	    }
	    .log-box {
	      border-radius:5%;
	      overflow:scroll;
	      padding:2pt 7pt 2pt 2pt;
	      font-size:12pt;
	      color:#000000;
	      background-color:#ffffff;
	      text-align:left;
	      border:solid 1px #777777;
	      height:278px;
    	      display:inline-block;
	    }
	    textarea {
	      border:solid 1px #777777;
	      width:190px; 
	      min-width:190px;
	      resize:none;
	    }
	    input[type="checkbox"] {
  	      margin: 0pt 0pt 3pt 0pt;
  	      line-height: normal;
	    }
	    .column-wrapper {
	      width:210px;
	      margin-left: auto;
	      margin-right: auto;
	    }
	    .table td {
	      border-top:none;
	      font-size:14pt;
	      text-align:center;
	    }
	    h2 {
	      text-align:center;
	    }
	    h3 {
	      margin-bottom:-2pt;
	      font-size:16pt;
	      text-align:center;
	    }
	    .volume-element-label {
	      margin-top:13pt;
	      margin-bottom:-1pt;
	      line-height:0pt;
	      font-size:14pt;
	      text-align:center;
	    }
	    .volume-label {
	      line-height:8pt;
	    }
	    .label {
	      font-weight:normal;
	      margin-bottom:12pt;
	      line-height:4pt;
	      font-size:14pt;
	      text-align:center;
	    }
	    .key {
	      border-radius:15%;
	      padding:2pt 2pt 2pt 2pt;
	      font-size:14pt;
	      color:#ffffff;
	      text-align:center;
	      border:solid 1px #777777;
	      height:20px;
	      width:50px;
    	      display:inline;
	      margin:0pt 5pt 2pt 5pt;
	    }
	    .btn-yellow { 
	      background-color:hsl(55, 85%, 44%) !important; 
	      background-repeat: repeat-x; 
	      filter: progid:DXImageTransform.Microsoft.gradient(startColorstr="#f2e768", 
	              endColorstr="#cfbf10"); 
	      background-image:-khtml-gradient(linear,left top,left bottom,from(#f2e768),
	                       to(#cfbf10)); 
	      background-image:-moz-linear-gradient(top, #f2e768, #cfbf10); 
	      background-image:-ms-linear-gradient(top, #f2e768, #cfbf10); 
	      background-image:-webkit-gradient(linear, left top, left bottom, 
	                       color-stop(0%, #f2e768), color-stop(100%, #cfbf10)); 
	      background-image:-webkit-linear-gradient(top, #f2e768, #cfbf10); 
	      background-image:-o-linear-gradient(top, #f2e768, #cfbf10); 
	      background-image: linear-gradient(#f2e768, #cfbf10); 
	      border-color: #cfbf10 #cfbf10 hsl(55, 85%, 38%); 
	      color: #333 !important; 
	      text-shadow: 0 1px 1px rgba(255, 255, 255, 0.39); 
	      -webkit-font-smoothing: antialiased; 
	    }
	    .btn-green { 
	      background-color: hsl(119, 84%, 26%) !important;
	      background-repeat: repeat-x; 
	      filter: progid:DXImageTransform.Microsoft.gradient(startColorstr="#16d712", 
	              endColorstr="#0c790a"); 
	      background-image: -khtml-gradient(linear, left top, left bottom, from(#16d712), 
	                  	to(#0c790a)); 
	      background-image: -moz-linear-gradient(top, #16d712, #0c790a); 
	      background-image: -ms-linear-gradient(top, #16d712, #0c790a); 
	      background-image: -webkit-gradient(linear, left top, left bottom, 
	                        color-stop(0%, #16d712), color-stop(100%, #0c790a)); 
	      background-image: -webkit-linear-gradient(top, #16d712, #0c790a); 
	      background-image: -o-linear-gradient(top, #16d712, #0c790a); 
	      background-image: linear-gradient(#16d712, #0c790a); 
	      border-color: #0c790a #0c790a hsl(119, 84%, 21%); 
	      color: #fff !important; 
	      text-shadow: 0 -1px 0 rgba(0, 0, 0, 0.33); 
	      -webkit-font-smoothing: antialiased; 
	    }
	    .btn-blue { 
	      background-color: hsl(236, 67%, 37%) !important; 
	      background-repeat: repeat-x; 
	      filter: progid:DXImageTransform.Microsoft.gradient(startColorstr="#4751da", 
	              endColorstr="#1f279d"); 
	      background-image: -khtml-gradient(linear, left top, left bottom, from(#4751da), 
	         		to(#1f279d)); 
	      background-image: -moz-linear-gradient(top, #4751da, #1f279d); 
	      background-image: -ms-linear-gradient(top, #4751da, #1f279d); 
	      background-image: -webkit-gradient(linear, left top, left bottom, 
	      			color-stop(0%, #4751da), color-stop(100%, #1f279d)); 
	      background-image: -webkit-linear-gradient(top, #4751da, #1f279d); 
	      background-image: -o-linear-gradient(top, #4751da, #1f279d); 
	      background-image: linear-gradient(#4751da, #1f279d); 
	      border-color: #1f279d #1f279d hsl(236, 67%, 32%); 
	      color: #fff !important; 
	      text-shadow: 0 -1px 0 rgba(0, 0, 0, 0.33); 
	      -webkit-font-smoothing: antialiased; 
	    }
	    .myRingtones {
	      width:200px;
	      min-width:200px;
	      border-radius:5%;
	      overflow:scroll;
	      padding:2pt 2pt 2pt 2pt;
	      font-size:12pt;
	      color:#000000;
	      background-color:#ffffff;
	      text-align:left;
	      border:solid 1px #777777;
	    }
	    #bottom-space {
	      margin-bottom:8pt;
	    }
	    #text-left {
	      text-align:left;
	    }
	    #text-right {
	      text-align:right;
	    }
	    #text-center {
	      text-align:center;
	    }
	    #front {
	      background-color:#00aa00;
	      float:left;
	    }
	    #rear {
	      background-color:#0000aa;
	      float:right;
	    }
	    .btn-large {
	      margin-left:10px;
	      margin-top:-20px;
	      margin-bottom:-20px;
	    }
	  </style>
	</head>	  
	<html>
	  <div class="container">
	  <form id="myDoorbellSetupBtn">
  	    <button class="btn-large" type="submit">Setup</button>
	  </form>
            <div class="row-fluid">
	      <!-- left column, Uses -->
	      <div class="span4">
	        <div class="use-case-box">
	          <h2>Use</h2>
		  <h3>myDoorbell Rang</h3>
		  <div align="center">
		    <div class="column-wrapper">
		      <div class="key" id="front">Front</div>
		      <div class="key" id="rear">Rear</div>
		    </div>
		    <div class="log-box">
		      #{log2html(log.reverse())}
      	            </div>
      		  </div>
      		  <div class="column-wrapper">
		    <table class="table">
		      <tr>
		        <td id="text-left">Today's Total</td>
		        <td id="text-right">#{ent:myDoorbellRingsToday}</td>
		      </tr>
		      <tr>
		        <td id="text-left">All Time Total</td>
		        <td id="text-right">#{totalRings}</td>
		      </tr>
      		    </table>
		  </div>
		</div>
	      </div>

	      <!-- center column, Actions -->
	      <div class="span4">
	        <div class="use-case-box">
	          <h2>Actions</h2>
		  <h3 id="bottom-space">myDoorbell Volume</h3>

		  <form id="myDoorbellActions">
		    <!-- table implements front volume control -->
		    <div class="column-wrapper">
		      <p class="volume-element-label">Front</p>
		      <div class="volume-label right">High</div>
		      <div class="volume-label left">Low</div>
	      	        <input type="range" min="0" max="99" name="volumeFront" 
		               value="#{volumeFront}">
		    </div>

		    <!-- table implements rear volume control -->
		    <div class="column-wrapper">
		      <p class="volume-element-label">Rear</p>
		      <div class="volume-label right">High</div>
		      <div class="volume-label left">Low</div>
		      <!-- form end is well down the page -->
	      	        <input type="range" min="0" max="99" name="volumeRear" 
		               value="#{volumeRear}">
		    </div>

		    <h3>myDoorbell Rings</h3>
		    <div class="column-wrapper" align="center">
		      <table class="table table-condensed">
		        <tr>
		          <td></td>
		          <td>Front</td>
		          <td>Rear</td>
		        </tr>
		        <!-- this row for text message element -->
		        <tr>
		          <td id="text-left">Text Me</td>
		          <td>
			    <input type="checkbox" name="SMSFront" value="SMS" #{smsFront}>
			  </td>
			  <td>
			    <input type="checkbox" name="SMSRear" value="SMS" #{smsRear}>
			  </td>
		        </tr>
		        <!-- this row for email message element -->
		        <tr>
		          <td id="text-left">Email Me</td>
		          <td>
			  <input type="checkbox" name="EmailFront" value="Email" #{emailFront}><br>
			  </td>
			  <td>
			    <input type="checkbox" name="EmailRear" value="Email" #{emailRear}><br>
			  </td>
		        </tr>
		        <!-- this row for silencing element -->
		        <tr>
		          <td id="text-left">Be Silent</td>
			  <td>
			    <input type="checkbox" name="SilentFront" value="Silent" #{silentFront}>
			  </td>
			  <td>
			    <input type="checkbox" name="SilentRear" value="Silent" #{silentRear}>
			  </td>
		        </tr>
		      </table>

		      <p class="label">Message to Text \/ Email</p>
		      <textarea maxlength="100" name="myDoorbellMessage">#{myDoorbellMessage}
		      </textarea>
		      <button class="btn-medium btn-yellow" type="submit"><b>Save Actions</b>
		      </button>

		    </div>
		  </form>
		</div>
	      </div>

	      <!-- right column, Ringtones -->
	      <div class="span4">
	        <div class="use-case-box">
	          <h2>Ringtones</h2>
	          <h3>myDoorbell Plays</h3>
		  <div class="column-wrapper">
		    <table class="table table-condensed">
		      <tr>
		        <td id="text-left">Front:</td>
		        <td id="text-left">#{currentFrontRingtone}</td>
		      </tr>
		      <tr>
		        <td id="text-left">Rear:</td>
		        <td id="text-left">#{currentRearRingtone}</td>
		      </tr>
		    </table>
		  </div>
		  <div align="center">
		    <p class="label">Choose Front Ringtone</p>
		    <form id="myDoorbellFrontRingtone">
		      <select class="myRingtones" size="4" name="frontRingtone">
  			#{file_list2html(list)}
		      </select>
		      <div> 
		        <button class="btn-medium btn-green" name="frontRingtone" 
		      	        type="submit" value="Front"><b>Select Front</b></button>
		      </div>
		    </form>
		  </div>
		  <div align="center">
		    <p class="label">Choose Rear Ringtone</p>
		    <form id="myDoorbellRearRingtone">
		      <select class="myRingtones" size="4" name="rearRingtone">
  			#{file_list2html(list)}
		      </select> 
		      <div>
		        <button class="btn-medium btn-blue" name="rearRingtone" 
		      	        type="submit" value="Rear"><b>Select Rear</b></button>
		      </div>
		    </form>
		  </div>
		</div>
	      </div>
	    </div	<!-- end "row" -->
	  </div>	<!-- end "container" -->
        </html>
      >>;
    }
    {
      CloudRain:hideSpinner();
      CloudRain:createLoadPanel("myDoorbell Dashboard", {}, app_html);
      CloudRain:skyWatchSubmit("#myDoorbellActions", meta:eci());
      CloudRain:skyWatchSubmit("#myDoorbellFrontRingtone", meta:eci());
      CloudRain:skyWatchSubmit("#myDoorbellRearRingtone", meta:eci());
      CloudRain:skyWatchSubmit("#myDoorbellSetupBtn", meta:eci());
    }
    fired {
      schedule explicit event 'myDoorbellNewDay' repeat '0 0 * * *' if (event:get_list().length() == 0);
    }
  }


  rule myDoorbellSetup {
    select when explicit myDoorbellSetup
    pre {
      // generate html to display
      setup_html = << 
        <head>
	  <style type="text/css">
	    .use-case-box {
	      border-radius:1%;
	      align:center;
	      height:500px;
	      border:solid 3px #777777;
	      padding:2pt;
	      margin:3pt;
	    }
	    .setup-wrapper {
	      width:600px;
	      margin-left: auto;
	      margin-right: auto;
	    }
	    .table td {
	      border-top:none;
	      font-size:14pt;
	      text-align:center;
	    }
	    h2 {
	      text-align:center;
	    }
	    #text-left {
	      text-align:left;
	    }
	    #text-right {
	      text-align:right;
	    }
	    .btn-large {
	      margin-left:10px;
	      margin-top:-20px;
	      margin-bottom:-20px;
	    }
	  </style>
	</head>	  
	<html>
	  <div class="container">
	    <form id="myDoorbellHomeBtn">
  	      <button class="btn-large" type="submit">Home</button>
	    </form>
            <div class="row-fluid">
	      <!-- one center column -->
	      <div class="span12"></div>
	        <div class="use-case-box">
	          <h2>myDoorbell Setup Information</h2>
      		  <div class="setup-wrapper">
		    <table class="table">
		      <tr>
		        <td id="text-left">Application ID:</td>
		        <td id="text-left">#{ent:myDoorbellRID}</td>
		      </tr>
		      <tr>
		        <td id="text-left">Application Key:</td>
		        <td id="text-left">#{ent:myDoorbellECI}</td>
		      </tr>
      		    </table>
		  </div>
		</div>
	      </div>
	    </div	<!-- end "row" -->
	  </div>	<!-- end "container" -->
        </html>
      >>;
    }
    {
      CloudRain:hideSpinner();
      CloudRain:createLoadPanel("myDoorbell Dashboard", {}, setup_html);
      CloudRain:skyWatchSubmit("#myDoorbellHomeBtn", meta:eci());
    }
  }


  // this event is raised when the web UI is opened or refreshed
  rule DoorbellWelcome {
    select when web cloudAppSelected
    pre {
      eci = meta:eci();
      rid = meta:rid();
    }
    {
      CloudRain:hideSpinner();
    }
    always {
      set ent:myDoorbellECI eci;
      set ent:myDoorbellRID rid;
      raise explicit event myDoorbellHome if (authorized);
    }
  }
}
