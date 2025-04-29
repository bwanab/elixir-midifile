defmodule Midifile.Reader do

  import Bitwise
  alias Midifile.Sequence
  alias Midifile.Track
  alias Midifile.Event
  alias Midifile.Varlen

  @moduledoc """
  MIDI file reader.
  """
  
  @debug false

  # Channel messages
  @status_nibble_off 0x8
  @status_nibble_on 0x9
  @status_nibble_poly_press 0xA
  @status_nibble_controller 0xB
  @status_nibble_program_change 0xC
  @status_nibble_channel_pressure 0xD
  @status_nibble_pitch_bend 0xE

  # System common messages
  @status_sysex 0xF0

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

  @doc """
  Returns a Sequence record.
  Handles both format 0 (single track) and format 1 (multiple tracks) MIDI files.
  Format 0 files are converted to format 1 internally with a conductor track and a data track.
  """
  def read(path) do
    {:ok, f} = File.open(path, [:read, :binary])
    pos = look_for_chunk(f, 0, "MThd", :file.pread(f, 0, 4))
    [{:header, format, division}, num_tracks] = parse_header(:file.pread(f, pos, 10))
    tracks = read_tracks(f, num_tracks, pos + 10, [])
    File.close(f)
    
    # Parse the division value to determine time basis and related values
    time_basis_values = Sequence.parse_division(division)
    
    case {format, tracks} do
      # Format 0: Single track containing all MIDI data
      {0, [single_track]} ->
        # Extract metadata events for conductor track
        {meta_events, content_events} = split_track_events(single_track.events)
        
        # Create conductor track with metadata
        conductor_track = %Track{name: "Conductor Track", events: meta_events}
        
        # Create content track with the remaining events
        content_track = %Track{name: single_track.name, events: content_events}
        
        # Return a format 1 sequence
        %Sequence{
          format: 1, 
          # Set the time basis properties
          time_basis: time_basis_values.time_basis,
          ticks_per_quarter_note: time_basis_values.ticks_per_quarter_note,
          smpte_format: time_basis_values.smpte_format,
          ticks_per_frame: time_basis_values.ticks_per_frame,
          # Set tracks
          conductor_track: conductor_track, 
          tracks: [content_track]
        }
                  
      # Format 1: Multiple tracks with first track as conductor
      {1, [conductor_track | remaining_tracks]} ->
        %Sequence{
          format: format, 
          # Set the time basis properties
          time_basis: time_basis_values.time_basis,
          ticks_per_quarter_note: time_basis_values.ticks_per_quarter_note,
          smpte_format: time_basis_values.smpte_format,
          ticks_per_frame: time_basis_values.ticks_per_frame,
          # Set tracks
          conductor_track: conductor_track, 
          tracks: remaining_tracks
        }
                  
      # Other cases (should not normally occur)
      {_, tracks} ->
        [conductor_track | remaining_tracks] = tracks
        %Sequence{
          format: format, 
          # Set the time basis properties
          time_basis: time_basis_values.time_basis,
          ticks_per_quarter_note: time_basis_values.ticks_per_quarter_note,
          smpte_format: time_basis_values.smpte_format,
          ticks_per_frame: time_basis_values.ticks_per_frame,
          # Set tracks
          conductor_track: conductor_track, 
          tracks: remaining_tracks
        }
    end
  end
  
  # Splits a track's events into metadata events (for conductor track) and content events
  defp split_track_events(events) do
    # Find track name if it exists
    track_name_event = Enum.find(events, fn event -> event.symbol == :seq_name end)
    
    # Extract metadata events - tempo, time signature, key signature, etc.
    meta_events = events
                  |> Enum.filter(fn event -> 
                       event.symbol in [:tempo, :time_signature, :key_signature, :track_end]
                     end)
    
    # Add track name to metadata if found
    meta_events = if track_name_event, do: [track_name_event | meta_events], else: meta_events
    
    # Get non-metadata events for content track (exclude meta events that went to conductor)
    content_events = events 
                     |> Enum.filter(fn event -> 
                          not (event.symbol in [:tempo, :time_signature, :key_signature]) and
                          (event != track_name_event)
                        end)
    
    # Ensure both tracks have track_end events
    meta_events = ensure_track_end(meta_events)
    content_events = ensure_track_end(content_events)
    
    {meta_events, content_events}
  end
  
  # Ensures a track has a track_end event
  defp ensure_track_end(events) do
    has_track_end = Enum.any?(events, fn event -> event.symbol == :track_end end)
    if has_track_end do
      events
    else
      # Add a track_end event with delta_time 0
      events ++ [%Event{symbol: :track_end, delta_time: 0, bytes: []}]
    end
  end

  defp debug(msg) do
    if @debug, do: IO.puts(msg), else: nil
  end

  # Only reason this is a macro is for speed.
  defmacro chan_status(status_nibble, chan) do
    quote do: (unquote(status_nibble) <<< 4) + unquote(chan)
  end

  # Look for Cookie in file and return file position after Cookie.
  defp look_for_chunk(_f, pos, cookie, {:ok, cookie}) do
    debug("look_for_chunk")
    pos + byte_size(cookie)
  end

  defp look_for_chunk(f, pos, cookie, {:ok, _}) do
    debug("look_for_chunk")
    # This isn't efficient, because we only advance one character at a time.
    # We should really look for the first char in Cookie and, if found,
    # advance that far.
    look_for_chunk(f, pos + 1, cookie, :file.pread(f, pos + 1, byte_size(cookie)))
  end

  defp parse_header({:ok, <<_bytes_to_read::size(32), format::size(16), num_tracks::size(16), division::size(16)>>}) do
    debug("parse_header")
    [{:header, format, division}, num_tracks]
  end

  defp read_tracks(_f, 0, _pos, tracks) do
    debug("read_tracks")
    :lists.reverse(tracks)
  end

  # TODO: make this distributed. Would need to scan each track to get start
  # position of next track.

  defp read_tracks(f, num_tracks, pos, tracks) do
    debug("read_tracks")
    [track, next_track_pos] = read_track(f, pos)
    read_tracks(f, num_tracks - 1, next_track_pos, [track|tracks])
  end

  defp read_track(f, pos) do
    debug("read_track")
    track_start = look_for_chunk(f, pos, "MTrk", :file.pread(f, pos, 4))
    bytes_to_read = parse_track_header(:file.pread(f, track_start, 4))
    initial_state = %{status: 0, chan: -1}
    {events, _final_state} = event_list(f, track_start + 4, bytes_to_read, [], initial_state)
    [%Track{events: events}, track_start + 4 + bytes_to_read]
  end

  defp parse_track_header({:ok, <<bytes_to_read::size(32)>>}) do
    debug("parse_track_header")
    bytes_to_read
  end

  defp event_list(_f, _pos, 0, events, state) do
    debug("event_list")
    {Enum.reverse(events), state}
  end

  defp event_list(f, pos, bytes_to_read, events, state) do
    debug("event_list")
    {:ok, bin} = :file.pread(f, pos, 4)
    [delta_time, var_len_bytes_used] = Varlen.read(bin)
    {:ok, three_bytes} = :file.pread(f, pos + var_len_bytes_used, 3)
    {event, event_bytes_read, new_state} = read_event(f, pos + var_len_bytes_used, delta_time, three_bytes, state)
    bytes_read = var_len_bytes_used + event_bytes_read
    event_list(f, pos + bytes_read, bytes_to_read - bytes_read, [event|events], new_state)
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_off::size(4), chan::size(4), note::size(8), vel::size(8)>>, _state) do
    debug("read_event <<@status_nibble_off::size(4), chan::size(4), note::size(8), vel::size(8)>>")
    new_state = %{status: @status_nibble_off, chan: chan}
    {%Event{symbol: :off, delta_time: delta_time, bytes: [chan_status(@status_nibble_off, chan), note, vel]}, 3, new_state}
  end

  # note on, velocity 0 is a note off
  defp read_event(_f, _pos, delta_time, <<@status_nibble_on::size(4), chan::size(4), note::size(8), 0::size(8)>>, _state) do
    debug("read_event <<@status_nibble_on::size(4), chan::size(4), note::size(8), 0::size(8)>>")
    new_state = %{status: @status_nibble_on, chan: chan}
    {%Event{symbol: :off, delta_time: delta_time, bytes: [chan_status(@status_nibble_off, chan), note, 64]}, 3, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_on::size(4), chan::size(4), note::size(8), vel::size(8)>>, _state) do
    debug("read_event <<@status_nibble_on::size(4), chan::size(4), note::size(8), vel::size(8)>>")
    new_state = %{status: @status_nibble_on, chan: chan}
    {%Event{symbol: :on, delta_time: delta_time, bytes: [chan_status(@status_nibble_on, chan), note, vel]}, 3, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_poly_press::size(4), chan::size(4), note::size(8), amount::size(8)>>, _state) do
    debug("read_event <<@status_nibble_poly_press::size(4), chan::size(4), note::size(8), amount::size(8)>>")
    new_state = %{status: @status_nibble_poly_press, chan: chan}
    {%Event{symbol: :poly_press, delta_time: delta_time, bytes: [chan_status(@status_nibble_poly_press, chan), note, amount]}, 3, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_controller::size(4), chan::size(4), controller::size(8), value::size(8)>>, _state) do
    debug("read_event <<@status_nibble_controller::size(4), chan::size(4), controller::size(8), value::size(8)>>")
    new_state = %{status: @status_nibble_controller, chan: chan}
    {%Event{symbol: :controller, delta_time: delta_time, bytes: [chan_status(@status_nibble_controller, chan), controller, value]}, 3, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_program_change::size(4), chan::size(4), program::size(8), _::size(8)>>, _state) do
    debug("read_event <<@status_nibble_program_change::size(4), chan::size(4), program::size(8), _::size(8)>>")
    new_state = %{status: @status_nibble_program_change, chan: chan}
    {%Event{symbol: :program, delta_time: delta_time, bytes: [chan_status(@status_nibble_program_change, chan), program]}, 2, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_channel_pressure::size(4), chan::size(4), amount::size(8), _::size(8)>>, _state) do
    debug("read_event <<@status_nibble_channel_pressure::size(4), chan::size(4), amount::size(8), _::size(8)>>")
    new_state = %{status: @status_nibble_channel_pressure, chan: chan}
    {%Event{symbol: :chan_press, delta_time: delta_time, bytes: [chan_status(@status_nibble_channel_pressure, chan), amount]}, 2, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_nibble_pitch_bend::size(4), chan::size(4), 0::size(1), lsb::size(7), 0::size(1), msb::size(7)>>, _state) do
    debug("read_event <<@status_nibble_pitch_bend::size(4), chan::size(4), 0::size(1), lsb::size(7), 0::size(1), msb::size(7)>>")
    new_state = %{status: @status_nibble_pitch_bend, chan: chan}
    {%Event{symbol: :pitch_bend, delta_time: delta_time, bytes: [chan_status(@status_nibble_pitch_bend, chan), <<0::size(2), msb::size(7), lsb::size(7)>>]}, 3, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<@status_meta_event::size(8), @meta_track_end::size(8), 0::size(8)>>, _state) do
    debug("read_event <<@status_meta_event::size(8), @meta_track_end::size(8), 0::size(8)>>")
    new_state = %{status: @status_meta_event, chan: 0}
    {%Event{symbol: :track_end, delta_time: delta_time, bytes: []}, 3, new_state}
  end

  defp read_event(f, pos, delta_time, <<@status_meta_event::size(8), type::size(8), _::size(8)>>, _state) do
    debug("read_event <<@status_meta_event::size(8), type::size(8), _::size(8)>>")
    new_state = %{status: @status_meta_event, chan: 0}
    {:ok, bin} = :file.pread(f, pos + 2, 4)
    [length, length_bytes_used] = Varlen.read(bin)
    length_before_data = length_bytes_used + 2
    {:ok, data} = :file.pread(f, pos + length_before_data, length)
    total_length = length_before_data + length
    event_and_bytes = case type do
      @meta_seq_num ->
        debug("@meta_seq_num")
        {%Event{symbol: :seq_num, delta_time: delta_time, bytes: [data]}, total_length}
      @meta_text ->
        debug("@meta_text")
        {%Event{symbol: :text, delta_time: delta_time, bytes: data}, total_length}
      @meta_copyright ->
        debug("@meta_copyright")
        {%Event{symbol: :copyright, delta_time: delta_time, bytes: data}, total_length}
      @meta_seq_name ->
        debug("@meta_seq_name")
        {%Event{symbol: :seq_name, delta_time: delta_time, bytes: data}, total_length}
      @meta_instrument ->
        debug("@meta_instrument")
        {%Event{symbol: :instrument, delta_time: delta_time, bytes: data}, total_length}
      @meta_lyric ->
        debug("@meta_lyric")
        {%Event{symbol: :lyric, delta_time: delta_time, bytes: data}, total_length}
      @meta_marker ->
        debug("@meta_marker")
        {%Event{symbol: :marker, delta_time: delta_time, bytes: data}, total_length}
      @meta_cue ->
        debug("@meta_cue")
        {%Event{symbol: :cue, delta_time: delta_time, bytes: data}, total_length}
      @meta_midi_chan_prefix ->
        debug("@meta_midi_chan_prefix")
        {%Event{symbol: :midi_chan_prefix, delta_time: delta_time, bytes: [data]}, total_length}
      @meta_set_tempo ->
        debug("@meta_set_tempo")
        # data is microseconds per quarter note, in three bytes
        <<b0::size(8), b1::size(8), b2::size(8)>> = data
        {%Event{symbol: :tempo, delta_time: delta_time, bytes: [(b0 <<< 16) + (b1 <<< 8) + b2]}, total_length}
      @meta_smpte ->
        debug("@meta_smpte")
        {%Event{symbol: :smpte, delta_time: delta_time, bytes: [data]}, total_length}
      @meta_time_sig ->
        debug("@meta_time_sig")
        {%Event{symbol: :time_signature, delta_time: delta_time, bytes: [data]}, total_length}
      @meta_key_sig ->
        debug("@meta_key_sig")
        {%Event{symbol: :key_signature, delta_time: delta_time, bytes: [data]}, total_length}
      @meta_sequencer_specific ->
        debug("@meta_sequencer_specific")
        {%Event{symbol: :seq_name, delta_time: delta_time, bytes: [data]}, total_length}
      unknown ->
        debug("unknown meta")
        IO.puts("unknown == #{unknown}") # DEBUG
        {%Event{symbol: :unknown_meta, delta_time: delta_time, bytes: [type, data]}, total_length}
    end
    
    {event, bytes} = event_and_bytes
    {event, bytes, new_state}
  end

  defp read_event(f, pos, delta_time, <<@status_sysex::size(8), _::size(16)>>, _state) do
    debug("read_event <<@status_sysex::size(8), _::size(16)>>")
    new_state = %{status: @status_sysex, chan: 0}
    {:ok, bin} = :file.pread(f, pos + 1, 4)
    [length, length_bytes_used] = Varlen.read(bin)
    {:ok, data} = :file.pread(f, pos + length_bytes_used, length)
    {%Event{symbol: :sysex, delta_time: delta_time, bytes: [data]}, length_bytes_used + length, new_state}
  end

  # Handle running status bytes
  defp read_event(f, pos, delta_time, <<b0::size(8), b1::size(8), _::size(8)>>, state) when b0 < 128 do
    debug("read_event <<b0::size(8), b1::size(8), _::size(8)>>")
    %{status: status, chan: chan} = state
    {event, num_bytes, new_state} = read_event(f, pos, delta_time, <<status::size(4), chan::size(4), b0::size(8), b1::size(8)>>, state)
    {event, num_bytes - 1, new_state}
  end

  defp read_event(_f, _pos, delta_time, <<unknown::size(8), _::size(16)>>, _state) do
    debug("read_event <<unknown::size(8), _::size(16)>>, unknown = #{unknown}")
    new_state = %{status: 0, chan: 0}
    # Using raise instead of exit with string concatenation
    # exit("unknown status byte " ++ unknown).
    {%Event{symbol: :unknown_status, delta_time: delta_time, bytes: [unknown]}, 3, new_state}
  end

end
