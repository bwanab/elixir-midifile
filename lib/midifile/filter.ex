defmodule Midifile.Filter do
  @moduledoc """
  Functions for filtering events in MIDI sequences and tracks.
  """

  @doc """
  Filters events in a track by applying a predicate function.

  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct
    * `track_number` - Zero-based index of the track to filter
    * `predicate` - A function that takes an event and returns true if the event should be kept

  ## Returns
    * A new sequence with the filtered track
  """
  def filter_events_by_predicate(sequence, track_number, predicate) do
    # Get the tracks list
    tracks = sequence.tracks

    # Validate track number is in range
    if track_number < 0 or track_number >= length(tracks) do
      raise ArgumentError,
            "Track number #{track_number} is out of range (0-#{length(tracks) - 1})"
    end

    # Get the target track
    track = Enum.at(tracks, track_number)

    # Process the events, preserving delta times
    processed_events = preserve_delta_times(track.events, predicate)

    # Create a new track with filtered events
    filtered_track = %{track | events: processed_events}

    # Replace the track in the sequence and return the new sequence
    updated_tracks = List.replace_at(tracks, track_number, filtered_track)
    %{sequence | tracks: updated_tracks}
  end

  @doc """
  Filters events while preserving the total delta time.
  
  When removing events, their delta_time values are added to the next 
  non-filtered event to maintain the correct timing.
  """
  def preserve_delta_times(events, predicate) do
    {filtered_events, _} = 
      Enum.reduce(events, {[], 0}, fn event, {acc, accumulated_delta} ->
        if predicate.(event) do
          # Keep this event, add any accumulated delta to it
          updated_event = %{event | delta_time: event.delta_time + accumulated_delta}
          {[updated_event | acc], 0}
        else
          # Skip this event, accumulate its delta time
          {acc, accumulated_delta + event.delta_time}
        end
      end)
      
    # Return events in the original order
    Enum.reverse(filtered_events)
  end

  @doc """
  Filters events in a track by removing events that match the given event type.

  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct
    * `track_number` - Zero-based index of the track to filter
    * `event_type` - The event type to filter out (e.g., `:pitch_bend`)

  ## Returns
    * A new sequence with the filtered track
  """
  def filter_events(sequence, track_number, event_type) do
    filter_events_by_predicate(sequence, track_number, &(&1.symbol != event_type))
  end
end
