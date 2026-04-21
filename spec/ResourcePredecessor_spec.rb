#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = ResourcePredecessor_spec.rb -- The TaskJuggler III Project Management Software
#
# Unit tests for ResourceScenario#predecessor_on_slot, which identifies the
# task that held a resource in the most recent booked slot before a given
# slot index. Used by the PERT end-date variance propagation to detect
# tasks whose start is effectively determined by a preceding booking rather
# than by an explicit dependency.
#

require 'rubygems'

require 'taskjuggler/Task'
require 'taskjuggler/ResourceScenario'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
end

class TaskJuggler

  describe ResourceScenario, '#predecessor_on_slot' do

    # A minimal stub that just needs to respond to is_a?(Task).
    def make_task(name)
      t = Task.allocate
      t.instance_variable_set(:@fullId, name)
      def t.to_s; @fullId; end
      t
    end

    # Construct a ResourceScenario with only the scoreboard field set. This
    # bypasses the heavyweight initialize, which requires a fully wired
    # Project/Resource graph. The method under test only reads @scoreboard.
    def resource_with_scoreboard(scoreboard)
      rs = ResourceScenario.allocate
      rs.instance_variable_set(:@scoreboard, scoreboard)
      rs
    end

    # Scoreboard slot encodings used in these tests:
    #   nil       — available working-time slot (resource idle and bookable)
    #   Task      — booked to that task
    #   2         — off-shift (bit 1 set)
    #   4..0x3C   — leave (bits 2-5)
    OFF_SHIFT = 2
    LEAVE     = 4  # a leave type index encoded at bits 2-5 (typeIdx 1 << 2)

    it 'returns nil when the scoreboard has not been initialized' do
      rs = resource_with_scoreboard(nil)
      rs.predecessor_on_slot(10).should be_nil
    end

    it 'returns nil when slot index is 0' do
      rs = resource_with_scoreboard([nil, nil, nil])
      rs.predecessor_on_slot(0).should be_nil
    end

    it 'returns the task booked in the immediately preceding slot' do
      t = make_task('A')
      rs = resource_with_scoreboard([t, t, t, nil])
      rs.predecessor_on_slot(3).should equal(t)
    end

    it 'returns nil when the preceding slot is idle working-time (nil)' do
      t = make_task('A')
      rs = resource_with_scoreboard([t, nil, nil])
      # Slot 2 is the query point, slot 1 is nil (idle, bookable).
      # The resource was genuinely idle, so no tight predecessor.
      rs.predecessor_on_slot(2).should be_nil
    end

    it 'skips non-working slots (off-shift) and returns the earlier task' do
      t = make_task('A')
      # Pattern: A, off-shift, off-shift, [query at 3]
      # Off-shift is non-voluntary idleness (e.g. nights/weekends) and must
      # not terminate the search.
      rs = resource_with_scoreboard([t, OFF_SHIFT, OFF_SHIFT, nil])
      rs.predecessor_on_slot(3).should equal(t)
    end

    it 'skips leave slots and returns the earlier task' do
      t = make_task('A')
      rs = resource_with_scoreboard([t, LEAVE, LEAVE, nil])
      rs.predecessor_on_slot(3).should equal(t)
    end

    it 'stops at the first idle working-time slot even if a task is further back' do
      t = make_task('A')
      # Pattern: A, idle, idle, [query]
      # The idle working-time slots break the chain — the resource had
      # availability before the query point, so no tight predecessor.
      rs = resource_with_scoreboard([t, nil, nil, nil])
      rs.predecessor_on_slot(3).should be_nil
    end

    it 'returns the most recent of several tasks when they are adjacent' do
      a = make_task('A')
      b = make_task('B')
      rs = resource_with_scoreboard([a, a, b, b, nil])
      rs.predecessor_on_slot(4).should equal(b)
    end

    it 'skips over self-bookings of a fragmented task and returns the earlier predecessor' do
      a = make_task('A')
      t = make_task('T')
      # Task T is fragmented: it holds slots 2 and 4; query is at slot 5
      # (T's second segment ends at 4). The true resource-induced
      # predecessor is A, not T itself.
      rs = resource_with_scoreboard([a, a, t, OFF_SHIFT, t, nil])
      rs.predecessor_on_slot(5, t).should equal(a)
    end

    it 'returns nil when only non-working slots and no booked task exist' do
      rs = resource_with_scoreboard([OFF_SHIFT, OFF_SHIFT, LEAVE])
      rs.predecessor_on_slot(3).should be_nil
    end

    it 'returns nil past the beginning of the scoreboard' do
      t = make_task('A')
      rs = resource_with_scoreboard([OFF_SHIFT, OFF_SHIFT, OFF_SHIFT])
      rs.predecessor_on_slot(3).should be_nil
    end

  end

end
