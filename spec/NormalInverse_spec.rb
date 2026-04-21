#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = NormalInverse_spec.rb -- The TaskJuggler III Project Management Software
#

require 'rubygems'

require 'taskjuggler/NormalInverse'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
end

class TaskJuggler

  describe NormalInverse do

    # Φ(k) tabulated values. Reference: Abramowitz & Stegun, Table 26.1.
    # Moro's approximation delivers better than ~3e-9 in the central region
    # and better than ~1e-7 in the tails; we test against conservative
    # bounds that leave headroom.
    CENTRAL_TOL = 1e-8
    TAIL_TOL    = 1e-7

    describe '.ppf' do

      it 'returns 0 for p = 0.5 exactly' do
        NormalInverse.ppf(0.5).should == 0.0
      end

      it 'returns k = 1 for p = Φ(1)' do
        # Φ(1) = 0.8413447460685429
        NormalInverse.ppf(0.8413447460685429).should be_within(CENTRAL_TOL).of(1.0)
      end

      it 'returns k = -1 for p = Φ(-1)' do
        NormalInverse.ppf(1.0 - 0.8413447460685429).should be_within(CENTRAL_TOL).of(-1.0)
      end

      it 'returns k = 2 for p = Φ(2)' do
        # Φ(2) = 0.9772498680518208 — this is in the tail region
        NormalInverse.ppf(0.9772498680518208).should be_within(TAIL_TOL).of(2.0)
      end

      it 'returns k = -2 for p = Φ(-2)' do
        NormalInverse.ppf(1.0 - 0.9772498680518208).should be_within(TAIL_TOL).of(-2.0)
      end

      it 'returns k = 3 for p = Φ(3)' do
        # Φ(3) = 0.9986501019683699
        NormalInverse.ppf(0.9986501019683699).should be_within(TAIL_TOL).of(3.0)
      end

      it 'returns k = -3 for p = Φ(-3)' do
        NormalInverse.ppf(1.0 - 0.9986501019683699).should be_within(TAIL_TOL).of(-3.0)
      end

      it 'returns k ≈ 1.6449 for p = 0.95 (one-sided P95)' do
        NormalInverse.ppf(0.95).should be_within(CENTRAL_TOL).of(1.6448536269514722)
      end

      it 'returns k ≈ 1.96 for p = 0.975 (two-sided 95%)' do
        NormalInverse.ppf(0.975).should be_within(TAIL_TOL).of(1.959963984540054)
      end

      it 'returns k ≈ 2.3263 for p = 0.99' do
        NormalInverse.ppf(0.99).should be_within(TAIL_TOL).of(2.3263478740408408)
      end

      it 'returns k = +∞ for p = 1.0 exactly' do
        NormalInverse.ppf(1.0).should == Float::INFINITY
      end

      it 'returns k = -∞ for p = 0.0 exactly' do
        NormalInverse.ppf(0.0).should == -Float::INFINITY
      end

      it 'raises ArgumentError for p < 0' do
        lambda { NormalInverse.ppf(-0.01) }.should raise_error ArgumentError
      end

      it 'raises ArgumentError for p > 1' do
        lambda { NormalInverse.ppf(1.01) }.should raise_error ArgumentError
      end

      it 'raises ArgumentError for non-numeric input' do
        lambda { NormalInverse.ppf("0.5") }.should raise_error ArgumentError
      end

      it 'is antisymmetric around p = 0.5' do
        # Φ⁻¹(p) = -Φ⁻¹(1 - p) for any p in (0, 1).
        [0.001, 0.1, 0.25, 0.4, 0.45, 0.499].each do |p|
          NormalInverse.ppf(p).should be_within(TAIL_TOL).of(-NormalInverse.ppf(1.0 - p))
        end
      end

      it 'is monotonically increasing' do
        xs = [0.01, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.99]
        ks = xs.map { |p| NormalInverse.ppf(p) }
        ks.each_cons(2) { |a, b| a.should be < b }
      end

      it 'handles both sides of the central/tail split (|u| = 0.42) continuously' do
        # At p = 0.92 the branch switches. Verify derivative continuity by
        # comparing finite-difference slopes just inside and just outside
        # the split point — the two expansions must agree on the local
        # slope d/dp Φ⁻¹(p) = 1/φ(Φ⁻¹(p)), otherwise there is a visible
        # kink at the boundary.
        h = 1e-4
        slope_left  = (NormalInverse.ppf(0.9199) - NormalInverse.ppf(0.9197)) / (2 * h)
        slope_right = (NormalInverse.ppf(0.9203) - NormalInverse.ppf(0.9201)) / (2 * h)
        (slope_right - slope_left).abs.should be < 0.05
      end

    end

  end

end
