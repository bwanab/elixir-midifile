defmodule Midifile.UtilTest do
  use ExUnit.Case
  
  test "map_drums correctly remaps drum notes in folk1.mid" do
    input_path = "test/folk1.mid"
    output_path = "test/folk1_trans.mid"
    
    # Delete output file if it already exists
    if File.exists?(output_path) do
      File.rm!(output_path)
    end
    
    # Run the map_drums function
    result_path = Midifile.Util.map_drums(input_path, output_path)
    
    # Assert the output file was created
    assert File.exists?(output_path)
    assert result_path == output_path
    
    # Read both files to compare
    original = Midifile.read(input_path)
    transformed = Midifile.read(output_path)
    
    # The files should have the same number of tracks
    assert length(original.tracks) == length(transformed.tracks)
    
    # Get all note events from all tracks
    original_notes = extract_all_notes(original)
    transformed_notes = extract_all_notes(transformed)
    
    # Verify mappings
    Enum.zip(original_notes, transformed_notes)
    |> Enum.each(fn {orig, trans} ->
      case orig.note do
        40 -> assert trans.note == 38  # Snare mapping
        35 -> assert trans.note == 36  # Bass drum mapping
        44 -> assert trans.note == 42  # Pedal high-hat mapping
        other -> assert trans.note == other  # Other notes should remain unchanged
      end
    end)
    
    # Clean up - delete the output file
    File.rm!(output_path)
  end
  
  # Extract all note events from all tracks in a sequence
  defp extract_all_notes(sequence) do
    # For format 0 files, check the conductor track
    conductor_notes = extract_note_events(sequence.conductor_track.events)
    
    # Collect notes from all tracks
    track_notes = sequence.tracks
                  |> Enum.flat_map(fn track -> extract_note_events(track.events) end)
    
    # Combine notes from conductor and tracks, sort by start time if needed
    conductor_notes ++ track_notes
  end
  
  # Helper function to extract note events with relevant data for comparison
  defp extract_note_events(events) do
    events
    |> Enum.filter(&Midifile.Event.note?/1)
    |> Enum.map(fn event -> 
      %{
        note: Midifile.Event.note(event),
        symbol: event.symbol,
        delta_time: event.delta_time
      }
    end)
  end
end