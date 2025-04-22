defmodule Midifile.Writer do

  import Bitwise
  alias Midifile.Sequence
  alias Midifile.Track
  alias Midifile.Event
  alias Midifile.Varlen

  # Channel messages
  @status_nibble_off 0x8
  @status_nibble_on 0x9

  # Meta events
  @status_meta_event 0xFF
  @meta_seq_num 0x00
  @meta_text 0x01
  @meta_copyright 0x02
  @meta_seq_name 0x03
  @meta_instrument 0x04
  @meta_lyric 0x05
  @meta_marker 0x06
  @meta_cue 0x07
  @meta_midi_chan_prefix 0x20
  @meta_track_end 0x2f
  @meta_set_tempo 0x51
  @meta_smpte 0x54
  @meta_time_sig 0x58
  @meta_key_sig 0x59
  @meta_sequencer_specific 0x7F

  @moduledoc """
  MIDI file writer.
  """

  def write(%Sequence{format: format, division: division, conductor_track: ct, tracks: tracks}, path) do
    l = [header_io_list(format, division, length(tracks) + 1) |
  	     Enum.map([ct | tracks], &track_io_list/1)]
    :ok = :file.write_file(path, IO.iodata_to_binary(l))
  end

  def header_io_list(_format, division, num_tracks) do
    [?M, ?T, ?h, ?d,
     0, 0, 0, 6,                  # header chunk size
     0, 1,                        # format,
     (num_tracks >>> 8) &&& 255, # num tracks
      num_tracks        &&& 255,
     (division >>> 8) &&& 255, # division
      division        &&& 255]
  end

  def track_io_list(%Track{events: events}) do
    initial_state = %{status: 0, chan: 0}
    {event_list, _final_state} = Enum.map_reduce(events, initial_state, 
      fn(event, state) -> event_io_list(event, state) end)
    size = chunk_size(event_list)
    [?M, ?T, ?r, ?k,
     (size >>> 24) &&& 255,
     (size >>> 16) &&& 255,
     (size >>>  8) &&& 255,
      size         &&& 255,
      event_list]
  end

  # Return byte size of L, which is an IO list that contains lists, bytes, and
  # binaries.
  def chunk_size(l) do
    acc = 0
    List.foldl(List.flatten(l), acc, fn(e, acc) -> acc + io_list_element_size(e) end)
  end

  def io_list_element_size(e) when is_binary(e), do: byte_size(e)

  def io_list_element_size(_e), do: 1

  def event_io_list(%Event{symbol: :off, delta_time: delta_time, bytes: [status, note, vel]}, state) do
    chan = status &&& 0x0f
    %{status: running_status, chan: running_chan} = state
    {status_bytes, outvel, new_state} = if running_chan == chan and
                          (running_status == @status_nibble_off or
  	                       (running_status == @status_nibble_on and vel == 64)) do
      # If we see a note off and the velocity is 64, we can store a note on
      # with a velocity of 0. If the velocity isn't 64 then storing a note
      # on would be bad because the would be changed to 64 when reading the
      # file back in.
      {[], 0, state}                   # do not output a status
    else
  	  new_state = %{status: @status_nibble_off, chan: chan}
  	  {(@status_nibble_off <<< 4) + chan, vel, new_state}
    end
    {[Varlen.write(delta_time), status_bytes, note, outvel], new_state}
  end

  def event_io_list(%Event{symbol: :on, delta_time: delta_time, bytes: [status, note, vel]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, note, vel], new_state}
  end
  
  def event_io_list(%Event{symbol: :poly_press, delta_time: delta_time, bytes: [status, note, amount]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, note, amount], new_state}
  end
  
  def event_io_list(%Event{symbol: :controller, delta_time: delta_time, bytes: [status, controller, value]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, controller, value], new_state}
  end
  
  def event_io_list(%Event{symbol: :program, delta_time: delta_time, bytes: [status, program]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, program], new_state}
  end
  
  def event_io_list(%Event{symbol: :chan_press, delta_time: delta_time, bytes: [status, amount]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, amount], new_state}
  end

  def event_io_list(%Event{symbol: :pitch_bend, delta_time: delta_time, bytes: [status, <<0::size(2), msb::size(7), lsb::size(7)>>]}, state) do
    {status_bytes, new_state} = running_status(status, state)
    {[Varlen.write(delta_time), status_bytes, <<0::size(1), lsb::size(7), 0::size(1), msb::size(7)>>], new_state}
  end

  def event_io_list(%Event{symbol: :track_end, delta_time: delta_time, bytes: _}, _state) do
    new_state = %{status: @status_meta_event, chan: 0}
    {[Varlen.write(delta_time), @status_meta_event, @meta_track_end, 0], new_state}
  end

  def event_io_list(%Event{symbol: :seq_num, delta_time: delta_time, bytes: data}, state),            do: meta_io_list(delta_time, @meta_seq_num, data, state)
  def event_io_list(%Event{symbol: :text, delta_time: delta_time, bytes: data}, state),               do: meta_io_list(delta_time, @meta_text, data, state)
  def event_io_list(%Event{symbol: :copyright, delta_time: delta_time, bytes: data}, state),          do: meta_io_list(delta_time, @meta_copyright, data, state)
  def event_io_list(%Event{symbol: :seq_name, delta_time: delta_time, bytes: data}, state),           do: meta_io_list(delta_time, @meta_seq_name, data, state)
  def event_io_list(%Event{symbol: :instrument, delta_time: delta_time, bytes: data}, state),         do: meta_io_list(delta_time, @meta_instrument, data, state)
  def event_io_list(%Event{symbol: :lyric, delta_time: delta_time, bytes: data}, state),              do: meta_io_list(delta_time, @meta_lyric, data, state)
  def event_io_list(%Event{symbol: :marker, delta_time: delta_time, bytes: data}, state),             do: meta_io_list(delta_time, @meta_marker, data, state)
  def event_io_list(%Event{symbol: :cue, delta_time: delta_time, bytes: data}, state),                do: meta_io_list(delta_time, @meta_cue, data, state)
  def event_io_list(%Event{symbol: :midi_chan_prefix, delta_time: delta_time, bytes: [data]}, state), do: meta_io_list(delta_time, @meta_midi_chan_prefix, data, state)

  def event_io_list(%Event{symbol: :tempo, delta_time: delta_time, bytes: [data]}, _state) do
    new_state = %{status: @status_meta_event, chan: 0}
    {[Varlen.write(delta_time), @status_meta_event, @meta_set_tempo, Varlen.write(3),
     (data >>> 16) &&& 255,
     (data >>>  8) &&& 255,
      data         &&& 255], new_state}
  end

  def event_io_list(%Event{symbol: :smpte, delta_time: delta_time, bytes: [data]}, state),              do: meta_io_list(delta_time, @meta_smpte, data, state)
  def event_io_list(%Event{symbol: :time_signature, delta_time: delta_time, bytes: [data]}, state),     do: meta_io_list(delta_time, @meta_time_sig, data, state)
  def event_io_list(%Event{symbol: :key_signature, delta_time: delta_time, bytes: [data]}, state),      do: meta_io_list(delta_time, @meta_key_sig, data, state)
  def event_io_list(%Event{symbol: :sequencer_specific, delta_time: delta_time, bytes: [data]}, state), do: meta_io_list(delta_time, @meta_sequencer_specific, data, state)
  def event_io_list(%Event{symbol: :unknown_meta, delta_time: delta_time, bytes: [type, data]}, state), do: meta_io_list(delta_time, type, data, state)

  def meta_io_list(delta_time, type, data, _state) when is_binary(data) do
    new_state = %{status: @status_meta_event, chan: 0}
    {[Varlen.write(delta_time), @status_meta_event, type, Varlen.write(byte_size(data)), data], new_state}
  end

  def meta_io_list(delta_time, type, data, _state) do
    new_state = %{status: @status_meta_event, chan: 0}
    {[Varlen.write(delta_time), @status_meta_event, type, Varlen.write(length(data)), data], new_state}
  end

  def running_status(status, state) do
    %{status: running_status, chan: running_chan} = state
    high_nibble = status >>> 4
    chan = status &&& 0x0f
    if running_status == high_nibble and running_chan == chan do
  	    {[], state}                      # do not output a byte, keep same state
    else
  	    new_state = %{status: high_nibble, chan: chan}
        {status, new_state}
    end
  end
end
