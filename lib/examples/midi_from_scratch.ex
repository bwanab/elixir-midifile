defmodule Examples.MidiFromScratch do
  alias Midifile.Track
  alias Midifile.Sequence
  alias Midifile.Writer
  import MusicPrims

  # creates a C major scale where each note has a duration of 1 quarter note and writes it to a midifile.
  def midifile_from_scratch() do
    c_major = major_scale(:C, 4)
    write_midi_file(c_major, "c_major_scale")
  end

  # this is only for testing. The only case it can add a rest assumes all the notes are 1 quarter note and
  # it only adds at the beginning of the qn. More advanced uses must be "by hand" or are use cases for
  # a later date.
  def midifile_with_rest() do
    c_major = major_scale(:C, 4)
    {c_major, _td} = add_rest_at_keeping_total_duration(c_major, 0, 0.5)
    write_midi_file(c_major, "c_major_scale_with_rest")
  end

  # this is an example of building a chord sequence mixed with a rest and a two note melody line.
  # don't expect it do sound good :)
  def midi_file_mixed_chords_notes_rests() do
    sonorities = [
      Chord.new({{:C, 4}, :major}, 1),
      Chord.new({{:D, 4}, :minor}, 1),
      Rest.new(1),
      Note.new({:A, 4}, duration: 1),
      Note.new({:B, 4}, duration: 1)
    ]
    write_midi_file(sonorities, "with chords")
  end


  # this creates a chord sequence with 10 measures. There is randomness in the computation of the series,
  # but it is built on a foundation of logical chord sequences so add this to a midi player with an
  # appropriate string/organ/brass like instrument and it should sound pleasing albeit possibly incipid.
  @spec midi_file_from_chord_progression() :: :ok
  def midi_file_from_chord_progression() do
    chords = Enum.map(ChordPrims.random_progression(10, 1), &(ChordPrims.chord_sym_to_chord(&1, {{:C, 4}, :major})))
      |> Enum.map(&(Chord.new(&1, 4)))
    write_midi_file(chords, "random_progression")
  end
  def write_midi_file(notes, name) do
    track = Track.new(name, notes, 960)
    sfs = Sequence.new(name, 110, [track], 960)
    Writer.write(sfs, "test/#{name}.mid")
  end

  def add_rest_at_keeping_total_duration(ms, pos, duration) do
    note = Enum.at(ms, pos)

    {ms, _td} = change_dur_at(ms, pos, note.duration - duration)
    add_rest_at(ms, pos + 1, duration)
  end
  def add_rest_at(ms, pos, duration) do
    ms = List.insert_at(ms, pos, Note.rest(duration))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end

  def change_dur_at(ms, pos, duration) do
    note = Enum.at(ms, pos)
    ms = List.replace_at(ms, pos, Note.new(note.note, duration: duration, velocity: note.velocity))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end
end
