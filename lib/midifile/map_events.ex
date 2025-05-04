defmodule Midifile.MapEvents do
  @moduledoc """
  Functions for mapping MIDI track events to Sonority types.

  This module provides functionality to analyze a MIDI track and convert its
  events into a sequence of musical sonorities (Note, Chord, Rest). This higher-level
  representation makes it easier to work with musical concepts rather than raw MIDI events.

  The conversion process works in multiple steps:
  1. Identify all note events in the track and calculate their start/end times
  2. Group notes into chords based on timing overlap and tolerance settings
  3. Add rests between sound events
  4. Return chronologically ordered sonorities

  These sonorities can then be manipulated, analyzed, or converted back to MIDI events.

  ## Example

      # Convert MIDI track to sonorities
      sonorities = Midifile.MapEvents.track_to_sonorities(track, %{chord_tolerance: 10})

      # Process individual sonorities
      Enum.each(sonorities, fn sonority ->
        case Sonority.type(sonority) do
          :note -> IO.puts("Note: # {inspect(sonority.note)}")
          :chord -> IO.puts("Chord with # {length(sonority.notes)} notes")
          :rest -> IO.puts("Rest: # {Sonority.duration(sonority)} beats")
        end
      end)
  """

  alias Midifile.Event
  alias Midifile.Defaults

  @doc """
  Maps a track's MIDI events to a sequence of Sonority types (Note, Chord, or Rest).

  This function analyzes a MIDI track and extracts its musical content as a series
  of sonorities that represent the fundamental musical elements:
  - Notes: Single pitches with duration and velocity
  - Chords: Multiple notes sounding together with a common duration
  - Rests: Periods of silence with a duration

  The algorithm handles overlapping notes, identifying chords based on timing proximity,
  and properly accounts for rests between sound events.

  ## Parameters
    * `track` - A `Midifile.Track` struct containing MIDI events
    * `opts` - Options map with the following possible keys:
      * `:chord_tolerance` - Time in ticks within which notes are considered part of the same chord (default: 0)
      * `:ticks_per_quarter_note` - The PPQN/TPQN time division to use (default: 960)

  ## Returns
    * A list of Sonority protocol implementations (Note, Chord, Rest) in chronological order

  ## Examples

      # Basic usage with default options
      sonorities = Midifile.MapEvents.track_to_sonorities(track)

      # With custom chord tolerance and PPQN
      sonorities = Midifile.MapEvents.track_to_sonorities(track, %{
        chord_tolerance: 10,  # Notes within 10 ticks are considered part of the same chord
        ticks_per_quarter_note: sequence.ticks_per_quarter_note
      })
  """
  def track_to_sonorities(track, opts \\ %{}) do
    # Default options
    chord_tolerance = Map.get(opts, :chord_tolerance, 0)
    tpqn = Map.get(opts, :ticks_per_quarter_note, Defaults.default_ppqn)

    # First, calculate absolute start and end times for all notes
    note_events = identify_note_events(track.events)

    # Group notes into chords and rests
    group_into_sonorities(note_events, chord_tolerance, tpqn)
  end

  @doc """
  Identifies all note events in a track and calculates their absolute start/end times.

  This function pairs note-on and note-off events to create complete note objects
  with duration information. It handles both standard note-off events and note-on
  events with zero velocity (which are treated as note-offs according to the MIDI spec).

  The function also properly handles unmatched note-on events by assigning them
  an end time based on the last event in the track.

  ## Parameters
    * `events` - List of MIDI events from a track

  ## Returns
    * A list of note data maps with keys:
      * `:note` - The MIDI note number (0-127)
      * `:start_time` - Absolute start time in ticks from the beginning of the track
      * `:end_time` - Absolute end time in ticks
      * `:velocity` - The note's velocity (0-127)
      * `:channel` - The MIDI channel (0-15)

  ## Examples

      # Get all notes from a track with their timing information
      note_events = Midifile.MapEvents.identify_note_events(track.events)

      # Print information about each note
      Enum.each(note_events, fn note ->
        duration = note.end_time - note.start_time
        IO.puts("Note # {note.note} on channel # {note.channel}, " <>
                "duration: # {duration} ticks, velocity: # {note.velocity}")
      end)
  """
  def identify_note_events(events) do
    # Calculate absolute times for all events
    events_with_times = add_absolute_times(events)

    # Track note_on events to pair with note_offs
    # Format: %{{channel, note} => {abs_time, velocity}}
    {notes, note_on_events} =
      Enum.reduce(events_with_times, {[], %{}}, fn {event, abs_time}, {notes_acc, note_on_acc} ->
        case event do
          # Handle note_on events (velocity > 0)
          %{symbol: :on, bytes: [_status, note_num, velocity]} when velocity > 0 ->
            channel = Event.channel(event)
            key = {channel, note_num}
            # Store this note_on event with its start time and velocity
            new_note_on_acc = Map.put(note_on_acc, key, {abs_time, velocity})
            {notes_acc, new_note_on_acc}

          # Handle note_off events
          %{symbol: :off} = event ->
            channel = Event.channel(event)
            note_num = Event.note(event)
            key = {channel, note_num}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Create a note data structure
                note_data = %{
                  note: note_num,
                  start_time: start_time,
                  end_time: abs_time,
                  velocity: velocity,
                  channel: channel
                }

                # Add to notes list and remove from tracking
                {[note_data | notes_acc], Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, note_on_acc}
            end

          # Handle note_on with zero velocity (treated as note_off)
          %{symbol: :on, bytes: [_status, note_num, 0]} ->
            channel = Event.channel(event)
            key = {channel, note_num}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Create a note data structure
                note_data = %{
                  note: note_num,
                  start_time: start_time,
                  end_time: abs_time,
                  velocity: velocity,
                  channel: channel
                }

                # Add to notes list and remove from tracking
                {[note_data | notes_acc], Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, note_on_acc}
            end

          # Ignore all other event types
          _ ->
            {notes_acc, note_on_acc}
        end
      end)

    # For any note_on events without matching note_off events, assume they end at the track end
    # (this might happen in malformed MIDI files)
    unmatched_notes =
      Enum.map(note_on_events, fn {{channel, note_num}, {start_time, velocity}} ->
        # Use the last event's time as the end time or just a large value
        end_time =
          case List.last(events_with_times) do
            {_, time} -> time
            _ -> 999_999  # Just a large number for unmatched notes
          end

        %{
          note: note_num,
          start_time: start_time,
          end_time: end_time,
          velocity: velocity,
          channel: channel
        }
      end)

    Enum.concat(notes, unmatched_notes)
  end

  @doc """
  Groups identified notes into sonorities (Notes, Chords, Rests).

  This function analyzes the timing relationships between notes to determine when
  notes should be considered as individual notes, as parts of chords, or when
  rests should be inserted between sound events.

  The chord_tolerance parameter allows for some flexibility in chord detection.
  Notes that start within the tolerance window will be grouped into a chord,
  even if they don't start at exactly the same time. This is particularly useful
  for human performances or imperfectly quantized MIDI where chord notes might
  not be precisely aligned.

  ## Parameters
    * `note_events` - List of note data maps from identify_note_events/1
    * `chord_tolerance` - Time window (in ticks) for grouping notes into chords
    * `tpqn` - Ticks per quarter note value used to calculate durations in beats

  ## Returns
    * A list of Sonority protocol implementations (Note, Chord, Rest) in chronological order

  ## Examples

      # First identify notes
      note_events = Midifile.MapEvents.identify_note_events(track.events)

      # Then group them into sonorities with a tolerance of 10 ticks
      sonorities = Midifile.MapEvents.group_into_sonorities(note_events, 10, 960)

      # Count the different types of sonorities
      types = Enum.group_by(sonorities, &Sonority.type/1)
      IO.puts("Found # {length(types[:note] || [])} notes, " <>
              "# {length(types[:chord] || [])} chords, and " <>
              "# {length(types[:rest] || [])} rests")
  """
  def group_into_sonorities(note_events, chord_tolerance, tpqn \\ Defaults.default_ppqn) do
    # Find all unique start and end times
    all_times =
      note_events
      |> Enum.flat_map(fn note -> [note.start_time, note.end_time] end)
      |> Enum.uniq()
      |> Enum.sort()

    # For each time segment, determine what sonority is active
    {sonorities, _} =
      Enum.reduce(all_times, {[], nil}, fn current_time, {sonorities_acc, prev_time} ->
        # Skip the first time point (we need pairs of times)
        if prev_time == nil do
          {sonorities_acc, current_time}
        else
          # Find notes that are active during this time segment
          active_notes = Enum.filter(note_events, fn note ->
            note.start_time <= prev_time + chord_tolerance && note.end_time >= current_time
          end)

          duration = (current_time - prev_time) / tpqn
          # Create appropriate sonority based on number of active notes
          new_sonority = cond do
            # No notes active - create a Rest
            Enum.empty?(active_notes) ->
              Rest.new(duration)

            # One note active - create a Note
            length(active_notes) == 1 ->
              [note] = active_notes
              # Convert MIDI note to Note struct
              Note.midi_to_note(note.note, duration, note.velocity)

            # Multiple notes active - create a Chord
            true ->
              # Convert each MIDI note to a Note struct
              notes = Enum.map(active_notes, fn note ->
                Note.midi_to_note(note.note, duration, note.velocity)
              end)
              # Create chord with the notes
              Chord.new(notes, duration)
          end

          # Only add sonority if it has duration
          if Sonority.duration(new_sonority) > 0 do
            {[new_sonority | sonorities_acc], current_time}
          else
            {sonorities_acc, current_time}
          end
        end
      end)

    Enum.reverse(sonorities)
  end

  @doc false
  # Calculate absolute time for each event based on delta times
  #
  # In MIDI files, event timing is stored as delta times (time since the previous event).
  # This function converts these relative timings to absolute times from the start of the track,
  # which makes it easier to analyze timing relationships between events.
  #
  # Returns a list of {event, absolute_time} tuples in the original event order.
  defp add_absolute_times(events) do
    {events_with_times, _} =
      Enum.reduce(events, {[], 0}, fn event, {acc, current_time} ->
        new_time = current_time + event.delta_time
        {[{event, new_time} | acc], new_time}
      end)

    Enum.reverse(events_with_times)
  end
end
