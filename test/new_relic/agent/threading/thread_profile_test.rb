# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profile'
require 'new_relic/agent/threading/threaded_test_case'
require 'new_relic/agent/threading/thread_profiling_client_test'

if NewRelic::Agent::Commands::ThreadProfiler.is_supported?

  module NewRelic::Agent::Threading
    class ThreadProfileTest < ThreadedTestCase
      include ThreadProfilingClientTests

      def setup
        super

        @single_trace = [
          "irb.rb:69:in `catch'",
          "irb.rb:69:in `start'",
          "irb:12:in `<main>'"
        ]

        @profile = ThreadProfile.new(create_agent_command)

        # Run the worker_loop for the thread profile based on two iterations
        # This takes time fussiness out of the equation and keeps the tests stable
        @profile.instance_variable_set(:@worker_loop, NewRelic::Agent::WorkerLoop.new(:limit => 2))
      end

      def target_for_shared_client_tests
        @profile
      end

      def test_finished
        freeze_time
        @profile = ThreadProfile.new(create_agent_command('duration' => 7.0))
        assert !@profile.finished?

        advance_time(5.0)
        assert !@profile.finished?

        advance_time(5.0)
        assert @profile.finished?
      end

      def test_prune_tree
        @profile.aggregate(@single_trace, :request)

        @profile.truncate_to_node_count!(1)

        assert_equal 0, @profile.traces[:request].children.first.children.size
      end

      def test_prune_keeps_highest_counts
        @profile.aggregate(@single_trace, :request)
        @profile.aggregate(@single_trace, :other)
        @profile.aggregate(@single_trace, :other)

        @profile.truncate_to_node_count!(1)

        assert_empty @profile.traces[:request]
        assert_equal 1, @profile.traces[:other].children.size
        assert_equal [], @profile.traces[:other].children.first.children
      end

      def test_prune_keeps_highest_count_then_depths
        @profile.aggregate(@single_trace, :request)
        @profile.aggregate(@single_trace, :other)

        @profile.truncate_to_node_count!(2)

        assert_equal 1, @profile.traces[:request].children.size
        assert_equal 1, @profile.traces[:other].children.size
        assert_equal [], @profile.traces[:request].children.first.children
        assert_equal [], @profile.traces[:other].children.first.children
      end

      def build_well_known_trace
        trace = ["thread_profiler.py:1:in `<module>'"]
        10.times { @profile.aggregate(trace, :other) }

        trace = [
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:489:in `__bootstrap'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:512:in `__bootstrap_inner'",
          "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:480:in `run'",
          "thread_profiler.py:76:in `_profiler_loop'",
          "thread_profiler.py:103:in `_run_profiler'",
          "thread_profiler.py:165:in `collect_thread_stacks'"]
          10.times { @profile.aggregate(trace, :agent) }
      end

      WELL_KNOWN_TRACE_ENCODED = "eJy9klFPwjAUhf/LfW7WDQTUGBPUiYkGdAxelqXZRpGGrm1uS8xi/O924JQX\n9Un7dm77ndN7c19hlt7FCZxnWQZug7xYMYN6LSTHwDRA4KLWq53kl0CinEQh\nCUmW5zmBJH5axPPUk16MJ/E0/cGk0lLyyrGPS+uKamu943DQeX5HMtypz5In\nwv6vRCeZ1NoAGQ2PCDpvrOM1fRAlFtjQWyxq/qJxa+lj4zZaBeuuQpccrdDK\n0l4wolKU1OxftOoQLNTzIdL/EcjJafjnQYyVWjvrsDBMKNVOZBD1/jO27fPs\naBG+DoGr8fX9JJktpjftVry9A9unzGo=\n"

      def test_to_collector_array
        build_well_known_trace
        @profile.instance_variable_set(:@profile_id, "-1")
        @profile.stubs(:created_at).returns(1350403938892.524)
        @profile.stubs(:last_aggregated_at).returns(1350403939904.375)
        @profile.instance_variable_set(:@poll_count, 10)
        @profile.instance_variable_set(:@sample_count, 2)

        expected = [[
          -1,
          1350403938892.524,
          1350403939904.375,
          10,
          WELL_KNOWN_TRACE_ENCODED,
          2,
          0
        ]]

        marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
        assert_equal expected, @profile.to_collector_array(marshaller.default_encoder)
      end

      def test_to_collector_array_with_bad_values
        build_well_known_trace
        @profile.instance_variable_set(:@profile_id, "-1")
        @profile.stubs(:created_at).returns('')
        @profile.stubs(:last_aggregated_at).returns(nil)
        @profile.instance_variable_set(:@poll_count, Rational(10, 1))
        @profile.instance_variable_set(:@sample_count, nil)

        expected = [[
          -1,
          0.0,
          0.0,
          10,
          WELL_KNOWN_TRACE_ENCODED,
          0,
          0
        ]]

        marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
        assert_equal expected, @profile.to_collector_array(marshaller.default_encoder)
      end

      def test_aggregate_should_increment_only_sample_count
        sample_count = @profile.sample_count
        failure_count = @profile.failure_count
        @profile.aggregate(@single_trace, :request)

        assert_equal sample_count + 1, @profile.sample_count
        assert_equal failure_count, @profile.failure_count
      end

      def test_aggregate_increments_only_the_failure_count_with_nil_backtrace
        sample_count = @profile.sample_count
        failure_count = @profile.failure_count
        @profile.aggregate(nil, :request)

        assert_equal sample_count, @profile.sample_count
        assert_equal failure_count + 1, @profile.failure_count
      end

      def test_aggregate_updates_created_at_timestamp
        expected = freeze_time
        @profile = ThreadProfile.new(create_agent_command)

        @profile.aggregate(@single_trace, :request)
        t0 = @profile.created_at

        advance_time(5.0)
        @profile.aggregate(@single_trace, :request)

        assert_equal expected, t0
        assert_equal expected, @profile.created_at
      end

      def test_aggregate_updates_last_aggregated_at_timestamp
        expected = freeze_time
        @profile.aggregate(@single_trace, :request)
        t0 = @profile.last_aggregated_at

        advance_time(5.0)
        @profile.aggregate(@single_trace, :request)

        assert_equal expected, t0
        assert_equal expected + 5.0, @profile.last_aggregated_at
      end
    end

  end
end