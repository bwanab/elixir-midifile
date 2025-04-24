defmodule Midifile.Filter do
  @moduledoc """
  Functions for filtering events in MIDI sequences and tracks.
  """

  @doc """
  Filters events in a track by removing events that match the given criteria.

  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct
    * `track_number` - Zero-based index of the track to filter
    * `event_type` - The event type to filter out (e.g., `:pitch_bend`)

  ## Returns
    * A new sequence with the filtered track
  """
  def filter_events(sequence, track_number, event_type) do
    # Get the tracks list
    tracks = sequence.tracks

    # Validate track number is in range
    if track_number < 0 or track_number >= length(tracks) do
      raise ArgumentError, "Track number #{track_number} is out of range (0-#{length(tracks) - 1})"
    end

    # Get the target track
    track = Enum.at(tracks, track_number)
    
    # Filter the events
    filtered_events = Enum.filter(track.events, &(&1.symbol != event_type))
    
    # Create a new track with filtered events
    filtered_track = %{track | events: filtered_events}
    
    # Replace the track in the sequence and return the new sequence
    updated_tracks = List.replace_at(tracks, track_number, filtered_track)
    %{sequence | tracks: updated_tracks}
  end
end