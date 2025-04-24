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
    assert length(filtered_track.events) == length(original_track.events) - original_pitch_bend_count
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
      Enum.at(original_start_times, 0),  # note_on
      Enum.at(original_start_times, 3),  # note_off
      Enum.at(original_start_times, 5)   # note_on
    ]
    
    assert filtered_start_times == expected_start_times, "Start times should be preserved for non-filtered events"
  end
end