#!/usr/bin/env ruby

require 'socket'
require 'monitor'
require_relative '../ext/string'
require_relative 'logger'

# https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
# https://apidock.com/ruby/Array/pack
# https://apidock.com/ruby/String/unpack

# Packet structure:
# Field         | Type                                | Value
# ----------------------------------------------------------------------
# Size          | 32-bit little-endian Signed Integer (l<) | Varies, see below.
# ID            | 32-bit little-endian Signed Integer (l<) | Varies, see below.
# Type          | 32-bit little-endian Signed Integer (l<) | Varies, see below.
# Body          | Null-terminated ASCII String        (Z*) | Varies, see below.
# Empty String  | Null-terminated ASCII String        (Z*) | 0x00

# Packet size:
# The packet size field is a 32-bit little endian integer, representing the length of the request in bytes.
# Note that the packet size field itself is not included when determining the size of the packet, so the value
# of this field is always 4 less than the packet's actual length. The minimum possible value for packet size is 10:

# Size            | Containing
# 4 Bytes         | ID Field
# 4 Bytes         | Type Field
# At least 1 Byte | Packet body (potentially empty)
# 1 Bytes         | Empty string terminator

class NoTCPResponseError < StandardError
  def initialize(host=nil)
    super "Could not read a TCP response from server#{host ? " #{host}" : '!'}"
  end
end

class TCPSocketError < StandardError
  def initialize(msg=nil)
    super msg
  end
end

class RconSocket < Socket
  attr_reader :mutex

  def initialize(ip, port, password, timeout=3)
    @mutex = Mutex.new
    @rcon_ip = ip
    @rcon_port = port
    @rcon_password = password

    addr = Socket.getaddrinfo(ip, nil)
    sockaddr = Socket.pack_sockaddr_in(port, addr[0][3])

    super(Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0).tap do |socket|
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      begin
        socket.connect_nonblock(sockaddr)
      rescue IO::WaitWritable
        if IO.select(nil, [socket], nil, timeout)
          begin
            socket.connect_nonblock(sockaddr)
          rescue Errno::EISCONN
            # Connected
          rescue
            socket.close
            raise
          end
        else
          # IO.select returns nil when the socket is not ready before timeout
          # seconds have elapsed
          socket.close
          raise "Connection to #{socket.remote_host} timed out."
        end
      end
    end
  end

  def info
    return @rcon_ip, @rcon_port, @rcon_password
  end

  def remote_host
    "#{@rcon_ip}:#{@rcon_port}"
  end
end

