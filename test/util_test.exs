defmodule Midifile.UtilTest do
  use ExUnit.Case

  test "map_drums correctly remaps drum notes using CSV mapping file" do
    map_file_path = "Yamaha_QY10_map.csv"
    input_path = "test/folk1.mid"
    output_path = "test/folk1_trans.mid"

    # Delete output file if it already exists
    if File.exists?(output_path) do
      File.rm!(output_path)
    end

    # Run the map_drums function with the CSV file
    result_path = Midifile.Util.map_drums(map_file_path, 0, input_path, output_path)

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

    # Read expected mappings from CSV
    mappings = Midifile.Util.read_mappings(map_file_path)
    mapping_map = Enum.into(mappings, %{}, fn {_item, from, to} -> {from, to} end)

    # Verify mappings
    Enum.zip(original_notes, transformed_notes)
    |> Enum.each(fn {orig, trans} ->
      expected_note = Map.get(mapping_map, orig.note, orig.note)
      assert trans.note == expected_note
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
