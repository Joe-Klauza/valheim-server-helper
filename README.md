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

# Setting up the Valheim Discord bot
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
1. Create or designate an existing role for sensitive commands (`/restart`, `/restart_bot`). Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      VALHEIM_BOT_ADMIN_ROLE_ID: 000000000000000000
      ```

# Valheim Discord bot commands
- `help`
  - Print command list
- `info`
  - Print server info including name, current player count, type, OS, and version
  - Example:
    ```
    Name: Test
    Current players: 1
    Type: Dedicated
    OS: Linux
    Version: 0.146.11
    ```
- `players`
  - Print active players. Player names are currently not reported by the server.
  - Example:
    ```
    • Unknown - 00:00:28
    ```
- `restart`
  - Restart the Valheim server gracefully (via `SIGINT`). Status messages are printed to the designated channel as the server restarts. Server updates are applied during this process.
- `restart_bot`
  - Restart the Discord bot to apply new source code changes without Valheim server downtime
- `status`
  - Query whether the server is running (i.e. process still exists via `pgrep`)