# Handles holding open RCON connections to each server and sending commands
class RconClient
  include Logging
  attr_reader :sockets

  @@pack_string = 'l<l<l<Z*Z*'
  @@empty_packet = "\n\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  @sockets = {}

  def initialize
    @sockets = {}
    @mutex = Mutex.new
  end

  def synchronize(mutex=@mutex, &block)
    mutex.synchronize(&block)
  end

  def put_socket(remote_address, socket)
    synchronize do
      delete_socket @sockets[remote_address] if @sockets[remote_address]
      @sockets[remote_address] = socket
    end
  end

  def get_socket(remote_address)
    synchronize do
      @sockets[remote_address]
    end
  end

  def open_socket(server_ip, port, password)
    logger.debug("Opening socket to #{server_ip}:#{port}")
    socket = RconSocket.new server_ip, port, password
    return socket unless password
    if authenticate socket, password
      "127.0.0.1:27015" => socket
      put_socket socket.remote_address.inspect_sockaddr, socket
      return socket
    end
  rescue => e
    logger.warn("Failed to open socket to #{server_ip}:#{port} (#{e.class}) #{e.message}")
    raise
  end

  def authenticate(socket, password)
    # "If the rcon_password cvar is not set, or if it is set to empty string, all SERVERDATA_AUTH requests will be refused."
    # Currently we assume there is always a password.
    logger.debug("#{socket.remote_host.ljust(21)} Authenticating RCON connection")
    packet = build_packet(password, 3, hide_content: true) # Type 3 for auth packet
    id = send_receive_wrapper socket, packet, sensitive: true
    raise Errno::ENOTCONN if id.nil?
    raise "Failed to authenticate. Bad RCON password?" if id == -1
    logger.debug("#{socket.remote_host.ljust(21)} Successfully authenticated.")
    true
  rescue Errno::ENOTCONN => e
    logger.warn("#{socket.remote_host.ljust(21)} Failed to connect with RCON: (#{e.class}) #{e.message}")
    delete_socket socket
    raise
  end

  def close
    @sockets.each do |host, socket|
      logger.debug("Closing socket to #{host}")
      delete_socket socket
    end
    logger.debug("All sockets closed.")
  end

  def get_socket_for_host(server_ip, port, password)
    socket = get_socket "#{server_ip}:#{port}"
    socket = open_socket server_ip, port, password if socket.nil?
    begin
      socket.remote_address # see if we're connected
    rescue Errno::ENOTCONN
      socket = reopen_socket socket
    end
    socket
  end

  def build_packet(body, type=2, id=1, hide_content: false)
    # packet = [0xFF, 0xFF, 0xFF, 0xFF, a2s_info_header, content].pack('c5Z*')
    # packet = [0xFF, 0xFF, 0xFF, 0xFF, 0x55, -1].pack('cccccl_')
    packet_id = id # This can be any positive integer and can be used to match responses with requests if desired. Need not be unique.
    packet_type = type
    packet_body = body
    packet_empty_string = ''
    packet = [packet_id, packet_type, packet_body, packet_empty_string] # Skip size for now
    size = packet.pack(@@pack_string[2..]).length # Get packet size by packing what we have and checking length.
    packet.unshift(size)
    # logger.debug("Packet: " << packet.inspect)
    packed = packet.pack(@@pack_string)
    # logger.debug("Packet: " << packet.inspect.utf8 unless hide_content)
    # logger.debug("Packed: " << packed.inspect.utf8 unless hide_content)
    packed
  end

  def delete_socket(socket)
    if socket.nil?
      logger.warn("Tried to delete nil socket!")
      return
    end
    logger.debug("#{socket.remote_host.ljust(21)} Removing socket")
    socket.close rescue nil
    @sockets.delete @sockets.key(socket)
  end

  def reopen_socket(socket)
    ip, port, pass = socket.info
    logger.warn("#{socket.remote_host.ljust(21)} Reopening socket") unless socket.nil?
    delete_socket socket unless socket.nil?
    socket = get_socket_for_host ip, port, pass
    socket
  end

  def send_receive_wrapper(socket, packet, timeout=2, retries=1, sensitive: false)
    logger.debug("#{socket.remote_host.ljust(21)} Attempting to gain mutex lock")
    synchronize(socket.mutex) do
      logger.debug("#{socket.remote_host.ljust(21)} Sucessfully gained mutex lock")
      logger.debug("#{socket.remote_host.ljust(21)} Sending packet: #{sensitive ? 'REDACTED' : packet.inspect.utf8}")
      response = send_receive(socket, packet, timeout, retries, sensitive: sensitive)
      response.gsub!("\x00", '') if response.is_a? String # Int for auth
      logger.debug("#{socket.remote_host.ljust(21)} Got response: #{response.inspect.utf8}")
      logger.debug("#{socket.remote_host.ljust(21)} Ending mutex lock")
      response
    end
  end

  def send_receive(socket, packet, timeout=3, retries=1, sensitive: false)
    begin
      socket.write packet
    rescue Errno::EPIPE # broken pipe
      logger.warn("#{socket.remote_host.ljust(21)} Broken pipe. Reopening socket.")
      socket = reopen_socket socket
      socket.write packet
    end
    logger.debug("#{socket.remote_host.ljust(21)} Receiving response")
    header, _ = if IO.select([socket], nil, nil, timeout)
      socket.recv 12
    end
    if header.to_s.empty?
      delete_socket socket
      raise "#{socket.remote_host.ljust(21)} Nil response for RCON."
    end
    logger.debug("#{socket.remote_host.ljust(21)} Header: #{header.inspect}")
    size, id, type = header.unpack('l<l<l<')
    logger.debug("#{socket.remote_host.ljust(21)} Unpacked header: Size - #{size} | ID - #{id} | Type - #{type}")
    if size.nil? || size.zero?
      logger.error("#{socket.remote_host.ljust(21)} Unexpected header response: #{header.inspect}")
      logger.warn("#{socket.remote_host.ljust(21)} Trying again with a new socket")
      socket = reopen_socket socket
      socket.write packet
      logger.debug("#{socket.remote_host.ljust(21)} Receiving response")
      header, _ = if IO.select([socket], nil, nil, timeout)
        socket.recv 12
      end
      raise "#{socket.remote_host.ljust(21)} Nil response for RCON" if  header.to_s.empty?
      logger.debug("#{socket.remote_host.ljust(21)} Header: #{header.inspect}")
      size, id, type = header.unpack('l<l<l<')
      raise "#{socket.remote_host.ljust(21)} Nil response for RCON" if size.nil? || size.zero?
    end
    logger.debug("#{socket.remote_host.ljust(21)} Reading #{size} (+2) bytes")
    response, _ = if IO.select([socket], nil, nil, timeout)
      socket.recv(size + 2)[0..-3] # Discard last two null bytes
    end
    # Handle retries
    if response.nil?
      if retries > 0
        logger.debug("#{socket.remote_host.ljust(21)} No response; retrying")
        return send_receive(socket, packet, timeout, retries - 1)
      else
        logger.debug("#{socket.remote_host.ljust(21)} No response; no retries remain")
        # Reopen socket? Could harm server if this happens often.
        raise NoTCPResponseError.new socket.remote_host
      end
    end

    logger.debug("#{socket.remote_host.ljust(21)} Read response: #{response.inspect}")

    # Ensure no paginated responses waiting
    # logger.debug("#{socket.remote_host.ljust(21)} Writing empty packet: #{@@empty_packet.inspect}")
    # socket.write @@empty_packet
    # additional_responses = false
    # loop do
    #   additional_header, _ = if IO.select([socket], nil, nil, timeout)
    #     socket.recv 12
    #   end
    #   logger.debug("#{socket.remote_host.ljust(21)} Additional header: #{additional_header.inspect}")
    #   break if additional_header.nil?
    #   size, id, type = additional_header.unpack('l<l<l<')
    #   raise "#{socket.remote_host.ljust(21)} Unexpected additional header response: #{additional_header.inspect}" if size.nil?
    #   # break if size.nil?
    #   if size == 10 # Empty packet
    #     socket.recv(2) # Discard remainder
    #     break
    #   end
    #   logger.debug("#{socket.remote_host.ljust(21)} Unpacked additional header: Size - #{size} | ID - #{id} | Type - #{type}")
    #   break if size == 0
    #   logger.debug("#{socket.remote_host.ljust(21)} Reading additional #{size} (+2) bytes")
    #   additional_response, _ = if IO.select([socket], nil, nil, timeout)
    #     socket.recv(size + 2)[0..-3] # Discard last two null bytes
    #   end
    #   break if additional_header.nil?
    #   logger.debug("#{socket.remote_host.ljust(21)} Read additional response: #{additional_response.inspect}")
    #   additional_responses = true
    #   response = '' if response.nil?
    #   response << additional_response
    # end

    # logger.debug("#{socket.remote_host.ljust(21)} #{additional_responses ? 'Combined r' : 'R'}esponse: #{response.inspect}")
    return response
  rescue Errno::ENOTCONN, Errno::ECONNRESET => e
    logger.warn("#{socket.remote_host.ljust(21)} Remote host closed/reset the connection. #{e.class}: #{e.message}")
    logger.warn("#{socket.remote_host.ljust(21)} Removing closed socket")
    delete_socket socket
    raise e
  end

  # User interface
  def send(server_ip, port, password, command, timeout: 2, retries: 1)
    socket = get_socket_for_host server_ip, port, password
    raise "Couldn't get socket for #{server_ip}:#{port}!" if socket.nil?
    packet = build_packet command
    response = send_receive_wrapper socket, packet, timeout, retries
    response
  end
end

if __FILE__ == $0
  client = RconClient.new
  puts client.send('127.0.0.1', 22222, nil, ARGV.join(' '))
end
