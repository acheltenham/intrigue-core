module Intrigue
module Machine
  class ExternalDiscoveryLightActive < Intrigue::Machine::Base

    def self.metadata
      {
        :name => "external_discovery_light_active",
        :pretty_name => "External Discovery - Light, Active",
        :passive => false,
        :user_selectable => true,
        :authors => ["jcran"],
        :description => "This machine performs a light active enumeration. Start with a Domain or NetBlock."
      }
    end

    # Recurse should receive a fully enriched object from the creator task
    def self.recurse(entity, task_result)

      project = entity.project
      seed_list = project.seeds.map{|s| s.name }.join(",")

      ### 
      # Don't go any further unless we're scoped! 
      ### 
      traversable = false # default to no traverse
      # This is a little trixy, allows for runtime scoping since we're dynamically checking
      traversable = true if entity.scoped? && !entity.hidden # true if we're scoped and not hidden      
      # LOG THE CHOICE
      return unless traversable 
      ###
      #  End scoping madness 
      ###

      if entity.type_string == "AwsS3Bucket"
        
        # test out a put file 
        start_recursive_task(task_result, "aws_s3_put_file", entity)

      elsif entity.type_string == "AwsRegion" 
        ## KINDA HAXXXY... TODO (remove & build a separate machine for these collections?)

        # test out a put file 
        start_recursive_task(task_result, "import/aws_ipv4_ranges", entity)

      elsif entity.type_string == "Domain"

        # get the nameservers
        start_recursive_task(task_result,"enumerate_nameservers", entity)

        # try an nsec walk
        start_recursive_task(task_result,"dns_nsec_walk", entity ,[], true)

        # attempt a zone transfer
        start_recursive_task(task_result,"dns_transfer_zone", entity, [], true)

        # check certificate records
        start_recursive_task(task_result,"search_crt", entity,[
          {"name" => "extract_pattern", "value" => seed_list }])

        # check certspotter for more certificates
        start_recursive_task(task_result,"search_certspotter", entity,[
          {"name" => "extract_pattern", "value" => seed_list }])

        # search sonar results
        start_recursive_task(task_result,"dns_search_sonar",entity, [], true)

        # threatcrowd 
        start_recursive_task(task_result,"search_threatcrowd", entity,[], true)

        # bruteforce email addresses
        start_recursive_task(task_result,"email_brute_gmail_glxu",entity,[], true)

        # quick spf recurse, creating new (unscoped) domains 
        start_recursive_task(task_result,"dns_recurse_spf",entity, [])

        # run dns-morph
        start_recursive_task(task_result,"dns_morph", entity,[])

        # quick subdomain bruteforce
        #start_recursive_task(task_result,"dns_brute_sub",entity,[
        #  {"name" => "brute_alphanumeric_size", "value" => 1 }], true)

        start_recursive_task(task_result,"saas_google_groups_check",entity,[])
        
        #start_recursive_task(task_result,"saas_trello_check",entity,[])
        start_recursive_task(task_result,"saas_jira_check",entity,[])

        # search greyhat warfare
        start_recursive_task(task_result,"search_grayhat_warfare",entity, [], true)

        # S3 bruting based on domain name
       #generated_names = [
       #   "#{entity.name.split(".").join("")}",
       #   "#{entity.name.split(".").join("-")}",
       #   "#{entity.name.split(".").join("_")}",
       #   "#{entity.name.split(".")[0...-1].join(".")}",
       #   "#{entity.name.split(".")[0...-1].join("")}",
       #   "#{entity.name.split(".")[0...-1].join("_")}",
       #   "#{entity.name.split(".")[0...-1].join("-")}",
       #   "#{entity.name.gsub(" ","")}"
       # ]

       # start_recursive_task(task_result,"aws_s3_brute",entity,[
       #   {"name" => "use_creds", "value" => true},
       #   {"name" => "additional_buckets", "value" => generated_names.join(",")}])
        
        if project.get_option("authorized")
          task_result.log_good "Project authorized, so searching hunter.io!"
          start_recursive_task(task_result,"search_hunter_io",entity,[])
        end

      elsif entity.type_string == "DnsRecord"

        #start_recursive_task(task_result,"dns_brute_sub",entity)

      elsif entity.type_string == "EmailAddress"

        start_recursive_task(task_result,"search_have_i_been_pwned",entity,[
          {"name" => "only_sensitive", "value" => true }])
  
        start_recursive_task(task_result,"saas_google_calendar_check",entity,[])

      elsif entity.type_string == "GithubAccount"

        start_recursive_task(task_result,"gitrob", entity, [])

      elsif entity.type_string == "IpAddress"
      
        # Prevent us from re-scanning services
        unless entity.created_by?("masscan_scan")
  
          ### search for netblocks
          start_recursive_task(task_result,"whois_lookup",entity, [])

          # use shodan to "scan" and create ports 
          start_recursive_task(task_result,"search_shodan",entity, [])

          # and we might as well scan to cover any new info
          start_recursive_task(task_result,"nmap_scan",entity, [])
        end

      elsif entity.type_string == "Nameserver"

        start_recursive_task(task_result,"security_trails_nameserver_search",entity, [], true)

      elsif entity.type_string == "NetBlock"

        transferred = entity.get_detail("transferred")

        scannable = entity.scoped && !transferred

        task_result.log "#{entity.name} Enriched: #{entity.enriched}"
        task_result.log "#{entity.name} Scoped: #{entity.scoped}"
        task_result.log "#{entity.name} Transferred: #{transferred}"
        task_result.log "#{entity.name} Scannable: #{scannable}"

        # Make sure it's owned by the org, and if it is, scan it. also skip ipv6/
        if scannable

          # 17185 - vxworks
          # https://duo.com/decipher/mapping-the-internet-whos-who-part-three 

          start_recursive_task(task_result,"masscan_scan",entity,[
            {"name"=> "tcp_ports", "value" => "21,23,35,22,2222,5000,502,503,80,443,81,4786,8080,8081," + 
              "8443,3389,1883,8883,6379,6443,8032,9200,9201,9300,9301,9091,9092,9094,2181,2888,3888,5900," + 
              "5901,7001,27017,27018,27019,8278,8291,53413,9000,11994"},
            {"name"=>"udp_ports", "value" => "123,161,1900,17185"}])

        else
          task_result.log "Cowardly refusing to scan this netblock: #{entity}.. it's not scannable!"
        end
      
      elsif entity.type_string == "NetworkService"

        #if entity.get_detail("service") == "RDP"
        #  start_recursive_task(task_result,"rdpscan_scan",entity, [], true)
        #end

      elsif entity.type_string == "Organization"

        ### search for netblocks
        start_recursive_task(task_result,"whois_lookup",entity, [])

        # search bgp data for netblocks
        start_recursive_task(task_result,"search_bgp",entity, [], true)

        # search greyhat warfare
        start_recursive_task(task_result,"search_grayhat_warfare",entity, [], true)

        # Search for jira accounts
        start_recursive_task(task_result,"saas_jira_check",entity)

        # Search for other accounts with this name
        start_recursive_task(task_result,"web_account_check",entity)

        # Search for trello accounts - currently requires browser
        #start_recursive_task(task_result,"saas_trello_check",entity)

        ### search for github - too noisy? 
        #start_recursive_task(task_result,"search_github",entity, [], true)

        ### AWS_S3_brute the name
        # S3!
        generated_names = [
          "#{entity.name.gsub(" ","")}",
          "#{entity.name.gsub(" ","-")}",
          "#{entity.name.gsub(" ","_")}"
        ]

        start_recursive_task(task_result,"aws_s3_brute",entity,[
          {"name" => "additional_buckets", "value" => generated_names.join(",")}])

      elsif entity.type_string == "Uri"

        #puts "Working on URI #{entity.name}!"

        # wordpress specific checks
        if entity.get_detail("fingerprint")

          if entity.get_detail("fingerprint").any?{|v| v['product'] =~ /Wordpress/i }
            puts "Checking Wordpress specifics on #{entity.name}!"
            start_recursive_task(task_result,"wordpress_enumerate_users",entity, [])
            start_recursive_task(task_result,"wordpress_enumerate_plugins",entity, [])
          end

          if entity.get_detail("fingerprint").any?{|v| v['product'] =~ /GlobalProtect/ }
            puts "Checking GlobalProtect specifics on #{entity.name}!"
            start_recursive_task(task_result,"vuln/globalprotect_check",entity, [])
          end

          # Hold on this for now, memory leak?
          #if entity.get_detail("fingerprint").any?{|v| v['vendor'] == "Apache" && v["product"] == "HTTP Server" }
          #  start_recursive_task(task_result,"apache_server_status_parser",entity, [])
          #end

        end

        ## Grab the SSL Certificate
        start_recursive_task(task_result,"uri_gather_ssl_certificate",entity, []) if entity.name =~ /^https/

        # Check for exploitable URIs, but don't recurse on things we've already found
        #unless (entity.created_by?("uri_brute_focused_content") || entity.created_by?("uri_spider") )
        start_recursive_task(task_result,"uri_brute_focused_content", entity)
        #end
        
        if entity.name =~ (ipv4_regex || ipv6_regex)
          puts "Cowardly refusing to check for subdomain hijack, #{entity.name} looks like an access-by-ip uri"
        else 
          start_recursive_task(task_result,"uri_check_subdomain_hijack",entity, [])
        end

        # if we're going deeper 
        if project.get_option("authorized")
          task_result.log_good "Project authorized, so spidering URI!"
          unless entity.created_by?("uri_spider")
            # Super-lite spider, looking for metadata
            start_recursive_task(task_result,"uri_spider",entity,[
              {"name" => "max_pages", "value" => 100 },
              {"name" => "extract_dns_records", "value" => true }
            ])
          end
        else 
          task_result.log_good "Project not authorized, not spidering URI!"
          task_result.log_good "Project Options: #{project.options}"
        end

      else
        task_result.log "No actions for entity: #{entity.type}##{entity.name}"
        return
      end
    end

end
end
end
