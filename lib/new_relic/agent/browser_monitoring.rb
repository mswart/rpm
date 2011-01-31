module NewRelic
  module Agent
    module BrowserMonitoring
      def browser_instrumentation_header(options={})
        
        browser_key = NewRelic::Agent.instance.browser_monitoring_key
        
        return "" if browser_key.nil?

        shard = NewRelic::Agent.instance.shard
        application_id = NewRelic::Agent.instance.application_id
        browser_apdex = NewRelic::Agent.instance.browser_apdex
        beacon = NewRelic::Agent.instance.beacon
        episodes_file_path = NewRelic::Agent.instance.episodes_file_path
        transaction_name = Thread::current[:newrelic_scope_name] 
        
        http_part = ((episodes_file_path == "localhost:3000/javascripts") ? "http:" : "https:")
        file = "\"#{http_part}//#{episodes_file_path}/episodes_1.js\""
        
  <<-eos
  <!-- generated by the New Relic agent -->
  <script src=#{file} type="text/javascript"></script>
  <script type="text/javascript" charset="utf-8">
    if (EPISODES.isCompatible) {
      EPISODES.setBeacon("#{beacon}");
      EPISODES.setLicenseKey("#{browser_key}");
      EPISODES.setShard("#{shard}");
      EPISODES.setApplicationID("#{application_id}");
      EPISODES.setApdexT("#{browser_apdex}");
      EPISODES.setTransactionName("#{transaction_name}");
    }
  </script>
  eos
      end
      
      def browser_instrumentation_footer(options={})
        
        return "" if NewRelic::Agent.instance.browser_monitoring_key.nil?
        
        #this is a total hack
        begin_time = (Thread.current[:started_on].to_f * 1000).round
        frame = Thread.current[:newrelic_metric_frame]

        if frame
          end_time = (frame.start.to_f * 1000).round
        else
          #this is a total hack
          end_time = begin_time + 250
        end
 
  <<-eos
  <!-- generated by the New Relic agent -->
  <script type="text/javascript" charset="utf-8">
    if (EPISODES.isCompatible) {
      window.postMessage("EPISODES:mark:qstart:#{begin_time}", "*");
      window.postMessage("EPISODES:mark:qend:#{end_time}", "*");
      window.postMessage("EPISODES:measure:qtime:qstart:qend", "*");
      window.postMessage("EPISODES:mark:appstart:#{begin_time}", "*");
      window.postMessage("EPISODES:mark:append:#{(Time.now.to_f * 1000).round}", "*");
      window.postMessage("EPISODES:measure:apptime:appstart:append", "*");
    }
  </script>
  eos
      end
    end
  end
end