#!/usr/bin/env ruby

require 'socket'
require_relative 'logger'

# https://developer.valvesoftware.com/wiki/Server_queries
# https://apidock.com/ruby/Array/pack
# https://apidock.com/ruby/String/unpack

class NoUDPResponseError < StandardError
    def initialize(host=nil)
        super "Could not read a UDP response from server#{host ? " #{host}" : '!'}"
    end
end

class ServerQuery
    include Logging

    def self.send_recv_udp(packet, server_ip, server_port, socket_opts: 0, timeout: 2, retries: 1)
        s = UDPSocket.new
        s.send(packet, socket_opts, server_ip, server_port)
        resp, from = if IO.select([s], nil, nil, timeout)
            s.recvfrom(60000)
        end
        if resp.nil?
            if retries > 0
                s.close
                return send_recv_udp(packet, server_ip, server_port, socket_opts: socket_opts, timeout: timeout, retries: retries - 1)
            else
                raise NoUDPResponseError.new "#{server_ip}:#{server_port}"
            end
        end
        return resp, from
    ensure
        s.close
    end

    def self.a2s_info(server_ip, server_port)
        # https://developer.valvesoftware.com/wiki/Server_queries#A2S_INFO
        a2s_info_header = 0x54
        content = "Source Engine Query\0"
        packet = [0xFF, 0xFF, 0xFF, 0xFF, a2s_info_header, content].pack('c5Z*')

        resp, _ = send_recv_udp(packet, server_ip, server_port)
        data = resp.unpack('xxxxccZ*Z*Z*Z*s_cccZZccZ*xxxxxxxxxxxZ*')
        type = case data[10]
            when 'd'
                'Dedicated'
            when 'l'
                'Listen'
            when 'p'
                'Proxy'
            else
                data[10]
            end

        os = case data[11]
            when 'w'
                'Windows'
            when 'l'
                'Linux'
            when 'm'
                'macOS'
            when 'o'
                'macOS'
            else
                data[11]
            end

        {
            name: data[2],
            #map: data[3] # Unfortunately just the server name repeated
            current_players: data[7],
            type: type,
            os: os,
            version: data[15],
        }
    rescue NoUDPResponseError => e
        logger.warn "(#{e.class}): #{e}"
        nil
    rescue => e
        logger.error "[#{server_ip}:#{server_port}] Rescued error while querying info: (#{e.class}) #{e}"
        nil
    end

    def self.a2s_player(server_ip, server_port)
        # https://developer.valvesoftware.com/wiki/Server_queries#A2S_PLAYER
        players = []
            packet = [0xFF, 0xFF, 0xFF, 0xFF, 0x55, -1].pack('cccccl_')
            resp, _ = send_recv_udp(packet, server_ip, server_port)
            if resp.unpack('xxxxcl').first == 65 # Challenge detected ('A' response); request again with given long
                packet = [0xFF, 0xFF, 0xFF, 0xFF, 0x55, resp.unpack('xxxxcl').last].pack('cccccl')
                resp, _ = send_recv_udp(packet, server_ip, server_port)
            end
            resp = resp[6..] # Remove padding, header, player count
            until resp.empty?
                begin
                    pack_string = 'xZ*lf'
                    player_data = resp.unpack(pack_string)
                    resp = resp[player_data.pack(pack_string).length..] # Remove the read player info so we can iterate through the response (arbitrary length)
                    player_info = {
                        :name => player_data[0].to_s.strip, # Can be empty
                        :score => player_data[1],
                        :duration => Time.at(player_data[2]).utc.strftime("%H:%M:%S"),
                    }
                    players << player_info
                rescue StandardError => e
                    logger.error "[#{server_ip}:#{server_port}] Rescued error while iterating players: (#{e.class}): #{e}"
                    break
                end
            end
            players
    rescue NoUDPResponseError => e
        logger.warn "(#{e.class}): #{e}"
        nil
    rescue => e
        logger.error "[#{server_ip}:#{server_port}] Rescued error while querying players: (#{e.class}): #{e}"
        nil
    end
end

if __FILE__ == $0
    ip = '127.0.0.1'
    port = '24572'
    puts 'INFO: ' + ServerQuery::a2s_info(ip, port).inspect
    puts 'PLAYERS: ' + ServerQuery::a2s_player(ip, port).inspect
end
