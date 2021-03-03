#!/usr/bin/env ruby
# encoding: UTF-8

require 'discordrb'
require 'pry'
require_relative 'lib/logger'
require_relative 'lib/self-updater'
require_relative 'lib/server-query'

$logger = Logging.logger

Dir.chdir __dir__

bot_token = ENV['VALHEIM_BOT_TOKEN'] || abort('VALHEIM_BOT_TOKEN is undefined')
$valheim_channel_id = ENV['VALHEIM_BOT_CHANNEL_ID'] || abort('VALHEIM_BOT_CHANNEL_ID is undefined')
$admin_role_id = ENV['VALHEIM_BOT_ADMIN_ROLE_ID'] || abort('VALHEIM_BOT_ADMIN_ROLE_ID is undefined')
$owner_role_id = ENV['VALHEIM_BOT_OWNER_ROLE_ID'] || abort('VALHEIM_BOT_OWNER_ROLE_ID is undefined')
players = []
info = {}

PGREP='pgrep valheim_server'
PKILL_INT='pkill -INT valheim_server'

def send_to_channel(message)
    $bot.channel($valheim_channel_id).send(message)
end

def respond(event, message)
    $bot.channel($valheim_channel_id).send message
    event.respond(message) unless event.channel.id.to_s == $valheim_channel_id
end

def log_command_event(event)
    $logger.info("#{event.user.name} (#{event.user.id}) triggered command #{event.command}")
end

def system_no_out(command)
    system(command, :out => File::NULL)
end

def wait_command_success(command)
    # E.g. wait for server process to exist
    waited = 0
    max = 120
    until system_no_out(command) || waited > max
        sleep 1
    end
    waited < max
end

def wait_command_failure(command)
    # E.g. wait for server process to no longer exist
    waited = 0
    max = 120
    until !system_no_out(command) || waited > max
        sleep 1
    end
    waited < max
end

def wait_server_up = wait_command_success(PGREP)
def wait_server_down = wait_command_failure(PGREP)
def interrupt_server = system_no_out(PKILL_INT)

$bot = Discordrb::Commands::CommandBot.new(token: bot_token, prefix: ENV['VALHEIM_BOT_COMMAND_PREFIX'] || '!')

$bot.command :info, description: 'Print server information' do |event|
    log_command_event(event)
    response = ['Server info:', '```']
    info.each do |k, v|
        response.push("#{k.to_s.capitalize.gsub('_', ' ').sub(/^Os$/, 'OS')}: #{v.to_s}")
    end
    response.push('```')
    response.join("\n")
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

$bot.command :players, description: 'Print server players' do |event|
    log_command_event(event)
    current = info[:current_players] ? " (#{info[:current_players]})" : ''
    response = ["Server players#{current}:", '```']
    players.each do |p|
        name = p[:name].to_s.strip.empty? ? "Unknown" : p[:name].to_s.strip
        response.push("  • #{name} - #{p[:duration].to_s}")
    end
    response.push('```')
    response.join("\n")
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

$bot.command :restart, description: 'Restart the server (and apply updates)', required_roles: [$admin_role_id] do |event|
    log_command_event(event)
    send_to_channel("<@#{event.user.id}> (#{event.user.name}) is restarting the server...")
    outcome = "Server #{interrupt_server ?
        'interrupt successfully sent. Waiting for server to gracefully exit...' :
        '`pkill` command failed! Is the server running?'}"
    respond(event, outcome)

    outcome = "Server #{wait_server_down() ?
        'stopped successfully. Any pending updates will apply and the server will restart. This channel will receive a notification when the server is online.' :
        'Failed to detect server stopping. Is it stuck?'}"
    respond(event, outcome)

    outcome = wait_server_up() ? "Server is back up!" : "Failed to detect server within the time limit."
    respond(event, outcome)
    nil
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

$bot.command :restart_bot, description: 'Restart the bot (apply changes from update)', required_roles: [$admin_role_id] do |event|
    log_command_event(event)
    send_to_channel("<@#{event.user.id}> (#{event.user.name}) is restarting me...")
    exit 42
    nil
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

$bot.command :status, description: 'Check if server is online' do |event|
    log_command_event(event)
    event.respond system_no_out(PGREP) ? "Server is online!" : "Server is offline!"
    nil
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

$bot.command :update_bot, description: 'Update valheim-bot to the latest available version on GitHub. This will only overwrite files in the valheim-bot directory.', required_roles: [$owner_role_id] do |event|
    log_command_event(event)
    send_to_channel("<@#{event.user.id}> (#{event.user.name}) is updating the bot...")
    begin
        version = SelfUpdater.update_to_latest(only_files_in_dir: 'valheim-bot')
        respond(event, "Update to #{version} succeeded! :tada:\nReview the latest patch notes here: <https://github.com/Joe-Klauza/valheim-server-helper/releases/tag/#{version}>")
        respond(event, ":notebook_with_decorative_cover: **Note:** Please `#{$bot.prefix}restart_bot` to apply bot changes. Other changes (such as those to docker-compose.yml, entrypoint.sh) must be downloaded and applied manually.")
    rescue => e
        $logger.error(e)
        respond(event, "Failed to update the bot: (#{e.class}) #{e.message}")
    end
    nil
rescue => e
    $logger.error(e)
    "(#{e.class}) #{e.message}"
end

begin
    Thread.new do
        # Allow server to start
        $logger.info('Server monitor waiting for server to start')
        wait_server_up()
        while true
            begin
                ip = '127.0.0.1'
                port = ENV['SERVER_PORT'].to_i + 1
                info = ServerQuery::a2s_info(ip, port) || info
                players = ServerQuery::a2s_player(ip, port) || players
                sleep 10
            rescue => e
                $logger.warn(e)
            end
        end
    end
    $logger.info('Starting Valheim Bot now')
    $bot.run(true) # Daemonize (thread)
    $bot.online
    $logger.info('Valheim Bot started')
    at_exit do
        $logger.info('Stopping Valheim Bot')
        $bot.invisible
        $bot.stop
        $logger.info('Valheim Bot stopped')
    end
    if ENV['VSH_LAST_EXIT_CODE'] == '42'
        send_to_channel("I'm back! :wave:")
    end
    sleep
rescue SignalException => e
    $logger.debug(e)
    exit 43
rescue => e
    $logger.error(e)
end
