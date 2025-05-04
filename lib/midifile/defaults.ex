defmodule Midifile.Defaults do
  @moduledoc """
  Provides default values and utility functions for MIDI file parameters.
  
  This module contains constants and helper functions for common MIDI settings 
  such as BPM (beats per minute), PPQN (pulses per quarter note), and time signatures.
  These defaults provide consistency throughout the application and can be used 
  by other modules when specific values are not provided.
  """

  @doc """
  Returns the default tempo in beats per minute (BPM).
  
  ## Returns
  
    * `120` - Standard default tempo of 120 BPM, a moderate tempo (allegro)
  
  ## Examples
  
      iex> Midifile.Defaults.default_bpm()
      120
  """
  def default_bpm do 120 end
  
  @doc """
  Returns the default pulses per quarter note (PPQN), also known as ticks per quarter note.
  
  This value defines the time resolution of MIDI events. Higher values provide finer 
  timing resolution but require more storage space.
  
  ## Returns
  
    * `960` - High resolution timing value that divides well for common note divisions
  
  ## Examples
  
      iex> Midifile.Defaults.default_ppqn()
      960
  """
  def default_ppqn do 960 end
  
  @doc """
  Returns the default time signature as a list of [numerator, denominator].
  
  ## Returns
  
    * `[4, 4]` - Standard 4/4 time signature (common time)
  
  ## Examples
  
      iex> Midifile.Defaults.default_time_signature()
      [4, 4]
  """
  def default_time_signature do [4, 4] end

  @doc """
  Converts a time signature from [numerator, denominator] format to MIDI byte format.
  
  ## Parameters
  
    * `[num, denom]` - List containing numerator and denominator, defaults to [4, 4]
  
  ## Returns
  
    * A list containing a binary with the MIDI-formatted time signature
  
  ## Examples
  
      iex> Midifile.Defaults.time_signature([3, 4])
      [<<3, 2, 24, 8>>]
      
      iex> Midifile.Defaults.time_signature()
      [<<4, 2, 24, 8>>]
  """
  def time_signature([num, denom] \\ [4, 4]) do
    [<<num, ts_denom(denom), 24, 8>>]
  end
  
  @doc """
  Converts a time signature denominator to its MIDI representation.
  
  In MIDI, the denominator is stored as a negative power of 2:
  - 1 represents a half note (2)
  - 2 represents a quarter note (4)
  - 3 represents an eighth note (8)
  - etc.
  
  ## Parameters
  
    * `denom` - Denominator of the time signature (2, 4, 8, 16, or 32)
  
  ## Returns
  
    * Integer value representing the denominator in MIDI format
  
  ## Examples
  
      iex> Midifile.Defaults.ts_denom(4)
      2
      
      iex> Midifile.Defaults.ts_denom(8)
      3
  """
  def ts_denom(denom) do
     Map.get(%{
        2 => 1,
        4 => 2,
        8 => 3,
        16 => 4,
        32 => 5
      }, denom)
  end
end
