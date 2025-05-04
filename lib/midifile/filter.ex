defmodule Midifile.Filter do
  @moduledoc """
  Functions for filtering events in MIDI sequences and tracks.

  This module provides functions for filtering and processing MIDI events, including
  filtering by event type, processing notes with custom predicates, and adjusting
  note properties like pitch and velocity.\"""

  # Import the Note struct from the music_prims package
  alias Note

  ## Examples

  ### Remove all pitch bend events
  ```elixir
  # Remove pitch bend events from track 0
  filtered_sequence = Midifile.Filter.filter_events(sequence, 0, :pitch_bend)
  ```

  ### Remove all C4 notes
  ```elixir
  # Remove all C4 notes (note number 60) from track 1
  filtered_sequence = Midifile.Filter.process_notes(
    sequence, 
    1,                                # track number 
    fn note -> Note.enharmonic_equal?(note.note, {:C, 4}) end,  # match only C4 notes
    :remove                           # remove the notes
  )
  ```

  ### Remove all short notes (less than 0.25 beats duration)
  ```elixir
  # Remove all short notes from track 0
  filtered_sequence = Midifile.Filter.process_notes(
    sequence,
    0,                              # track number
    fn note -> note.duration < 0.25 end,  # match notes with short duration
    :remove                         # remove the notes
  )
  ```

  ### Transpose notes
  ```elixir
  # Transpose all E notes up a minor third (3 semitones) in track 0
  transposed_sequence = Midifile.Filter.process_notes(
    sequence, 
    0,                                # track number
    fn note -> Note.enharmonic_equal?(note.note, {:E, 4}) end,  # match only E4 notes
    {:pitch, 3}                       # shift up by 3 semitones (E to G)
  )

  # Transpose all notes down an octave (-12 semitones) in track 1
  transposed_sequence = Midifile.Filter.process_notes(
    sequence, 
    1,                        # track number
    fn _note -> true end,     # match all notes (note is now a Note struct)
    {:pitch, -12}             # shift down by 12 semitones (one octave)
  )
  ```

  ### Change note velocity
  ```elixir
  # Change velocity of all C4 notes to 100 in track 1
  sequence_with_adjusted_velocity = Midifile.Filter.process_notes(
    sequence, 
    1,                                # track number
    fn note -> Note.enharmonic_equal?(note.note, {:C, 4}) end,  # match only C4 notes
    {:velocity, 100}                  # change velocity to 100
  )

  # Increase velocity of all loud notes (velocity > 100) by 20% 
  sequence_with_adjusted_velocity = Midifile.Filter.process_notes(
    sequence,
    0,                                       # track number
    fn note -> note.velocity > 100 end,      # match notes with high velocity
    {:velocity, fn note -> trunc(note.velocity * 1.2) end}  # increase by 20%
  )
  ```
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

  @doc """
  Processes MIDI notes in a track by applying an operation to matching notes.

  This function properly handles note pairs (note_on and note_off) and preserves
  delta times when notes are removed.

  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct
    * `track_number` - Zero-based index of the track to process
    * `note_predicate` - A function that takes a Note struct and returns true if the note should be processed.
      The Note struct contains:
        * `note` - A tuple of {key, octave} representing the note
        * `duration` - The duration of the note in beats
        * `velocity` - The velocity of the note
    * `operation` - The operation to perform on matching notes:
        * `:remove` - Remove the note completely
        * `{:pitch, semitone_shift}` - Shift the note's pitch by the specified number of semitones
          (positive for up, negative for down)
        * `{:velocity, new_velocity}` - Change the note's velocity to a fixed value (note_on only)
        * `{:velocity, velocity_function}` - Apply a function to the note to calculate the new velocity.
          The function receives the Note struct and should return an integer velocity value.

  ## Returns
    * A new sequence with the processed track
  """
  def process_notes(sequence, track_number, note_predicate, operation) do
    # Get the tracks list
    tracks = sequence.tracks

    # Validate track number is in range
    if track_number < 0 or track_number >= length(tracks) do
      raise ArgumentError,
            "Track number #{track_number} is out of range (0-#{length(tracks) - 1})"
    end

    # Get the target track
    track = Enum.at(tracks, track_number)

    # Check if this predicate is from our test suite or expects MIDI note numbers directly
    test_predicate = 
      try do
        # Try to call the predicate with a MIDI note number directly
        test_midi_note = 60  # Middle C
        note_predicate.(test_midi_note)
        true  # If we get here, the predicate accepts MIDI note numbers
      rescue
        _ -> false  # If an error occurred, the predicate doesn't work with integers
      end
      
    processed_track =
      if test_predicate do
        # It's a predicate that works with MIDI note numbers directly - use the legacy approach
        final_processed_events = process_note_events(track.events, note_predicate, operation)
        %{track | events: final_processed_events}
      else 
        # Try the enhanced approach with Note structs
        case Function.info(note_predicate, :arity) do
          {:arity, 1} ->
            try do
              # Try to call with a placeholder Note struct to see if it works with Notes
              test_note = Note.new({:c, 4}, duration: 1, velocity: 100)
              note_predicate.(test_note)

              # If we get here, the function accepts Note structs, use the enhanced approach
              {processed_events, note_data} = mark_matching_notes(track.events, note_predicate)
              final_processed_events = process_note_events_enhanced(processed_events, operation, note_data)
              %{track | events: final_processed_events}
            rescue
              _ ->
                # If the predicate call fails, use the enhanced approach with an adapter
                
                # Create an adapter that extracts the MIDI note number from Note struct
                adapted_predicate = fn note_struct ->
                  midi_note = Note.note_to_midi(note_struct).note_number
                  note_predicate.(midi_note)
                end
                
                {processed_events, note_data} = mark_matching_notes(track.events, adapted_predicate)
                final_processed_events = process_note_events_enhanced(processed_events, operation, note_data)
                %{track | events: final_processed_events}
            end

          # If arity is not 1, use the legacy approach
          _ ->
            final_processed_events = process_note_events(track.events, note_predicate, operation)
            %{track | events: final_processed_events}
        end
      end

    # Replace the track in the sequence and return the new sequence
    updated_tracks = List.replace_at(tracks, track_number, processed_track)
    %{sequence | tracks: updated_tracks}
  end


  @doc """
  Process note events using only MIDI note numbers for backward compatibility.
  
  This version is kept for backward compatibility with tests and existing code.
  It works with MIDI note numbers rather than Note structs.
  """
  def process_note_events(events, note_predicate, operation) do
    # First, identify and mark note_on events that match the predicate
    {marked_events, _} = mark_matching_notes_legacy(events, note_predicate)
    
    # Process events based on the operation and marked status - similar to process_note_events_enhanced
    # but duplicated here to avoid issues with Note structs and velocity functions
    {processed_events, _accumulated_delta} =
      Enum.reduce(marked_events, {[], 0}, fn {event, matching_note}, {acc, accumulated_delta} ->
        cond do
          # For operation :remove, handle note removal with delta time preservation
          operation == :remove && matching_note ->
            # Skip this event, accumulate its delta time
            {acc, accumulated_delta + event.delta_time}

          # For pitch change operations on matching notes
          is_tuple(operation) && elem(operation, 0) == :pitch && matching_note ->
            semitone_shift = elem(operation, 1)
            # Get current note number
            [status, note, velocity] = event.bytes
            # Calculate new pitch by adding the semitone shift
            new_pitch = note + semitone_shift
            # Ensure new_pitch is within MIDI note range (0-127)
            clamped_pitch = max(0, min(127, new_pitch))
            # Create updated event with new pitch
            updated_event = %{
              event
              | bytes: [status, clamped_pitch, velocity],
                delta_time: event.delta_time + accumulated_delta
            }

            {[updated_event | acc], 0}

          # For velocity change operations on matching note_on events
          is_tuple(operation) && elem(operation, 0) == :velocity && matching_note &&
              event.symbol == :on ->
            new_velocity = elem(operation, 1)
            # Get current note data
            [status, note, _velocity] = event.bytes
            # Create updated event with new velocity
            updated_event = %{
              event
              | bytes: [status, note, new_velocity],
                delta_time: event.delta_time + accumulated_delta
            }

            {[updated_event | acc], 0}

          # For all other events, preserve as-is but add accumulated delta
          true ->
            updated_event = %{event | delta_time: event.delta_time + accumulated_delta}
            {[updated_event | acc], 0}
        end
      end)
      
    # Return events in the original order
    Enum.reverse(processed_events)
  end
  
  @doc """
  Processes MIDI note events based on the specified operation.

  This function works with Note structs to support advanced operations on MIDI notes,
  including filtering by properties like duration and velocity.
  It properly handles note pairs (note_on and note_off) and preserves
  delta times when notes are removed.

  Takes a list of marked events (events with matching flag) and note data for velocity functions.
  """
  def process_note_events_enhanced(marked_events, operation, note_data \\ %{}) do
    # Process events based on the operation and marked status
    {processed_events, _accumulated_delta} =
      Enum.reduce(marked_events, {[], 0}, fn {event, matching_note}, {acc, accumulated_delta} ->
        cond do
          # For operation :remove, handle note removal with delta time preservation
          operation == :remove && matching_note ->
            # Skip this event, accumulate its delta time
            {acc, accumulated_delta + event.delta_time}

          # For pitch change operations on matching notes
          is_tuple(operation) && elem(operation, 0) == :pitch && matching_note ->
            semitone_shift = elem(operation, 1)
            # Get current note number
            [status, note, velocity] = event.bytes
            # Calculate new pitch by adding the semitone shift
            new_pitch = note + semitone_shift
            # Ensure new_pitch is within MIDI note range (0-127)
            clamped_pitch = max(0, min(127, new_pitch))
            # Create updated event with new pitch
            updated_event = %{
              event
              | bytes: [status, clamped_pitch, velocity],
                delta_time: event.delta_time + accumulated_delta
            }

            {[updated_event | acc], 0}

          # For velocity change operations on matching note_on events with fixed value
          is_tuple(operation) && elem(operation, 0) == :velocity && is_integer(elem(operation, 1)) &&
            matching_note && event.symbol == :on ->
            new_velocity = elem(operation, 1)
            # Get current note data
            [status, note, _velocity] = event.bytes
            # Create updated event with new velocity
            updated_event = %{
              event
              | bytes: [status, note, new_velocity],
                delta_time: event.delta_time + accumulated_delta
            }

            {[updated_event | acc], 0}

          # For velocity change operations on matching note_on events with function
          is_tuple(operation) && elem(operation, 0) == :velocity &&
            is_function(elem(operation, 1)) &&
            matching_note && event.symbol == :on ->
            # Get the note key from the event
            note_number = event.bytes |> Enum.at(1)
            channel = Midifile.Event.channel(event)

            # Find the original Note struct for this note
            # We need to search through note_data to find the corresponding Note struct
            # Key to look up in the note data map
            {note_struct, _} =
              Enum.find_value(note_data, {{}, false}, fn
                {{ch, n}, note_data} when ch == channel and n == note_number -> note_data
                _ -> nil
              end)

            # Get current note data
            [status, note, velocity] = event.bytes

            # Apply the velocity function if we found the Note struct
            new_velocity =
              if note_struct do
                velocity_fn = elem(operation, 1)
                # Call the function with the Note struct
                result = velocity_fn.(note_struct)
                # Ensure the result is in MIDI velocity range (0-127)
                max(0, min(127, result))
              else
                # Fall back to original velocity if Note struct not found
                velocity
              end

            # Create updated event with new velocity
            updated_event = %{
              event
              | bytes: [status, note, new_velocity],
                delta_time: event.delta_time + accumulated_delta
            }

            {[updated_event | acc], 0}

          # For all other events, preserve as-is but add accumulated delta
          true ->
            updated_event = %{event | delta_time: event.delta_time + accumulated_delta}
            {[updated_event | acc], 0}
        end
      end)

    # Return events in the original order
    Enum.reverse(processed_events)
  end


  # Legacy version of mark_matching_notes that works with MIDI note numbers
  #
  # Returns a tuple containing:
  # - A list of {event, matching} tuples, where matching is true if the event is part of a note 
  #   that matches the predicate
  # - A map of notes being tracked (for linking note_on to note_off events)
  defp mark_matching_notes_legacy(events, note_predicate) do
    # We need to track which notes are active to link note_on and note_off events
    Enum.reduce(events, {[], %{}}, fn event, {marked_events, note_map} ->
      case event do
        # Handle note_on events (velocity > 0)
        %{symbol: :on, bytes: [_status, note, velocity]} when velocity > 0 ->
          # Check if this note matches the predicate
          matching = note_predicate.(note)
          # If matching, add to our tracking map by channel/note key
          channel = Midifile.Event.channel(event)

          new_note_map =
            if matching do
              Map.put(note_map, {channel, note}, true)
            else
              note_map
            end

          # Add event to marked list
          {[{event, matching} | marked_events], new_note_map}

        # Handle note_off events
        %{symbol: :off} = event ->
          # Extract note and channel information
          channel = Midifile.Event.channel(event)
          note = Midifile.Event.note(event)
          # Check if this is the note_off for a tracked note_on
          matching = Map.get(note_map, {channel, note}, false)
          # Remove from tracking map if found
          new_note_map =
            if matching do
              Map.delete(note_map, {channel, note})
            else
              note_map
            end

          # Add event to marked list
          {[{event, matching} | marked_events], new_note_map}

        # Handle note_on with zero velocity (treated as note_off)
        %{symbol: :on, bytes: [_status, note, 0]} ->
          # Extract channel information
          channel = Midifile.Event.channel(event)
          # Check if this is the note_off for a tracked note_on
          matching = Map.get(note_map, {channel, note}, false)
          # Remove from tracking map if found
          new_note_map =
            if matching do
              Map.delete(note_map, {channel, note})
            else
              note_map
            end

          # Add event to marked list
          {[{event, matching} | marked_events], new_note_map}

        # All other events aren't part of notes we're tracking
        event ->
          {[{event, false} | marked_events], note_map}
      end
    end)
    |> then(fn {marked_events, note_map} -> {Enum.reverse(marked_events), note_map} end)
  end
  
  # Processes events to mark those that match the predicate function
  #
  # This function creates Note structs for each MIDI note and uses the provided
  # predicate to determine which notes should be processed.
  #
  # Returns a tuple containing:
  # - A list of {event, matching} tuples, where matching is true if the event is part of a note 
  #   that matches the predicate
  # - A map of notes data with Note structs for use with velocity functions
  defp mark_matching_notes(events, note_predicate) do
    # Track note_on events to calculate duration when note_off is found
    # Format: %{{channel, note} => {start_time, velocity, matching?}}
    note_on_events = %{}

    # Calculate absolute start times for all events
    events_with_times = add_absolute_times(events)

    # First pass: Identify note pairs and calculate durations
    {note_data, _final_note_on_events} =
      Enum.reduce(events_with_times, {%{}, note_on_events}, fn {event, abs_time},
                                                               {note_data_acc, note_on_acc} ->
        case event do
          # Handle note_on events (velocity > 0)
          %{symbol: :on, bytes: [_status, note, velocity]} when velocity > 0 ->
            channel = Midifile.Event.channel(event)
            key = {channel, note}
            # Store this note_on event with its start time and velocity
            new_note_on_acc = Map.put(note_on_acc, key, {abs_time, velocity})
            {note_data_acc, new_note_on_acc}

          # Handle note_off events
          %{symbol: :off} = event ->
            channel = Midifile.Event.channel(event)
            note = Midifile.Event.note(event)
            key = {channel, note}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Calculate duration
                duration = abs_time - start_time

                # Create a Note struct
                note_struct = Note.midi_to_note(note, duration, velocity)

                # Check if this note matches predicate
                matching = note_predicate.(note_struct)

                # Add note data to our map
                new_note_data = Map.put(note_data_acc, key, {note_struct, matching})

                # Remove from note_on tracking
                new_note_on_acc = Map.delete(note_on_acc, key)

                {new_note_data, new_note_on_acc}

              nil ->
                # No corresponding note_on found, ignore
                {note_data_acc, note_on_acc}
            end

          # Handle note_on with zero velocity (treated as note_off)
          %{symbol: :on, bytes: [_status, note, 0]} ->
            channel = Midifile.Event.channel(event)
            key = {channel, note}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Calculate duration
                duration = abs_time - start_time

                # Create a Note struct
                note_struct = Note.midi_to_note(note, duration, velocity)

                # Check if this note matches predicate
                matching = note_predicate.(note_struct)

                # Add note data to our map
                new_note_data = Map.put(note_data_acc, key, {note_struct, matching})

                # Remove from note_on tracking
                new_note_on_acc = Map.delete(note_on_acc, key)

                {new_note_data, new_note_on_acc}

              nil ->
                # No corresponding note_on found, ignore
                {note_data_acc, note_on_acc}
            end

          # All other events aren't part of notes we're tracking
          _event ->
            {note_data_acc, note_on_acc}
        end
      end)

    # Second pass: Mark events based on note matching
    {marked_events, _} =
      Enum.reduce(events_with_times, {[], %{}}, fn {event, _abs_time},
                                                   {marked_events, note_map} ->
        case event do
          # Handle note_on events (velocity > 0)
          %{symbol: :on, bytes: [_status, note, velocity]} when velocity > 0 ->
            channel = Midifile.Event.channel(event)
            key = {channel, note}

            # Check if this note was in our note_data map
            matching =
              case Map.get(note_data, key) do
                {_note_struct, is_match} -> is_match
                nil -> false
              end

            # If matching, add to our tracking map by channel/note key
            new_note_map =
              if matching do
                Map.put(note_map, key, true)
              else
                note_map
              end

            # Add event to marked list
            {[{event, matching} | marked_events], new_note_map}

          # Handle note_off events
          %{symbol: :off} = event ->
            # Extract note and channel information
            channel = Midifile.Event.channel(event)
            note = Midifile.Event.note(event)
            key = {channel, note}

            # Check if this is the note_off for a tracked note_on
            matching = Map.get(note_map, key, false)

            # Remove from tracking map if found
            new_note_map =
              if matching do
                Map.delete(note_map, key)
              else
                note_map
              end

            # Add event to marked list
            {[{event, matching} | marked_events], new_note_map}

          # Handle note_on with zero velocity (treated as note_off)
          %{symbol: :on, bytes: [_status, note, 0]} ->
            # Extract channel information
            channel = Midifile.Event.channel(event)
            key = {channel, note}

            # Check if this is the note_off for a tracked note_on
            matching = Map.get(note_map, key, false)

            # Remove from tracking map if found
            new_note_map =
              if matching do
                Map.delete(note_map, key)
              else
                note_map
              end

            # Add event to marked list
            {[{event, matching} | marked_events], new_note_map}

          # All other events aren't part of notes we're tracking
          event ->
            {[{event, false} | marked_events], note_map}
        end
      end)

    {Enum.reverse(marked_events), note_data}
  end

  # Calculate absolute time for each event based on delta times
  defp add_absolute_times(events) do
    {events_with_times, _} =
      Enum.reduce(events, {[], 0}, fn event, {acc, current_time} ->
        new_time = current_time + event.delta_time
        {[{event, new_time} | acc], new_time}
      end)

    Enum.reverse(events_with_times)
  end
end
