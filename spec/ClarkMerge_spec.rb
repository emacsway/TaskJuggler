#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = ClarkMerge_spec.rb -- The TaskJuggler III Project Management Software
#

require 'rubygems'

require 'taskjuggler/ClarkMerge'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
end

class TaskJuggler

  describe ClarkMerge do

    # Monte Carlo a reference value for the max of a list of normals,
    # used to cross-check the analytical formula on small examples.
    def mc_max_moments(specs, n: 50_000, seed: 42)
      rng = Random.new(seed)
      samples = Array.new(n) do
        specs.map do |mu, sigma|
          u1, u2 = rng.rand, rng.rand
          z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
          mu + sigma * z
        end.max
      end
      mean = samples.sum / samples.size
      var  = samples.sum { |x| (x - mean) ** 2 } / (samples.size - 1)
      [mean, Math.sqrt(var)]
    end

    # ─── phi / cdf basics ──────────────────────────────────────

    describe '.phi' do
      it 'returns 1/√(2π) at 0' do
        ClarkMerge.phi(0.0).should be_within(1e-12).of(1.0 / Math.sqrt(2.0 * Math::PI))
      end

      it 'is symmetric around 0' do
        ClarkMerge.phi(1.2345).should be_within(1e-12).of(ClarkMerge.phi(-1.2345))
      end

      it 'tails off toward 0' do
        ClarkMerge.phi(6.0).should be < 1e-8
      end
    end

    describe '.cdf' do
      it 'returns 0.5 at 0' do
        ClarkMerge.cdf(0.0).should be_within(1e-12).of(0.5)
      end

      it 'approaches 1 for large positive x' do
        ClarkMerge.cdf(6.0).should be_within(1e-6).of(1.0)
      end

      it 'approaches 0 for large negative x' do
        ClarkMerge.cdf(-6.0).should be < 1e-6
      end

      it 'is monotonically increasing' do
        xs = [-3.0, -1.0, 0.0, 1.0, 3.0]
        cdfs = xs.map { |x| ClarkMerge.cdf(x) }
        cdfs.each_cons(2) { |a, b| a.should be < b }
      end
    end

    # ─── merge: degenerate cases ──────────────────────────────

    describe '.merge' do
      it 'returns the larger mean with zero σ when both operands are deterministic' do
        ClarkMerge.merge(5.0, 0.0, 3.0, 0.0).should == [5.0, 0.0]
        ClarkMerge.merge(3.0, 0.0, 5.0, 0.0).should == [5.0, 0.0]
      end

      it 'is symmetric: swapping operands yields the same result' do
        m1 = ClarkMerge.merge(10.0, 2.0, 7.0, 1.5)
        m2 = ClarkMerge.merge(7.0, 1.5, 10.0, 2.0)
        m1[0].should be_within(1e-12).of(m2[0])
        m1[1].should be_within(1e-12).of(m2[1])
      end

      # ─── merge: analytical landmarks ─────────────────────────

      it 'for two iid normals gives σ_max = σ · √(1 − 1/π)' do
        # Two independent N(μ, σ²). Closed form: σ_max = σ · √(1 − 1/π).
        mu, sigma = 10.0, 3.0
        _, sm = ClarkMerge.merge(mu, sigma, mu, sigma)
        expected = sigma * Math.sqrt(1.0 - 1.0 / Math::PI)
        sm.should be_within(1e-9).of(expected)
      end

      it 'for two iid normals gives E[max] = μ + σ/√π' do
        mu, sigma = 10.0, 3.0
        mm, _ = ClarkMerge.merge(mu, sigma, mu, sigma)
        expected = mu + sigma / Math.sqrt(Math::PI)
        mm.should be_within(1e-9).of(expected)
      end

      it 'with well-separated means reduces to the dominant operand' do
        # μ_1 − μ_2 >> σ_1, σ_2: Clark should return (μ_1, σ_1).
        mm, sm = ClarkMerge.merge(100.0, 1.0, 10.0, 1.0)
        mm.should be_within(1e-6).of(100.0)
        sm.should be_within(1e-6).of(1.0)
      end

      it 'one deterministic operand below the stochastic operand leaves it unchanged' do
        # μ_1 > μ_2 by many σ_1, and σ_2 = 0. Z ≈ X_1.
        mm, sm = ClarkMerge.merge(50.0, 2.0, 30.0, 0.0)
        mm.should be_within(1e-9).of(50.0)
        sm.should be_within(1e-9).of(2.0)
      end

      it 'one deterministic operand above absorbs a stochastic operand' do
        # μ_2 is deterministic and above μ_1 by many σ_1. Z ≈ μ_2, σ = 0.
        mm, sm = ClarkMerge.merge(30.0, 2.0, 50.0, 0.0)
        mm.should be_within(1e-9).of(50.0)
        sm.should be_within(1e-9).of(0.0)
      end

      # ─── merge: Monte Carlo agreement ─────────────────────────

      it 'matches Monte Carlo for a moderately asymmetric pair' do
        mu1, s1, mu2, s2 = 10.0, 2.0, 8.0, 3.0
        mm_clark, sm_clark = ClarkMerge.merge(mu1, s1, mu2, s2)
        mm_mc, sm_mc = mc_max_moments([[mu1, s1], [mu2, s2]])
        (mm_clark - mm_mc).abs.should be < 0.05
        (sm_clark - sm_mc).abs.should be < 0.05
      end
    end

    # ─── reduce ───────────────────────────────────────────────

    describe '.reduce' do
      it 'returns its only operand unchanged for a single-element list' do
        ClarkMerge.reduce([[7.0, 1.5]]).should == [7.0, 1.5]
      end

      it 'is insensitive to input order (dominant operand regime)' do
        moments = [[10.0, 1.0], [5.0, 1.0], [3.0, 1.0]]
        r1 = ClarkMerge.reduce(moments)
        r2 = ClarkMerge.reduce(moments.reverse)
        r1[0].should be_within(1e-9).of(r2[0])
        r1[1].should be_within(1e-9).of(r2[1])
      end

      it 'matches Monte Carlo for three branches with dominant critical path' do
        specs = [[20.0, 0.5], [5.0, 0.5], [3.0, 0.5]]
        mm_clark, sm_clark = ClarkMerge.reduce(specs)
        mm_mc, sm_mc = mc_max_moments(specs)
        (mm_clark - mm_mc).abs.should be < 0.02
        (sm_clark - sm_mc).abs.should be < 0.02
      end

      it 'matches Monte Carlo for three near-critical branches' do
        specs = [[10.0, 2.0], [10.0, 2.0], [10.0, 2.0]]
        mm_clark, sm_clark = ClarkMerge.reduce(specs)
        mm_mc, sm_mc = mc_max_moments(specs)
        # 3-branch near-critical is the regime where Clark's compounding
        # normal approximation starts to bite; we expect agreement within
        # ~3% of MC.
        (mm_clark - mm_mc).abs.should be < 0.1
        (sm_clark / sm_mc).should be_within(0.05).of(1.0)
      end

      it 'raises on empty list' do
        lambda { ClarkMerge.reduce([]) }.should raise_error ArgumentError
      end
    end

  end

end
