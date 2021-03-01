#!/bin/bash

function log {
  echo "$(date '+%F %T.%6N') | $@"
}

if ! [ -n "$SERVER_NAME" ] ||
   ! [ -n "$SERVER_PORT" ] ||
   ! [ -n "$SERVER_WORLD" ]; then
  log "Required variable is unset:"
  log "SERVER_NAME: $SERVER_NAME"
  log "SERVER_PORT: $SERVER_PORT"
  log "SERVER_WORLD: $SERVER_WORLD"
  exit 1
fi

if [ -n "$VALHEIM_BOT_TOKEN" ]; then
  pushd valheim-bot
    if ! command -v rbenv; then
      ### rbenv with ruby-build plugin
      log "Installing rbenv and ruby-build to mounted volume for Valheim Bot"
      git clone https://github.com/rbenv/rbenv.git ~/.rbenv
      mkdir -p "$(rbenv root)"/plugins
      git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build
      pushd ~/.rbenv
        src/configure
        make -C src
      popd
    else
      log "rbenv detected in mounted volume; skipping install"
    fi
    ### ruby and gems (cached in rbenv volume)
    log "Installing Ruby and required gems for Valheim Bot"
    rbenv install --skip-existing
    rbenv exec gem install bundler
    rbenv exec bundle install
    ### Start a thread that will relaunch the bot if it fails sporadically
    while true; do
      log "Starting Valheim Bot"
      ~/.rbenv/bin/rbenv exec bundle exec ruby valheim-bot.rb
      log "Valheim Bot Stopped"
      sleep 5
    done &
  popd
else
  log "VALHEIM_BOT_TOKEN unset; skipping bot startup"
fi

install_dir=/home/valheim/valheim
mkdir -p "$install_dir"
cd "$install_dir"

while true; do
  log "Downloading Valheim server to $install_dir"
  steamcmd +login anonymous +force_install_dir "$install_dir" +app_update 896660 validate +quit

  log "Copying 64-bit steamclient.so"
  cp linux64/steamclient.so .

  log "Starting Valheim server"
  ./valheim_server.x86_64 \
    -name "$SERVER_NAME" \
    -port "$SERVER_PORT" \
    -world "$SERVER_WORLD" \
    -password "$SERVER_PASSWORD" \
    -public 1

  log "Valheim server stopped. Checking for updates in 5 seconds."
  sleep 5
done
