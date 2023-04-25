#!/bin/bash

function log {
  echo "$(date '+%F %T.%6N') | $*"
}

function cleanup {
  log "Cleaning up subprocesses with SIGINT"
  # Specifically send SIGINT to Ruby as it's a granchild process
  pkill -2 ruby
  # Send SIGINT to all direct descendants (steamcmd, valheim_server)
  pkill -2 $$
  log "Waiting for subprocesses to exit"
  wait
  log "Graceful exit succeeded!"
  exit 0
}
trap cleanup INT TERM

function fail {
  log "ERROR: $*"
  exit 1
}

function install_rbenv {
  pushd ~/.rbenv || fail "Failed to pushd to ~/.rbenv"
    git config --global --add safe.directory '*'
    git init
    git remote add origin https://github.com/rbenv/rbenv.git
    git fetch
    # Force checkout (emulate clone)
    git checkout -f origin/master
    # Get ruby-build plug-in so we can install desired Ruby version
    mkdir -p ~/.rbenv/plugins
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
    src/configure
    make -C src
  popd || fail "Failed to popd"
}

if  [ -z "$SERVER_NAME" ] ||
    [ -z "$SERVER_PORT" ] ||
    [ -z "$SERVER_WORLD" ]; then
  fail "Required variable is unset:
    SERVER_NAME: $SERVER_NAME
    SERVER_PORT: $SERVER_PORT
    SERVER_WORLD: $SERVER_WORLD"
fi

if [ -n "$VALHEIM_BOT_TOKEN" ]; then
  pushd valheim-bot || fail "Failed to pushd to valheim-bot"
    if ! command -v rbenv; then
      ### rbenv with ruby-build plugin
      log "Installing rbenv and ruby-build to mounted volume for Valheim Bot"
      # Can't clone since the directory already exists due to the mount
      install_rbenv
      command -v rbenv || fail "ERROR: Failed to install rbenv"
    else
      log "rbenv detected in mounted volume; skipping install"
    fi
    ### ruby and gems (cached in rbenv volume)
    log "Installing Ruby and required gems for Valheim Bot"
    rbenv install --skip-existing --verbose
    rbenv exec gem install bundler
    ### Start a thread that will relaunch the bot if it fails sporadically or is restarted via command to apply updates
    while true; do
      rbenv exec bundle install
      log "Starting Valheim Bot"
      ~/.rbenv/bin/rbenv exec bundle exec ruby valheim-bot.rb
      export VSH_LAST_EXIT_CODE=$?
      log "Valheim Bot Stopped"
      if [[ $VSH_LAST_EXIT_CODE -eq 43 ]]; then
        break # Container is stopping; bail out
      elif [[ $VSH_LAST_EXIT_CODE -ne 42 ]]; then
        log "Restarting in 5 seconds"
        sleep 5
      fi
    done & # Send this to a background thread so we can proceed to start the server
  popd || fail "Failed to popd"
else
  log "VALHEIM_BOT_TOKEN unset; skipping bot startup"
fi

if [ -n "$VALHEIM_BOT_RCON_PORT" ] then
  # BepInEx https://valheim.thunderstore.io/package/denikson/BepInExPack_Valheim/
  export DOORSTOP_ENABLE=TRUE
  export DOORSTOP_INVOKE_DLL_PATH=./BepInEx/core/BepInEx.Preloader.dll
  export DOORSTOP_CORLIB_OVERRIDE_PATH=./unstripped_corlib
  export LD_LIBRARY_PATH="./doorstop_libs:$LD_LIBRARY_PATH"
  export LD_PRELOAD="libdoorstop_x64.so:$LD_PRELOAD"
fi

install_dir=/home/valheim/valheim
mkdir -p "$install_dir"
cd "$install_dir" || fail "Failed to cd to install dir: $install_dir"

while true; do
  log "Downloading Valheim server to $install_dir"
  steamcmd +force_install_dir "$install_dir" +login anonymous +app_update 896660 validate +quit &
  wait $!

  log "Copying 64-bit steamclient.so"
  mkdir -p /home/valheim/.steam/sdk64/
  cp linux64/steamclient.so /home/valheim/.steam/sdk64/steamclient.so

  log "Starting Valheim server"
  ./valheim_server.x86_64 \
    -name "$SERVER_NAME" \
    -port "$SERVER_PORT" \
    -world "$SERVER_WORLD" \
    -password "$SERVER_PASSWORD" \
    -public 1 & # We need this in the background in order for signals (SIGINT) to arrive
  wait $!

  log "Valheim server stopped. Checking for updates in 5 seconds."
  sleep 5
done
