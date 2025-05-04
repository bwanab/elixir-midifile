defmodule Midifile.Track do
  @moduledoc """
  Represents a MIDI track containing a sequence of MIDI events.
  
  A MIDI track is a container for a sequence of time-ordered MIDI events.
  Each track has a name and can represent an instrument part, percussion,
  or control information.
  
  This module provides functions for creating and manipulating tracks,
  as well as for extracting track information like instrument assignments.
  
  ## Examples
  
      # Create a track from musical sonorities
      track = Midifile.Track.new("Piano", sonorities)
      
      # Get the instrument name for the track
      instrument = Midifile.Track.instrument(track)
      
      # Quantize the track's timing
      quantized = Midifile.Track.quantize(track, 240)  # 16th note quantization at 960 PPQN
  """
  
  @type t() :: %__MODULE__{
    name: String.t(),
    events: list()
  }

  alias Midifile.Defaults
  alias Midifile.Event

  defstruct name: "Unnamed",
    events: []

  @doc """
  Creates a new track from a list of sonorities.
  
  This function converts high-level musical sonorities (notes, chords, rests)
  into low-level MIDI events and assembles them into a properly formatted track.
  The track will include a name event at the beginning and an end-of-track event.
  
  ## Parameters
  
    * `name` - String name for the track
    * `sonorities` - List of sonority protocol implementations (Note, Chord, Rest)
    * `tpqn` - Ticks per quarter note, defines the time resolution (default: 960)
  
  ## Returns
  
    * A new `Midifile.Track` struct containing the converted events
  
  ## Examples
  
      # Create a track with a C major scale
      notes = [
        Note.new({:C, 4}, duration: 1.0),
        Note.new({:D, 4}, duration: 1.0),
        Note.new({:E, 4}, duration: 1.0),
        Note.new({:F, 4}, duration: 1.0),
        Note.new({:G, 4}, duration: 1.0),
        Note.new({:A, 4}, duration: 1.0),
        Note.new({:B, 4}, duration: 1.0),
        Note.new({:C, 5}, duration: 1.0)
      ]
      
      track = Midifile.Track.new("C Major Scale", notes, 960)
  """
  @spec new(String.t(), [Sonority], integer()) :: t()
  def new(name, sonorities, tpqn \\ Defaults.default_ppqn) do
    e1 = [%Midifile.Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    events = Enum.map(sonorities, &(Midifile.Event.new(Sonority.type(&1), &1, tpqn)))
    e_last = [%Midifile.Event{symbol: :track_end, delta_time: 0, bytes: []}]

    %Midifile.Track{
      name: name,
      events: List.flatten(e1 ++ events ++ e_last)
    }
  end

  @doc """
  Returns the instrument name assigned to the track.
  
  This function searches the track's events for an instrument program change event
  and returns its value. If no instrument event is found, returns an empty string.
  
  ## Parameters
  
    * `track` - The `Midifile.Track` struct to examine
  
  ## Returns
  
    * String representation of the instrument or an empty string if none is found
  
  ## Examples
  
      instrument = Midifile.Track.instrument(track)
      IO.puts("This track uses #{instrument}")
  """
  def instrument(%Midifile.Track{events: nil}), do: ""
  def instrument(%Midifile.Track{events: []}),  do: ""
  def instrument(%Midifile.Track{events: list})  do
    case Enum.find(list, &(&1.symbol == :instrument)) do
      %Event{bytes: bytes} -> bytes
      nil -> ""
    end
  end

  @doc """
  Quantizes the timing of all events in a track to a grid.
  
  This function adjusts the timing of events to align with a regular grid,
  making the rhythm more precise. The grid size is specified in ticks.
  
  ## Parameters
  
    * `track` - The `Midifile.Track` struct to quantize
    * `n` - The grid size in ticks (e.g., 240 for 16th notes at 960 PPQN)
  
  ## Returns
  
    * A new `Midifile.Track` struct with quantized events
  
  ## Examples
  
      # Quantize to 8th notes (at 960 PPQN)
      quantized_track = Midifile.Track.quantize(track, 480)
      
      # Quantize to 16th notes (at 960 PPQN)
      quantized_track = Midifile.Track.quantize(track, 240)
  """
  def quantize(track, n) do
    %{track | events: Event.quantize(track.events, n)}
  end
end
