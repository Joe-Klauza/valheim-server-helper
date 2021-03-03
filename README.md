# Valheim Server Helper
Valheim Server Helper makes running your own Valheim server simple. It comes with an optional Discord bot to help administer the server remotely.

# Prerequisites
- [Docker](https://docs.docker.com/get-docker/) (or [Podman](https://podman.io/getting-started/installation))
- [Docker Compose](https://docs.docker.com/compose/install/) (or [Podman Compose](https://github.com/containers/podman-compose))

# Setup
1. Clone or download this repository
1. Copy `docker-compose.yml` to `docker-compose.override.yml` and modify its contents to suit your needs
1. In a shell where docker-compose is on the `PATH`, build the container:
    - ```bash
      docker-compose build
      ```

# Starting the server
The server is run via `docker-compose`. Several volumes store SteamCMD, `rbenv`, server files, and world files to reduce time needed to restart the container (or run multiple containers). The Discord bot code is also mounted in a volume to allow updates without Valheim server downtime.
1. Run/restart the container (detached)
    - ```bash
      docker-compose up -d --force-recreate
      ```
1. Stop/rm the container
    - ```bash
      docker-compose down
      ```

# Setting up the optional Valheim Discord bot
1. Create a new Application for your Discord account [here](https://discord.com/developers/applications)
1. Create a Bot for your application and copy its secret token, pasting it in the `docker-compose.override.yaml`:
    - ```yaml
      VALHEIM_BOT_TOKEN: YOUR_BOT_TOKEN
      ```
1. Copy the `Client ID` for your application and use it in this URL in your browser to add your bot to your server (replace `YOUR_BOT_CLIENT_ID_HERE`):
    - ```
      https://discord.com/oauth2/authorize?client_id=YOUR_BOT_CLIENT_ID_HERE&scope=bot
      ```
1. Enable Developer Mode in your Discord user settings in `User Settings -> App Settings -> Appearance -> Advanced -> Developer Mode`. This allows you to right-click channels and roles to copy their IDs for the next steps.
1. Create or designate an existing channel for the bot's announcements. Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      VALHEIM_BOT_CHANNEL_ID: 000000000000000000
      ```
1. Create or designate an existing role for sensitive commands (`!restart`, `!restart_bot`). Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      VALHEIM_BOT_ADMIN_ROLE_ID: 000000000000000000
      ```
1. Create or designate an existing role for even more sensitive commands (`!update_bot`). Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      VALHEIM_BOT_OWNER_ROLE_ID: 000000000000000000
      ```
1. If desired, change the bot command prefix character:
    - ```yaml
      VALHEIM_BOT_COMMAND_PREFIX: '!'
      ```
1. Once the container starts, your bot should show as online and be available for commands.

# Valheim Discord bot commands
By default the bot prefix character is `!`.
- `!help`
  - Print command list or get help with a specific command
- `!info`
  - Print server info including name, current player count, type, OS, and version
  - Example:
    ```
    Name: Test
    Current players: 1
    Type: Dedicated
    OS: Linux
    Version: 0.146.11
    ```
- `!players`
  - Print active players. Player names are currently not reported by the server.
  - Example:
    ```
    • Unknown - 00:00:28
    ```
- `!restart`
  - Restart the Valheim server gracefully (via `SIGINT`). Status messages are printed to the designated channel as the server restarts. Server updates are applied during this process.
- `!restart_bot`
  - Restart the Discord bot to apply new source code changes without Valheim server downtime
- `!status`
  - Query whether the server is running (i.e. process still exists via `pgrep`)
- `!update_bot`
  - Download the latest release from this repository and overwrite the contents of the valheim-bot directory with the latest bot files. Requires `!restart_bot` to apply bot source code changes. Note that this does not update the rest of the repository. (TODO: update script)

# Advanced usage

## Running multiple servers
With multiple compose files it's simple to run multiple containers on different port ranges.

### Caveats
- The server files, save location, etc. are on shared mounts between all servers.
  - You must make sure each server has a unique `SERVER_WORLD` to avoid conflicts on causing missing items or progress as servers save their state.
  - You must only update one server at a time (as SteamCMD would conflict with itself if run via multiple containers simultaneously)
    - Subsequent servers' updates will see the updated files and simply validate them
  - Admins and bans must be shared across servers
    - There is no guarantee bans will persist properly when running multiple servers, depending on when the server writes the bans file. (TODO: test this)

### Example

1. Copy `docker-compose.yml` to another file, e.g. `docker-compose-new.yml`
1. Edit `docker-compose-new.yml` to utilize different ports. It is unknown whether changing the internal ports is required (`SERVER_PORT` and latter port in the `ports` entries), but it doesn't hurt:
    - ```yaml
          environment:
            SERVER_PORT: 12456
          ports:
            - "12456:12456/udp"
            - "12457:12457/udp"
            - "12458:12458/udp"
      ```
1. Run your new server using a separate docker-compose project (`-p`) and the configured compose file (`-f`) for compartmentalization:
    - ```bash
      docker-compose -p new -f docker-compose-new.yml up -d
      ```
1. Use the project name and compose file when interacting with that container, e.g. to stop the server:
    - ```bash
      docker-compose -p new -f docker-compose-new.yml down
      ```

# Contact
For discussion, troubleshooting, etc., join us over on the unofficial [Valheim Community Server Hosts Discord](https://discord.gg/wEX7N96WcG)!
