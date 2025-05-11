defmodule Midifile.Track do
  @moduledoc """
  Represents a MIDI track containing a sequence of MIDI events.

  A MIDI track is a container for a sequence of time-ordered MIDI events.
  Each track has a name and can represent an instrument part, percussion,
  or control information.

  This module provides functions for creating and manipulating tracks,
  as well as for extracting track information like instrument assignments.

  ## Examples

      # Create a track from MIDI events
      track = Midifile.Track.new("Piano", events)

      # Get the instrument name for the track
      instrument = Midifile.Track.instrument(track)

      # Quantize the track's timing
      quantized = Midifile.Track.quantize(track, 240)  # 16th note quantization at 960 PPQN
  """

  @type t() :: %__MODULE__{
    name: String.t(),
    events: list()
  }

  alias Midifile.Event

  defstruct name: "Unnamed",
    events: []

  @doc """
  Creates a new track from a list of MIDI events.

  ## Parameters

    * `name` - String name for the track
    * `events` - List of MIDI events

  ## Returns

    * A new `Midifile.Track` struct containing the events

  ## Examples

      # Create a track with MIDI events
      events = [
        %Event{symbol: :on, delta_time: 0, bytes: [144, 60, 100]},
        %Event{symbol: :off, delta_time: 480, bytes: [128, 60, 0]}
      ]

      track = Midifile.Track.new("Piano", events)
  """
  @spec new(String.t(), [Event.t()]) :: t()
  def new(name, events) do
    e1 = [%Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    e_last = [%Event{symbol: :track_end, delta_time: 0, bytes: []}]

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
      # IO.puts("This track uses # {instrument}")
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
