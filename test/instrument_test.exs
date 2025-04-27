defmodule InstrumentTest do
  use ExUnit.Case
  
  test "identify instruments in MIDI file" do
    # Use the existing CSV mapping and a MIDI file from the test directory
    map_file_path = "midi_percussion_mapping.csv"
    midi_file_path = "test/folk1.mid"
    
    instruments = Midifile.Util.identify_instruments(map_file_path, midi_file_path)
    
    # Verify the result is a list of {key_number, note, sound_name} tuples
    assert is_list(instruments)
    
    unless Enum.empty?(instruments) do
      {key_number, note, sound_name} = List.first(instruments)
      assert is_integer(key_number)
      assert is_binary(note)
      assert is_binary(sound_name)
      
      # Verify the list is sorted by key_number
      key_numbers = instruments |> Enum.map(fn {k, _, _} -> k end)
      assert key_numbers == Enum.sort(key_numbers)
    end
    
    # Print the identified instruments for manual verification
    IO.puts("\nIdentified instruments in #{midi_file_path}:")
    Enum.each(instruments, fn {key, note, name} ->
      IO.puts("Key: #{key}, Note: #{note}, Sound: #{name}")
    end)
  end
end