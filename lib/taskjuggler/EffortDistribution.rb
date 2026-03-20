#!/usr/bin/env ruby -w
# frozen_string_literal: true
# encoding: UTF-8
#
# = EffortDistribution.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014
#               by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

class TaskJuggler

  # The EffortDistribution class represents effort as a probability distribution
  # with mean and standard deviation values. This allows for uncertainty analysis
  # in project planning.
  class EffortDistribution

    attr_reader :mean, :stddev

    # Create a new EffortDistribution object.
    # @param mean [Float] The mean (expected) effort value in time slots
    # @param stddev [Float] The standard deviation of the effort (optional, defaults to 0)
    def initialize(mean, stddev = 0.0)
      @mean = mean.to_f
      @stddev = stddev.to_f
    end

    # Check if this is a deterministic effort (no uncertainty)
    # @return [Boolean] true if stddev is 0
    def deterministic?
      @stddev == 0.0
    end

    def round(ndigits = 0)
      EffortDistribution.new(@mean.round(ndigits), @stddev)
    end

    def abs
      EffortDistribution.new(@mean.abs, @stddev)
    end

    # Compatibility method for existing code that expects a numeric value
    # @return [Float] the mean effort value
    def to_f
      @mean
    end

    # Compatibility method for existing code that expects a numeric value
    # @return [Integer] the mean effort value as integer
    def to_i
      @mean.to_i
    end

    # String representation for debugging and display
    # @return [String] formatted string showing mean and stddev
    def to_s
      if deterministic?
        @mean.to_s
      else
        "#{@mean}±#{@stddev}"
      end
    end

    # Comparison methods for compatibility with numeric values
    def >(other)
      @mean > (other.respond_to?(:mean) ? other.mean : other)
    end

    def <(other)
      @mean < (other.respond_to?(:mean) ? other.mean : other)
    end

    def ==(other)
      if other.respond_to?(:mean) && other.respond_to?(:stddev)
        @mean == other.mean && @stddev == other.stddev
      else
        @mean == other && @stddev == 0.0
      end
    end

    def >=(other)
      @mean >= (other.respond_to?(:mean) ? other.mean : other)
    end

    def <=(other)
      @mean <= (other.respond_to?(:mean) ? other.mean : other)
    end

    # Arithmetic operations - return new EffortDistribution objects
    def +(other)
      if other.respond_to?(:mean) && other.respond_to?(:stddev)
        # Adding two distributions: combine mean and stddev
        new_stddev = Math.sqrt(@stddev**2 + other.stddev**2)
        EffortDistribution.new(@mean + other.mean, new_stddev)
      else
        # Adding a constant: only affects mean
        EffortDistribution.new(@mean + other, @stddev)
      end
    end

    def -(other)
      if other.respond_to?(:mean) && other.respond_to?(:stddev)
        # Subtracting two distributions
        new_stddev = Math.sqrt(@stddev**2 + other.stddev**2)
        EffortDistribution.new(@mean - other.mean, new_stddev)
      else
        # Subtracting a constant
        EffortDistribution.new(@mean - other, @stddev)
      end
    end

    def *(other)
      # Multiplication by a scalar
      scalar = other.respond_to?(:mean) ? other.mean : other
      EffortDistribution.new(@mean * scalar, @stddev * scalar.abs)
    end

    def /(other)
      # Division by a scalar
      scalar = other.respond_to?(:mean) ? other.mean : other
      EffortDistribution.new(@mean / scalar, @stddev / scalar.abs)
    end

  end

end