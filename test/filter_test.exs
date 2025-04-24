defmodule Midifile.FilterTest do
  use ExUnit.Case

  alias Midifile.Filter

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
end