defmodule Midifile.FilterTest do
  use ExUnit.Case

  alias Midifile.Filter
  alias Midifile.Event

  test "filter_events removes pitch_bend events from a track" do
    # Load the test MIDI file
    sequence = Midifile.read("test/test_filter_pitch_bend.mid")

    # Get the original track and count pitch_bend events
    original_track = Enum.at(sequence.tracks, 2)
    original_pitch_bend_count = Enum.count(original_track.events, &(&1.symbol == :pitch_bend))

    # Verify the test file actually has pitch_bend events to filter
    assert original_pitch_bend_count > 0, "Test file should contain pitch_bend events"

    # Filter pitch_bend events from track 2
    filtered_sequence = Filter.filter_events(sequence, 2, :pitch_bend)

    # Check the filtered track
    filtered_track = Enum.at(filtered_sequence.tracks, 2)
    filtered_pitch_bend_count = Enum.count(filtered_track.events, &(&1.symbol == :pitch_bend))

    # Assert all pitch_bend events were removed
    assert filtered_pitch_bend_count == 0, "All pitch_bend events should be removed"

    # Assert other tracks remain unchanged
    assert length(filtered_sequence.tracks) == length(sequence.tracks)
    assert Enum.at(filtered_sequence.tracks, 0) == Enum.at(sequence.tracks, 0)
    assert Enum.at(filtered_sequence.tracks, 1) == Enum.at(sequence.tracks, 1)

    # Assert other events in the filtered track remain unchanged
    assert length(filtered_track.events) ==
             length(original_track.events) - original_pitch_bend_count
  end

  test "preserve_delta_times correctly maintains timing when filtering events" do
    # Create a test sequence of events with known delta times
    events = [
      %Midifile.Event{symbol: :note_on, delta_time: 10, bytes: [0x90, 60, 100]},
      %Midifile.Event{symbol: :pitch_bend, delta_time: 20, bytes: [0xE0, 0, 64]},
      %Midifile.Event{symbol: :pitch_bend, delta_time: 30, bytes: [0xE0, 0, 70]},
      %Midifile.Event{symbol: :note_off, delta_time: 40, bytes: [0x80, 60, 0]},
      %Midifile.Event{symbol: :pitch_bend, delta_time: 50, bytes: [0xE0, 0, 64]},
      %Midifile.Event{symbol: :note_on, delta_time: 60, bytes: [0x90, 64, 100]}
    ]

    # Calculate the original total duration
    original_duration = Enum.sum(Enum.map(events, fn e -> e.delta_time end))

    # Filter out pitch_bend events
    filtered_events = Filter.preserve_delta_times(events, &(&1.symbol != :pitch_bend))

    # Calculate the new total duration
    filtered_duration = Enum.sum(Enum.map(filtered_events, fn e -> e.delta_time end))

    # The total duration should be preserved
    assert filtered_duration == original_duration, "Total duration should be preserved"

    # Check specific delta_time values
    assert length(filtered_events) == 3, "Should have 3 events after filtering"

    # First event should keep its original delta_time
    assert Enum.at(filtered_events, 0).delta_time == 10

    # Second event should include the delta times of the filtered pitch_bend events
    assert Enum.at(filtered_events, 1).delta_time == 40 + 30 + 20

    # Third event should include the delta time of the last filtered pitch_bend event
    assert Enum.at(filtered_events, 2).delta_time == 60 + 50

    # Verify start times are correctly preserved
    original_start_times = Event.start_times(events)
    filtered_start_times = Event.start_times(filtered_events)

    # Only compare start times for events that weren't filtered out
    expected_start_times = [
      # note_on
      Enum.at(original_start_times, 0),
      # note_off
      Enum.at(original_start_times, 3),
      # note_on
      Enum.at(original_start_times, 5)
    ]

    assert filtered_start_times == expected_start_times,
           "Start times should be preserved for non-filtered events"
  end

  test "process_notes removes note pairs correctly" do
    # Create a test sequence with multiple notes
    events = [
      # Note on C4 (to remove)
      %Midifile.Event{symbol: :on, delta_time: 10, bytes: [0x90, 60, 100]},
      # Note on E4 (to keep)
      %Midifile.Event{symbol: :on, delta_time: 20, bytes: [0x91, 64, 100]},
      # Note on G4 (to keep)
      %Midifile.Event{symbol: :on, delta_time: 30, bytes: [0x90, 67, 100]},
      # Note off C4 (to remove)
      %Midifile.Event{symbol: :off, delta_time: 40, bytes: [0x80, 60, 0]},
      # Note off E4 (to keep)
      %Midifile.Event{symbol: :off, delta_time: 50, bytes: [0x81, 64, 0]},
      # Note off G4 (to keep)
      %Midifile.Event{symbol: :off, delta_time: 60, bytes: [0x80, 67, 0]}
    ]

    # Calculate the original total duration
    original_duration = Enum.sum(Enum.map(events, fn e -> e.delta_time end))

    # Process notes - remove only C4 (note 60)
    processed_events =
      Filter.process_note_events(
        events,
        # Match only C4
        fn note -> note == 60 end,
        # Remove the note
        :remove
      )

    # Calculate the new total duration
    processed_duration = Enum.sum(Enum.map(processed_events, fn e -> e.delta_time end))

    # The total duration should be preserved
    assert processed_duration == original_duration, "Total duration should be preserved"

    # Check the result
    assert length(processed_events) == 4, "Should have 4 events after removing C4 note pair"

    # Check that only the C4 note events were removed
    remaining_notes =
      processed_events
      |> Enum.filter(&(&1.symbol in [:on, :off]))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()

    assert Enum.sort(remaining_notes) == [64, 67], "Only notes E4 and G4 should remain"

    # Verify start times are correctly preserved
    original_start_times = Event.start_times(events)
    processed_start_times = Event.start_times(processed_events)

    # Expected start times (removing note 60 events)
    expected_start_times = [
      # E4 on
      Enum.at(original_start_times, 1),
      # G4 on
      Enum.at(original_start_times, 2),
      # E4 off
      Enum.at(original_start_times, 4),
      # G4 off
      Enum.at(original_start_times, 5)
    ]

    assert processed_start_times == expected_start_times,
           "Start times should be preserved for non-removed notes"
  end

  test "process_notes changes note pitch correctly with relative shift" do
    # Create a test sequence with multiple notes
    events = [
      # Note on C4 (to change)
      %Midifile.Event{symbol: :on, delta_time: 10, bytes: [0x90, 60, 100]},
      # Note on E4 (to keep)
      %Midifile.Event{symbol: :on, delta_time: 20, bytes: [0x91, 64, 100]},
      # Note off C4 (to change)
      %Midifile.Event{symbol: :off, delta_time: 40, bytes: [0x80, 60, 0]},
      # Note off E4 (to keep)
      %Midifile.Event{symbol: :off, delta_time: 50, bytes: [0x81, 64, 0]}
    ]

    # Process notes - shift C4 (note 60) up by 12 semitones to C5 (note 72)
    processed_events =
      Filter.process_note_events(
        events,
        # Match only C4
        fn note -> note == 60 end,
        # Shift up one octave
        {:pitch, 12}
      )

    # Check that both note on and note off events were changed to C5
    c5_events =
      processed_events
      |> Enum.filter(fn e ->
        Midifile.Event.channel(e) == 0 &&
          Midifile.Event.note(e) == 72
      end)

    assert length(c5_events) == 2, "Should have 2 events for C5"

    # Verify note on event is changed
    note_on =
      Enum.find(processed_events, fn e ->
        e.symbol == :on && Midifile.Event.channel(e) == 0
      end)

    assert note_on != nil, "Note on event should exist"
    assert Midifile.Event.note(note_on) == 72, "Note on pitch should be C5 (72)"

    # Verify note off event is changed
    note_off =
      Enum.find(processed_events, fn e ->
        e.symbol == :off && Midifile.Event.channel(e) == 0
      end)

    assert note_off != nil, "Note off event should exist"
    assert Midifile.Event.note(note_off) == 72, "Note off pitch should be C5 (72)"
  end

  test "process_notes handles pitch shifting with note range clamping" do
    # Create a test sequence with a note at the edge of MIDI range
    events = [
      # High note (to shift beyond range)
      %Midifile.Event{symbol: :on, delta_time: 10, bytes: [0x90, 120, 100]},
      # Low note (to shift below range)
      %Midifile.Event{symbol: :on, delta_time: 20, bytes: [0x91, 5, 100]},
      # High note off
      %Midifile.Event{symbol: :off, delta_time: 40, bytes: [0x80, 120, 0]},
      # Low note off
      %Midifile.Event{symbol: :off, delta_time: 50, bytes: [0x81, 5, 0]}
    ]

    # Process high notes - shift up by 20 semitones (should clamp to 127)
    high_processed_events =
      Filter.process_note_events(
        events,
        # Match high note
        fn note -> note == 120 end,
        # Shift up by 20 semitones (beyond MIDI range)
        {:pitch, 20}
      )

    # Process low notes - shift down by 20 semitones (should clamp to 0)
    low_processed_events =
      Filter.process_note_events(
        events,
        # Match low note
        fn note -> note == 5 end,
        # Shift down by 20 semitones (below MIDI range)
        {:pitch, -20}
      )

    # Verify high note is clamped to 127
    high_note_on =
      Enum.find(high_processed_events, fn e ->
        e.symbol == :on && Midifile.Event.channel(e) == 0
      end)

    assert high_note_on != nil, "High note on event should exist"

    assert Midifile.Event.note(high_note_on) == 127,
           "High note should be clamped to max MIDI value (127)"

    # Verify low note is clamped to 0
    low_note_on =
      Enum.find(low_processed_events, fn e ->
        e.symbol == :on && Midifile.Event.channel(e) == 1
      end)

    assert low_note_on != nil, "Low note on event should exist"

    assert Midifile.Event.note(low_note_on) == 0,
           "Low note should be clamped to min MIDI value (0)"
  end

  test "process_notes changes note velocity correctly" do
    # Create a test sequence with multiple notes
    events = [
      # Note on C4 (to change velocity)
      %Midifile.Event{symbol: :on, delta_time: 10, bytes: [0x90, 60, 100]},
      # Note on E4 (to keep)
      %Midifile.Event{symbol: :on, delta_time: 20, bytes: [0x91, 64, 100]},
      # Note off C4
      %Midifile.Event{symbol: :off, delta_time: 40, bytes: [0x80, 60, 0]},
      # Note off E4
      %Midifile.Event{symbol: :off, delta_time: 50, bytes: [0x81, 64, 0]}
    ]

    # Process notes - change C4 (note 60) velocity to 64
    processed_events =
      Filter.process_note_events(
        events,
        # Match only C4
        fn note -> note == 60 end,
        # Change velocity to 64
        {:velocity, 64}
      )

    # Verify note on event velocity is changed
    note_on =
      Enum.find(processed_events, fn e ->
        e.symbol == :on && Midifile.Event.channel(e) == 0 && Midifile.Event.note(e) == 60
      end)

    assert note_on != nil, "Note on event should exist"
    assert Midifile.Event.velocity(note_on) == 64, "Note on velocity should be 64"

    # Verify note off event velocity is NOT changed (still 0)
    note_off =
      Enum.find(processed_events, fn e ->
        e.symbol == :off && Midifile.Event.channel(e) == 0 && Midifile.Event.note(e) == 60
      end)

    assert note_off != nil, "Note off event should exist"
    assert Midifile.Event.velocity(note_off) == 0, "Note off velocity should still be 0"
  end

  test "process_notes handles note_on with zero velocity" do
    # Create a test sequence using note_on with zero velocity as note_off
    events = [
      # Note on C4 (to remove)
      %Midifile.Event{symbol: :on, delta_time: 10, bytes: [0x90, 60, 100]},
      # Note on E4 (to keep)
      %Midifile.Event{symbol: :on, delta_time: 20, bytes: [0x91, 64, 100]},
      # Note off C4 via note_on with velocity 0
      %Midifile.Event{symbol: :on, delta_time: 40, bytes: [0x90, 60, 0]},
      # Note off E4 via note_on with velocity 0
      %Midifile.Event{symbol: :on, delta_time: 50, bytes: [0x91, 64, 0]}
    ]

    # Process notes - remove only C4 (note 60)
    processed_events =
      Filter.process_note_events(
        events,
        # Match only C4
        fn note -> note == 60 end,
        # Remove the note
        :remove
      )

    # Check the result
    assert length(processed_events) == 2, "Should have 2 events after removing C4 note pair"

    # Check that only the C4 note events were removed
    remaining_notes =
      processed_events
      |> Enum.filter(&(&1.symbol == :on))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()

    assert remaining_notes == [64], "Only note E4 should remain"
  end

  test "process_notes works with Note struct predicates" do
    # Create a sequence with note pairs of varying durations
    sequence = %Midifile.Sequence{
      format: 1,
      # Standard MIDI ticks per quarter note
      division: 480,
      tracks: [
        %Midifile.Track{
          events: [
            # Long note - C4 with duration 480 ticks (quarter note)
            # C4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},
            # Short note - D4 with duration 120 ticks (1/16 note)
            # D4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 62, 100]},
            # D4 note_off
            %Midifile.Event{symbol: :off, delta_time: 120, bytes: [0x80, 62, 0]},
            # Medium note - E4 with duration 240 ticks (1/8 note)
            # E4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 64, 70]},
            # E4 note_off
            %Midifile.Event{symbol: :off, delta_time: 240, bytes: [0x80, 64, 0]},
            # C4 note_off
            %Midifile.Event{symbol: :off, delta_time: 120, bytes: [0x80, 60, 0]}
          ]
        }
      ]
    }

    # Filter out short notes (less than 200 ticks duration)
    filtered_sequence =
      Filter.process_notes(
        sequence,
        0,
        # Match notes shorter than 200 ticks
        fn note -> note.duration < 200 end,
        # Remove these notes
        :remove
      )

    filtered_events = List.first(filtered_sequence.tracks).events

    # Should have 4 events left (C4 note_on/off and E4 note_on/off)
    assert length(filtered_events) == 4

    # Check that D4 is gone and C4/E4 remain
    remaining_notes =
      filtered_events
      |> Enum.filter(&(&1.symbol in [:on, :off]))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()
      |> Enum.sort()

    assert remaining_notes == [60, 64], "Only C4 and E4 should remain (D4 should be removed)"

    # Filter by velocity
    velocity_filtered =
      Filter.process_notes(
        sequence,
        0,
        # Match notes with low velocity (C4:80, E4:70) for removal
        fn note -> note.velocity < 90 end,
        # Remove these notes
        :remove
      )

    velocity_events = List.first(velocity_filtered.tracks).events

    # Should have removed C4 and E4 (low velocity), leaving only D4
    remaining_vel_notes =
      velocity_events
      |> Enum.filter(&(&1.symbol in [:on, :off]))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()

    assert remaining_vel_notes == [62], "Only D4 should remain (velocity 100)"
  end
end
